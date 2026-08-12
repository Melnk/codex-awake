import AppKit
import CodexAwakeCore
import Combine
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
    @Published var closedLidProtectionEnabled: Bool
    @Published var closedLidProtection = ClosedLidProtectionSnapshot()
    @Published var closedLidActionMessage: String?
    @Published var closedLidHelperActionInProgress = false
    @Published var workspacePath: String?
    @Published var interfaceTheme: InterfaceTheme
    @Published var appLanguage: AppLanguage

    let diagnostics = DiagnosticsStore()
    let chat: CodexChatSession
    private let logger = Logger(subsystem: "com.melnikoleg.CodexAwake", category: "App")
    private let tracker = ThreadActivityTracker()
    private let preferences: any AppPreferencesStoring
    private let desktopMonitor = CodexDesktopMonitor()
    private let power: PowerProtectionManager
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
    private var closedLidStatusTask: Task<Void, Never>?
    private var chatObservation: AnyCancellable?
    private var isShuttingDown = false
    private var lastEventAt: Date?
    private var lastReconciliationAt: Date?
    private let startedAt = Date()

    init(preferences: any AppPreferencesStoring = UserDefaultsAppPreferences()) {
        self.preferences = preferences
        let auto = preferences.autoKeepAwake
        let keepForDesktop = preferences.keepAwakeForCodexDesktop
        let closedLid = preferences.closedLidProtectionEnabled
        interfaceTheme =
            InterfaceTheme(
                rawValue: preferences.interfaceTheme ?? ""
            ) ?? .light
        let selectedLanguage =
            AppLanguage(
                rawValue: preferences.appLanguage ?? ""
            ) ?? .systemDefault
        appLanguage = selectedLanguage
        chat = CodexChatSession(language: selectedLanguage)
        autoKeepAwake = auto
        keepAwakeForCodexDesktop = keepForDesktop
        closedLidProtectionEnabled = closedLid
        firstRunAcknowledged = preferences.firstRunAcknowledged
        if let savedWorkspace = preferences.workspacePath,
            FileManager.default.fileExists(atPath: savedWorkspace)
        {
            workspacePath = savedWorkspace
        } else {
            workspacePath = nil
        }
        let power = PowerProtectionManager(closedLidRequested: closedLid)
        self.power = power
        coordinator = AwakeCoordinator(
            power: power,
            autoKeepAwake: auto,
            keepAwakeForCodexDesktop: keepForDesktop
        )
        launchAtLogin = launchManager.isEnabled
        chatObservation = chat.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func start() {
        guard connectionLoopTask == nil else { return }
        logger.notice("CodexAwake lifecycle started")
        desktopMonitor.start { [weak self] snapshot in
            self?.handleCodexDesktopSnapshot(snapshot)
        }
        startClosedLidStatusMonitoring()
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
            chat.cancelPendingApprovals()
            chat.markDisconnected(
                t("The managed Codex server was stopped.", "Управляемый сервер Codex остановлен."))
            connectionLoopTask?.cancel()
            connectionLoopTask = nil
            await client?.disconnect()
            client = nil
            await supervisor.stop()
        }
    }

    func restartServer() {
        Task {
            chat.cancelPendingApprovals()
            chat.markDisconnected(
                t("The managed Codex server is restarting.", "Управляемый сервер Codex перезапускается."))
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
        preferences.setAutoKeepAwake(enabled)
        Task {
            await coordinator.setAutoKeepAwake(enabled)
            await refreshPublishedState()
        }
    }

    func setInterfaceTheme(_ theme: InterfaceTheme) {
        interfaceTheme = theme
        preferences.setInterfaceTheme(theme.rawValue)
    }

    func setAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        chat.setLanguage(language)
        preferences.setAppLanguage(language.rawValue)
        if closedLidProtection.leaseActive {
            closedLidActionMessage = t(
                "Closed-Lid lease active. The display may be closed.",
                "Аренда Closed-Lid активна. Крышку можно закрыть.")
        } else if closedLidProtectionEnabled {
            closedLidActionMessage = t(
                "Closed-Lid armed; the lease starts with sleep protection.",
                "Closed-Lid готов; аренда начнётся вместе с защитой от сна.")
        } else {
            closedLidActionMessage = nil
        }
    }

    func setKeepAwakeForCodexDesktop(_ enabled: Bool) {
        keepAwakeForCodexDesktop = enabled
        preferences.setKeepAwakeForCodexDesktop(enabled)
        Task {
            await coordinator.setKeepAwakeForCodexDesktop(enabled)
            await refreshPublishedState()
        }
    }

    func setClosedLidProtectionEnabled(_ enabled: Bool) {
        closedLidProtectionEnabled = enabled
        preferences.setClosedLidProtectionEnabled(enabled)
        closedLidActionMessage =
            enabled
            ? t(
                "Closed-Lid requested. Install the helper if it is not ready.",
                "Режим закрытой крышки запрошен. Если helper не готов, установите его.")
            : t(
                "Closed-Lid disabled; normal lid sleep is restored.",
                "Режим закрытой крышки выключен; обычный сон восстановлен.")
        Task {
            do {
                try await power.setClosedLidRequested(enabled)
            } catch {
                record(error)
            }
            closedLidProtection = await power.refreshClosedLidStatus()
            updateDiagnostics()
        }
    }

    func installClosedLidHelper() {
        guard !closedLidHelperActionInProgress else { return }
        closedLidHelperActionInProgress = true
        closedLidActionMessage = t(
            "Checking the existing helper before requesting administrator access…",
            "Проверяем установленный helper перед запросом прав администратора…")

        Task {
            let status = await power.refreshClosedLidStatus(retryIfNeeded: false)
            closedLidProtection = status
            guard !status.helperInstalled || !status.helperReachable else {
                closedLidActionMessage = t(
                    "Closed-Lid helper is already ready. No password is required.",
                    "Closed-Lid helper уже готов. Пароль не требуется.")
                closedLidHelperActionInProgress = false
                updateDiagnostics()
                return
            }

            openClosedLidHelperCommand(
                resource: "install-closed-lid-helper",
                title: t("Installing CodexAwake Closed-Lid helper", "Установка Closed-Lid helper CodexAwake")
            )
            closedLidActionMessage = t(
                "Administrator approval is required once for this app build. Repeated ON/OFF changes need no password.",
                "Для этой сборки один раз нужны права администратора. Дальнейшее включение и выключение — без пароля.")
            updateDiagnostics()

            do {
                try await Task.sleep(for: .seconds(20))
            } catch {
                // Cancellation only shortens the UI cooldown.
            }
            closedLidHelperActionInProgress = false
        }
    }

    func retryClosedLidHelperConnection() {
        guard !closedLidHelperActionInProgress else { return }
        closedLidHelperActionInProgress = true
        closedLidActionMessage = t(
            "Checking the helper connection…",
            "Проверяем подключение к helper…")
        Task {
            let status = await power.refreshClosedLidStatus(retryIfNeeded: false)
            closedLidProtection = status
            closedLidActionMessage =
                status.helperReachable
                ? t("Helper connection restored. No password was required.", "Связь с helper восстановлена без пароля.")
                : t(
                    "The installed helper does not accept this app build. Update it once to continue using Closed-Lid.",
                    "Установленный helper не принимает эту сборку. Обновите его один раз для работы Closed-Lid.")
            closedLidHelperActionInProgress = false
            updateDiagnostics()
        }
    }

    func removeClosedLidHelper() {
        Task {
            closedLidProtectionEnabled = false
            preferences.setClosedLidProtectionEnabled(false)
            do {
                try await power.setClosedLidRequested(false)
            } catch {
                record(error)
            }
            closedLidProtection = await power.refreshClosedLidStatus()
            openClosedLidHelperCommand(
                resource: "uninstall-closed-lid-helper",
                title: t("Removing CodexAwake Closed-Lid helper", "Удаление Closed-Lid helper CodexAwake")
            )
            closedLidActionMessage = t(
                "Complete the administrator prompt in Terminal.",
                "Подтвердите запрос администратора в Терминале.")
            updateDiagnostics()
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
        preferences.setFirstRunAcknowledged(true)
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
            try FileManager.default.createDirectory(
                at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
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
        panel.title = t("Choose the Codex CLI executable", "Выберите исполняемый файл Codex CLI")
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
        panel.title = t("Choose a project for Codex", "Выберите проект для Codex")
        panel.prompt = t("Use Project", "Использовать проект")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let workspacePath {
            panel.directoryURL = URL(fileURLWithPath: workspacePath)
        }
        if panel.runModal() == .OK, let path = panel.url?.standardizedFileURL.path {
            workspacePath = path
            preferences.setWorkspacePath(path)
            newChat()
        }
    }

    @discardableResult
    func sendPrompt(_ prompt: String) -> Bool {
        guard let workspacePath, appServerState == .running, let client else {
            chat.markUnavailable(
                chatUnavailableReason ?? t("Codex is not ready yet.", "Codex пока не готов."))
            return false
        }
        return chat.send(
            prompt,
            client: client,
            workspacePath: workspacePath,
            unavailableReason: chatUnavailableReason
        )
    }

    func interruptChat() {
        guard let client else { return }
        chat.interrupt(client: client)
    }

    func newChat() {
        chat.reset(client: client)
    }

    func resolveApproval(_ request: CodexApprovalRequest, decision: CodexApprovalDecision) {
        chat.resolve(request, decision: decision)
    }

    var chatMessages: [CodexChatMessage] { chat.messages }
    var chatThreadID: String? { chat.threadID }
    var chatTurnID: String? { chat.turnID }
    var chatIsSending: Bool { chat.isSending }
    var approvalRequests: [CodexApprovalRequest] { chat.approvalRequests }

    func requestQuit() {
        NSApplication.shared.terminate(nil)
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        desktopMonitor.stop()
        closedLidStatusTask?.cancel()
        closedLidStatusTask = nil
        chat.cancelPendingApprovals()
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
            return t(
                "Choose a project folder before sending a message.",
                "Перед отправкой сообщения выберите папку проекта.")
        }
        if appServerState != .running {
            if codexPath == nil {
                return t(
                    "Codex runtime is not ready. Restart the server or choose a Codex binary in Diagnostics.",
                    "Среда Codex не готова. Перезапустите сервер или выберите исполняемый файл Codex в Диагностике."
                )
            }
            return t(
                "Codex App Server is \(appServerState.rawValue). Wait for READY or press Restart.",
                "Сервер приложения Codex: \(appServerState.rawValue). Дождитесь статуса «ГОТОВ» или нажмите «Перезапустить»."
            )
        }
        if client == nil {
            return t(
                "Codex is connecting. Try again in a moment.",
                "Codex подключается. Повторите через несколько секунд.")
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
            chat.handle(event)
            return
        default:
            break
        }

        let snapshot = await tracker.apply(event)
        await coordinator.update(snapshot)
        activity = snapshot
        chat.handle(event)
        if case .unknown = event {
            if let client { await reconcile(using: client) }
        } else {
            await refreshPublishedState()
        }
    }

    private func handleDisconnect(_ reason: String) async {
        guard !isShuttingDown else { return }
        lastSafeError = String(reason.prefix(300))
        chat.cancelPendingApprovals()
        chat.markDisconnected(
            t(
                "Connection to the managed Codex server was lost.",
                "Соединение с управляемым сервером Codex потеряно."))
        let unknown = await tracker.markConnectionUnknown()
        await coordinator.update(unknown)
        activity = unknown
        appServerState = .reconnecting
        await refreshPublishedState()
    }

    private func reconcile(using client: AppServerClient) async {
        do {
            let reconciled = try await client.reconcileStatuses()
            let snapshot = await tracker.reconcile(
                loadedThreadIds: reconciled.loaded, statuses: reconciled.statuses)
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
        logger.error("An application operation failed; details are available in the in-app diagnostics")
        updateDiagnostics()
    }

    private func refreshPublishedState() async {
        assertionHeld = await coordinator.assertionIsHeld()
        updateDiagnostics()
    }

    private func updateDiagnostics() {
        var value = DiagnosticsSnapshot()
        value.appVersion = AppBuildInfo.displayVersion
        value.architecture = Self.architecture
        value.codexPath = codexPath
        value.codexVersion = codexVersion
        value.codexDesktopRunning = codexDesktopRunning
        value.codexDesktopActiveSessionIDs = codexDesktopActiveSessionIDs
        value.keepAwakeForCodexDesktop = keepAwakeForCodexDesktop
        value.closedLidProtection = closedLidProtection
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

    private func handleCodexDesktopSnapshot(_ snapshot: CodexDesktopMonitor.Snapshot) {
        codexDesktopRunning = snapshot.isRunning
        codexDesktopActiveSessionIDs = snapshot.activeSessionIDs
        Task {
            await coordinator.setCodexDesktopRunning(snapshot.isRunning)
            await coordinator.setCodexDesktopActiveCount(snapshot.activeSessionIDs.count)
            await refreshPublishedState()
        }
    }

    private func startClosedLidStatusMonitoring() {
        guard closedLidStatusTask == nil else { return }
        closedLidStatusTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let value = await power.refreshClosedLidStatus()
                if value != closedLidProtection {
                    closedLidProtection = value
                    if value.helperReachable {
                        closedLidHelperActionInProgress = false
                    }
                    if value.leaseActive {
                        closedLidActionMessage = t(
                            "Closed-Lid lease active. The display may be closed.",
                            "Аренда Closed-Lid активна. Крышку можно закрыть.")
                    } else if value.requested, value.helperInstalled, value.helperReachable {
                        closedLidActionMessage = t(
                            "Closed-Lid armed; the lease starts with sleep protection.",
                            "Closed-Lid готов; аренда начнётся вместе с защитой от сна.")
                    }
                    updateDiagnostics()
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    private func openClosedLidHelperCommand(resource: String, title: String) {
        do {
            guard let script = Bundle.main.url(forResource: resource, withExtension: "sh") else {
                throw CodexAwakeError.serverStartFailed("Closed-Lid installer resource is missing")
            }
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("CodexAwake", isDirectory: true)
            try FileManager.default.createDirectory(
                at: support,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let command = support.appendingPathComponent("\(title).command")
            try ClosedLidHelperCommandBuilder.commandContents(scriptPath: script.path, title: title)
                .write(to: command, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.path)
            NSWorkspace.shared.open(command)
        } catch {
            record(error)
        }
    }

    private func t(_ english: String, _ russian: String) -> String {
        appLanguage.text(english, russian)
    }

    private func handleServerRequest(_ request: AppServerServerRequest) async -> JSONValue? {
        await chat.handleServerRequest(request)
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
