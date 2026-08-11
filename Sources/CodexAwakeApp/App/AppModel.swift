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
    @Published var codexDesktopRunning = false
    @Published var codexDesktopActiveSessionIDs: Set<String> = []
    @Published var keepAwakeForCodexDesktop: Bool
    @Published var workspacePath: String?
    @Published var chatMessages: [CodexChatMessage] = []
    @Published var chatThreadID: String?
    @Published var chatTurnID: String?
    @Published var chatIsSending = false
    @Published var approvalRequests: [CodexApprovalRequest] = []

    let diagnostics = DiagnosticsStore()
    private let logger = Logger(subsystem: "com.melnikoleg.CodexAwake", category: "App")
    private let tracker = ThreadActivityTracker()
    private let desktopRolloutScanner = CodexDesktopRolloutScanner()
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
    private var desktopActivityTask: Task<Void, Never>?
    private var workspaceObserverTokens: [NSObjectProtocol] = []
    private var codexDesktopLaunchDate: Date?
    private var isShuttingDown = false
    private var chatGenerationID: UUID?
    private var approvalContinuations: [Int: CheckedContinuation<JSONValue, Never>] = [:]
    private var lastEventAt: Date?
    private var lastReconciliationAt: Date?
    private let startedAt = Date()

    init(defaults: UserDefaults = .standard) {
        let auto = defaults.object(forKey: "AutoKeepAwake") as? Bool ?? true
        let keepForDesktop = defaults.object(forKey: "KeepAwakeForCodexDesktop") as? Bool ?? true
        autoKeepAwake = auto
        keepAwakeForCodexDesktop = keepForDesktop
        firstRunAcknowledged = defaults.bool(forKey: "FirstRunAcknowledged")
        if let savedWorkspace = defaults.string(forKey: "CodexWorkspacePath"),
           FileManager.default.fileExists(atPath: savedWorkspace) {
            workspacePath = savedWorkspace
        } else {
            workspacePath = nil
        }
        coordinator = AwakeCoordinator(
            power: power,
            autoKeepAwake: auto,
            keepAwakeForCodexDesktop: keepForDesktop
        )
        launchAtLogin = launchManager.isEnabled
    }

    func start() {
        guard connectionLoopTask == nil else { return }
        logger.notice("CodexAwake lifecycle started")
        startCodexDesktopMonitoring()
        startCodexDesktopActivityMonitoring()
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
            cancelPendingApprovals()
            markChatDisconnected("The managed Codex server was stopped.")
            connectionLoopTask?.cancel()
            connectionLoopTask = nil
            await client?.disconnect()
            client = nil
            await supervisor.stop()
        }
    }

    func restartServer() {
        Task {
            cancelPendingApprovals()
            markChatDisconnected("The managed Codex server is restarting.")
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

    func setKeepAwakeForCodexDesktop(_ enabled: Bool) {
        keepAwakeForCodexDesktop = enabled
        UserDefaults.standard.set(enabled, forKey: "KeepAwakeForCodexDesktop")
        Task {
            await coordinator.setKeepAwakeForCodexDesktop(enabled)
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

    var totalActiveSessionCount: Int {
        activity.activeCount + codexDesktopActiveSessionIDs.count
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

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Choose a project for Codex"
        panel.prompt = "Use Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let workspacePath {
            panel.directoryURL = URL(fileURLWithPath: workspacePath)
        }
        if panel.runModal() == .OK, let path = panel.url?.standardizedFileURL.path {
            workspacePath = path
            UserDefaults.standard.set(path, forKey: "CodexWorkspacePath")
            newChat()
        }
    }

    @discardableResult
    func sendPrompt(_ prompt: String) -> Bool {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatIsSending else { return false }
        guard let workspacePath, appServerState == .running, let client else {
            appendSystemMessage(chatUnavailableReason ?? "Codex is not ready yet.")
            return false
        }

        let generationID = UUID()
        chatGenerationID = generationID
        chatIsSending = true
        chatMessages.append(.init(role: .user, text: text))

        Task {
            do {
                var threadID = chatThreadID
                if threadID == nil {
                    threadID = try await client.startThread(cwd: workspacePath)
                    guard chatGenerationID == generationID else { return }
                    chatThreadID = threadID
                }
                guard let threadID else { throw CodexAwakeError.malformedMessage }
                let turnID = try await client.startTurn(threadId: threadID, text: text, cwd: workspacePath)
                guard chatGenerationID == generationID else { return }
                chatTurnID = turnID
            } catch {
                guard chatGenerationID == generationID else { return }
                chatGenerationID = nil
                chatIsSending = false
                appendSystemMessage(SafeDisplay.sanitizedError(error))
            }
        }
        return true
    }

    func interruptChat() {
        guard let client, let threadID = chatThreadID, let turnID = chatTurnID else { return }
        Task {
            do {
                try await client.interruptTurn(threadId: threadID, turnId: turnID)
            } catch {
                appendSystemMessage(SafeDisplay.sanitizedError(error))
            }
        }
    }

    func newChat() {
        if let client, let threadID = chatThreadID, let turnID = chatTurnID {
            Task { try? await client.interruptTurn(threadId: threadID, turnId: turnID) }
        }
        chatGenerationID = nil
        chatThreadID = nil
        chatTurnID = nil
        chatIsSending = false
        chatMessages.removeAll()
    }

    func resolveApproval(_ request: CodexApprovalRequest, decision: CodexApprovalDecision) {
        approvalRequests.removeAll { $0.id == request.id }
        approvalContinuations.removeValue(forKey: request.id)?.resume(returning: .string(decision.rawValue))
    }

    func requestQuit() {
        NSApplication.shared.terminate(nil)
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        stopCodexDesktopMonitoring()
        desktopActivityTask?.cancel()
        desktopActivityTask = nil
        cancelPendingApprovals()
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

    var chatUnavailableReason: String? {
        if workspacePath == nil {
            return "Choose a project folder before sending a message."
        }
        if appServerState != .running {
            if codexPath == nil {
                return "Codex runtime is not ready. Restart the server or choose a Codex binary in Diagnostics."
            }
            return "Codex App Server is \(appServerState.rawValue). Wait for READY or press Restart."
        }
        if client == nil {
            return "Codex is connecting. Try again in a moment."
        }
        return nil
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
                    serverRequestHandler: { [weak self] request in
                        await self?.handleServerRequest(request)
                    },
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
        switch event {
        case .agentMessageDelta, .agentMessageCompleted, .runtimeError, .ignored:
            handleChatEvent(event)
            return
        default:
            break
        }

        let snapshot = await tracker.apply(event)
        await coordinator.update(snapshot)
        activity = snapshot
        handleChatEvent(event)
        if case .unknown = event {
            if let client { await reconcile(using: client) }
        } else {
            await refreshPublishedState()
        }
    }

    private func handleDisconnect(_ reason: String) async {
        guard !isShuttingDown else { return }
        lastSafeError = String(reason.prefix(300))
        cancelPendingApprovals()
        markChatDisconnected("Connection to the managed Codex server was lost.")
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
        value.appVersion = "1.2.1 (4)"
        value.architecture = Self.architecture
        value.codexPath = codexPath
        value.codexVersion = codexVersion
        value.codexDesktopRunning = codexDesktopRunning
        value.codexDesktopActiveSessionIDs = codexDesktopActiveSessionIDs
        value.keepAwakeForCodexDesktop = keepAwakeForCodexDesktop
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

    private func startCodexDesktopMonitoring() {
        guard workspaceObserverTokens.isEmpty else {
            refreshCodexDesktopPresence()
            return
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshCodexDesktopPresence() }
            }
            workspaceObserverTokens.append(token)
        }
        refreshCodexDesktopPresence()
    }

    private func startCodexDesktopActivityMonitoring() {
        guard desktopActivityTask == nil else { return }
        desktopActivityTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshCodexDesktopActivity()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func stopCodexDesktopMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceObserverTokens { center.removeObserver(token) }
        workspaceObserverTokens.removeAll()
    }

    private func refreshCodexDesktopPresence() {
        let supportedBundleIDs: Set<String> = ["com.openai.codex", "com.openai.chat"]
        let applications = NSWorkspace.shared.runningApplications.filter { application in
            application.bundleIdentifier.map(supportedBundleIDs.contains) ?? false
        }
        let running = !applications.isEmpty
        codexDesktopRunning = running
        codexDesktopLaunchDate = applications.compactMap(\.launchDate).max()
        if !running {
            codexDesktopActiveSessionIDs = []
        }
        Task {
            await coordinator.setCodexDesktopRunning(running)
            if !running { await coordinator.setCodexDesktopActiveCount(0) }
            await refreshPublishedState()
        }
    }

    private func refreshCodexDesktopActivity() async {
        guard codexDesktopRunning else {
            if !codexDesktopActiveSessionIDs.isEmpty {
                codexDesktopActiveSessionIDs = []
                await coordinator.setCodexDesktopActiveCount(0)
                await refreshPublishedState()
            }
            return
        }

        let scanner = desktopRolloutScanner
        let launchDate = codexDesktopLaunchDate
        let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        let sessions = await Task.detached(priority: .utility) {
            scanner.activeSessions(in: sessionsRoot, desktopLaunchDate: launchDate)
        }.value
        guard !Task.isCancelled else { return }

        let ids = Set(sessions.map(\.id))
        if ids != codexDesktopActiveSessionIDs {
            codexDesktopActiveSessionIDs = ids
            await coordinator.setCodexDesktopActiveCount(ids.count)
            await refreshPublishedState()
        }
    }

    private func handleChatEvent(_ event: AppServerEvent) {
        switch event {
        case .agentMessageDelta(let threadID, _, let itemID, let delta):
            guard threadID == chatThreadID else { return }
            if let index = chatMessages.firstIndex(where: { $0.itemId == itemID }) {
                chatMessages[index].text += delta
                chatMessages[index].isStreaming = true
            } else {
                chatMessages.append(.init(
                    role: .assistant,
                    text: delta,
                    itemId: itemID,
                    isStreaming: true
                ))
            }

        case .agentMessageCompleted(let threadID, _, let itemID, let text, let phase):
            guard threadID == chatThreadID else { return }
            if let index = chatMessages.firstIndex(where: { $0.itemId == itemID }) {
                chatMessages[index].text = text
                chatMessages[index].phase = phase
                chatMessages[index].isStreaming = false
            } else {
                chatMessages.append(.init(
                    role: .assistant,
                    text: text,
                    itemId: itemID,
                    phase: phase
                ))
            }

        case .turnCompleted(let key, let status):
            guard key.threadId == chatThreadID,
                  chatTurnID == nil || key.turnId == chatTurnID else { return }
            chatGenerationID = nil
            chatTurnID = nil
            chatIsSending = false
            for index in chatMessages.indices where chatMessages[index].isStreaming {
                chatMessages[index].isStreaming = false
            }
            if let status, status != "completed", status != "interrupted" {
                appendSystemMessage("Codex turn ended with status: \(status).")
            }

        case .runtimeError(let threadID, let message):
            guard threadID == nil || threadID == chatThreadID else { return }
            appendSystemMessage(message)

        default:
            break
        }
    }

    private func handleServerRequest(_ request: AppServerServerRequest) async -> JSONValue? {
        let kind: CodexApprovalKind
        switch request.method {
        case "item/commandExecution/requestApproval": kind = .command
        case "item/fileChange/requestApproval": kind = .fileChange
        default: return nil
        }

        let approval = CodexApprovalRequest(
            id: request.id,
            kind: kind,
            title: approvalTitle(kind: kind, params: request.params),
            detail: approvalDetail(kind: kind, params: request.params),
            threadId: request.params?["threadId"]?.stringValue,
            turnId: request.params?["turnId"]?.stringValue
        )
        return await withCheckedContinuation { continuation in
            approvalRequests.append(approval)
            approvalContinuations[request.id] = continuation
        }
    }

    private func approvalTitle(kind: CodexApprovalKind, params: JSONValue?) -> String {
        if let host = params?["networkApprovalContext"]?["host"]?.stringValue {
            return "Allow network access to \(host)?"
        }
        return kind == .command ? "Allow this command?" : "Allow these file changes?"
    }

    private func approvalDetail(kind: CodexApprovalKind, params: JSONValue?) -> String {
        if let reason = params?["reason"]?.stringValue, !reason.isEmpty {
            return String(reason.prefix(600))
        }
        if kind == .command {
            if let command = params?["command"]?.stringValue {
                return String(command.prefix(600))
            }
            if let command = params?["command"]?.arrayValue?.compactMap(\.stringValue), !command.isEmpty {
                return String(command.joined(separator: " ").prefix(600))
            }
            return "Codex wants to run a command in the selected workspace."
        }
        if let root = params?["grantRoot"]?.stringValue {
            return "Codex wants to write inside \(root)."
        }
        return "Codex wants to apply file changes in the selected workspace."
    }

    private func cancelPendingApprovals() {
        let continuations = approvalContinuations.values
        approvalContinuations.removeAll()
        approvalRequests.removeAll()
        for continuation in continuations {
            continuation.resume(returning: .string(CodexApprovalDecision.cancel.rawValue))
        }
    }

    private func markChatDisconnected(_ message: String) {
        guard chatIsSending else { return }
        chatGenerationID = nil
        chatTurnID = nil
        chatIsSending = false
        appendSystemMessage(message)
    }

    private func appendSystemMessage(_ text: String) {
        guard chatMessages.last?.role != .system || chatMessages.last?.text != text else { return }
        chatMessages.append(.init(role: .system, text: String(text.prefix(500))))
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
