import AppKit
import CodexAwakeCore
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    @Published var appServerState: AppServerState = .stopped
    @Published var codexPath: String?
    @Published var codexVersion: String?
    @Published var endpoint: String?
    @Published var serverPID: Int32?
    @Published var activity = ActivitySnapshot()
    @Published var assertionHeld = false
    @Published var lastSafeError: String?
    @Published var reconnectCount = 0
    @Published var launchAtLogin = false
    @Published var firstRunAcknowledged: Bool
    @Published var autoKeepAwake: Bool

    let diagnostics = DiagnosticsStore()
    private let logger = Logger(subsystem: "com.melnikoleg.CodexAwake", category: "App")
    private let tracker = ThreadActivityTracker()
    private let power = PowerAssertionManager()
    private let coordinator: AwakeCoordinator
    private let binaryLocator = CodexBinaryLocator()
    private let socketManager = SocketPathManager()
    private let launchManager = LaunchAtLoginManager()
    private lazy var supervisor = AppServerSupervisor { [weak self] state, pid in
        await self?.handleSupervisorState(state, pid: pid)
    }
    private var client: AppServerClient?
    private var runtime: SocketPathManager.Runtime?
    private var connectionLoopTask: Task<Void, Never>?
    private var isShuttingDown = false
    private var lastEventAt: Date?
    private var lastReconciliationAt: Date?
    private let startedAt = Date()

    init(defaults: UserDefaults = .standard) {
        let auto = defaults.object(forKey: "AutoKeepAwake") as? Bool ?? true
        autoKeepAwake = auto
        firstRunAcknowledged = defaults.bool(forKey: "FirstRunAcknowledged")
        coordinator = AwakeCoordinator(power: power, autoKeepAwake: auto)
        launchAtLogin = launchManager.isEnabled
    }

    func start() {
        guard connectionLoopTask == nil else { return }
        logger.notice("CodexAwake lifecycle started")
        Task { await startManagedServer() }
    }

    func startManagedServer() async {
        isShuttingDown = false
        do {
            let info = try await binaryLocator.locate()
            let runtime = try socketManager.runtime()
            self.codexPath = info.path
            self.codexVersion = info.version
            self.runtime = runtime
            endpoint = runtime.endpoint
            lastSafeError = nil
            try await supervisor.start(binaryPath: info.path, runtime: runtime)
            beginConnectionLoopIfNeeded()
        } catch {
            record(error)
            appServerState = .failed
            await refreshPublishedState()
        }
    }

    func stopServer() {
        Task {
            connectionLoopTask?.cancel()
            connectionLoopTask = nil
            await client?.disconnect()
            client = nil
            await supervisor.stop()
        }
    }

    func restartServer() {
        Task {
            await client?.disconnect()
            client = nil
            do {
                try await supervisor.restart()
                beginConnectionLoopIfNeeded()
            } catch { record(error) }
        }
    }

    func setAutoKeepAwake(_ enabled: Bool) {
        autoKeepAwake = enabled
        UserDefaults.standard.set(enabled, forKey: "AutoKeepAwake")
        Task {
            await coordinator.setAutoKeepAwake(enabled)
            await refreshPublishedState()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchManager.setEnabled(enabled)
            launchAtLogin = launchManager.isEnabled
        } catch {
            launchAtLogin = launchManager.isEnabled
            record(error)
        }
    }

    func acknowledgeFirstRun() {
        firstRunAcknowledged = true
        UserDefaults.standard.set(true, forKey: "FirstRunAcknowledged")
    }

    var codexCommand: String? {
        guard let codexPath, let endpoint else { return nil }
        return CodexCommandBuilder.command(binaryPath: codexPath, endpoint: endpoint)
    }

    func copyCodexCommand() {
        guard let codexCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(codexCommand, forType: .string)
    }

    func openCodex() {
        guard let codexPath, let endpoint else { return }
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("CodexAwake", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
            let helper = support.appendingPathComponent("Open Managed Codex.command")
            try CodexCommandBuilder.helperContents(binaryPath: codexPath, endpoint: endpoint)
                .write(to: helper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            NSWorkspace.shared.open(helper)
        } catch { record(error) }
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics.snapshot.sanitizedText, forType: .string)
    }

    func chooseCodexBinary() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Codex CLI executable"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let path = panel.url?.path {
            do {
                try binaryLocator.saveUserSelectedPath(path)
                Task {
                    connectionLoopTask?.cancel()
                    connectionLoopTask = nil
                    await client?.disconnect()
                    client = nil
                    await supervisor.stop()
                    await startManagedServer()
                }
            } catch { record(error) }
        }
    }

    func requestQuit() {
        NSApplication.shared.terminate(nil)
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        connectionLoopTask?.cancel()
        connectionLoopTask = nil
        await client?.disconnect()
        client = nil
        await supervisor.stop()
        await coordinator.shutdown()
        assertionHeld = false
        logger.notice("CodexAwake lifecycle stopped")
    }

    private func beginConnectionLoopIfNeeded() {
        guard connectionLoopTask == nil else { return }
        connectionLoopTask = Task { [weak self] in await self?.connectionLoop() }
    }

    private func connectionLoop() async {
        var attempt = 0
        while !Task.isCancelled, !isShuttingDown {
            guard let runtime else { break }
            do {
                while !FileManager.default.fileExists(atPath: runtime.socket.path), !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard !Task.isCancelled else { break }
                let newClient = AppServerClient(
                    endpoint: runtime.endpoint,
                    socketPath: runtime.socket.path,
                    eventHandler: { [weak self] event in await self?.handle(event) },
                    disconnectHandler: { [weak self] reason in await self?.handleDisconnect(reason) }
                )
                try await newClient.connect()
                client = newClient
                attempt = 0
                appServerState = .running
                lastSafeError = nil
                await reconcile(using: newClient)

                while await newClient.isConnected, !Task.isCancelled {
                    try await Task.sleep(for: .seconds(10))
                    if await newClient.isConnected { await reconcile(using: newClient) }
                }
            } catch is CancellationError {
                break
            } catch {
                record(error)
                let unknown = await tracker.markConnectionUnknown()
                await coordinator.update(unknown)
                activity = unknown
            }
            guard !Task.isCancelled, !isShuttingDown else { break }
            reconnectCount += 1
            appServerState = .reconnecting
            attempt += 1
            let delay = min(pow(2.0, Double(attempt - 1)), 10.0)
            try? await Task.sleep(for: .seconds(delay))
        }
        connectionLoopTask = nil
    }

    private func handle(_ event: AppServerEvent) async {
        lastEventAt = Date()
        let snapshot = await tracker.apply(event)
        await coordinator.update(snapshot)
        activity = snapshot
        if case .unknown = event {
            if let client { await reconcile(using: client) }
        } else {
            await refreshPublishedState()
        }
    }

    private func handleDisconnect(_ reason: String) async {
        guard !isShuttingDown else { return }
        lastSafeError = String(reason.prefix(300))
        let unknown = await tracker.markConnectionUnknown()
        await coordinator.update(unknown)
        activity = unknown
        appServerState = .reconnecting
        await refreshPublishedState()
    }

    private func reconcile(using client: AppServerClient) async {
        do {
            let reconciled = try await client.reconcileStatuses()
            let snapshot = await tracker.reconcile(loadedThreadIds: reconciled.loaded, statuses: reconciled.statuses)
            lastReconciliationAt = Date()
            activity = snapshot
            await coordinator.update(snapshot)
            await refreshPublishedState()
        } catch {
            record(error)
        }
    }

    private func handleSupervisorState(_ state: AppServerState, pid: Int32?) {
        appServerState = state
        serverPID = pid
        if state == .stopped || state == .failed {
            Task {
                let snapshot = await tracker.confirmServerStopped()
                await coordinator.serverConfirmedStopped()
                activity = snapshot
                await refreshPublishedState()
            }
        }
        updateDiagnostics()
    }

    private func record(_ error: Error) {
        lastSafeError = SafeDisplay.sanitizedError(error)
        logger.error("Safe error: \(self.lastSafeError ?? "unknown", privacy: .public)")
        updateDiagnostics()
    }

    private func refreshPublishedState() async {
        assertionHeld = await coordinator.assertionIsHeld()
        updateDiagnostics()
    }

    private func updateDiagnostics() {
        var value = DiagnosticsSnapshot()
        value.appVersion = "1.0.0 (1)"
        value.architecture = Self.architecture
        value.codexPath = codexPath
        value.codexVersion = codexVersion
        value.endpoint = endpoint
        value.appServerState = appServerState
        value.serverPID = serverPID
        value.startedAt = startedAt
        value.activity = activity
        value.assertionHeld = assertionHeld
        value.lastEventAt = lastEventAt
        value.lastReconciliationAt = lastReconciliationAt
        value.reconnectCount = reconnectCount
        value.lastSafeError = lastSafeError
        diagnostics.snapshot = value
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
