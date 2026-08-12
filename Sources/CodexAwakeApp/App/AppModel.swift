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
    @Published var closedLidProtectionEnabled: Bool
    @Published var closedLidProtection = ClosedLidProtectionSnapshot()
    @Published var closedLidActionMessage: String?
    @Published var workspacePath: String?
    @Published var chatMessages: [CodexChatMessage] = []
    @Published var chatThreadID: String?
    @Published var chatTurnID: String?
    @Published var chatIsSending = false
    @Published var approvalRequests: [CodexApprovalRequest] = []
    @Published var interfaceTheme: InterfaceTheme
    @Published var appLanguage: AppLanguage

    let diagnostics = DiagnosticsStore()
    private let logger = Logger(subsystem: "com.melnikoleg.CodexAwake", category: "App")
    private let tracker = ThreadActivityTracker()
    private let desktopRolloutScanner = CodexDesktopRolloutScanner()
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
    private var desktopActivityTask: Task<Void, Never>?
    private var closedLidStatusTask: Task<Void, Never>?
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
        let closedLid = defaults.bool(forKey: "ClosedLidProtectionEnabled")
        interfaceTheme = InterfaceTheme(
            rawValue: defaults.string(forKey: "InterfaceTheme") ?? ""
        ) ?? .light
        appLanguage = AppLanguage(
            rawValue: defaults.string(forKey: "AppLanguage") ?? ""
        ) ?? .systemDefault
        autoKeepAwake = auto
        keepAwakeForCodexDesktop = keepForDesktop
        closedLidProtectionEnabled = closedLid
        firstRunAcknowledged = defaults.bool(forKey: "FirstRunAcknowledged")
        if let savedWorkspace = defaults.string(forKey: "CodexWorkspacePath"),
           FileManager.default.fileExists(atPath: savedWorkspace) {
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
    }

    func start() {
        guard connectionLoopTask == nil else { return }
        logger.notice("CodexAwake lifecycle started")
        startCodexDesktopMonitoring()
        startCodexDesktopActivityMonitoring()
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
            cancelPendingApprovals()
            markChatDisconnected(t("The managed Codex server was stopped.", "Управляемый сервер Codex остановлен."))
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
            markChatDisconnected(t("The managed Codex server is restarting.", "Управляемый сервер Codex перезапускается."))
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

    func setInterfaceTheme(_ theme: InterfaceTheme) {
        interfaceTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "InterfaceTheme")
    }

    func setAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: "AppLanguage")
        if closedLidProtection.leaseActive {
            closedLidActionMessage = t("Closed-Lid lease active. The display may be closed.", "Аренда Closed-Lid активна. Крышку можно закрыть.")
        } else if closedLidProtectionEnabled {
            closedLidActionMessage = t("Closed-Lid armed; the lease starts with sleep protection.", "Closed-Lid готов; аренда начнётся вместе с защитой от сна.")
        } else {
            closedLidActionMessage = nil
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

    func setClosedLidProtectionEnabled(_ enabled: Bool) {
        closedLidProtectionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "ClosedLidProtectionEnabled")
        closedLidActionMessage = enabled
            ? t("Closed-Lid requested. Install the helper if it is not ready.", "Режим закрытой крышки запрошен. Если helper не готов, установите его.")
            : t("Closed-Lid disabled; normal lid sleep is restored.", "Режим закрытой крышки выключен; обычный сон восстановлен.")
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
        if !closedLidProtectionEnabled { setClosedLidProtectionEnabled(true) }
        openClosedLidHelperCommand(
            resource: "install-closed-lid-helper",
            title: t("Installing CodexAwake Closed-Lid helper", "Установка Closed-Lid helper CodexAwake")
        )
        closedLidActionMessage = t("Complete the administrator prompt in Terminal, then return here.", "Подтвердите запрос администратора в Терминале, затем вернитесь сюда.")
    }

    func removeClosedLidHelper() {
        Task {
            closedLidProtectionEnabled = false
            UserDefaults.standard.set(false, forKey: "ClosedLidProtectionEnabled")
            try? await power.setClosedLidRequested(false)
            closedLidProtection = await power.refreshClosedLidStatus()
            openClosedLidHelperCommand(
                resource: "uninstall-closed-lid-helper",
                title: t("Removing CodexAwake Closed-Lid helper", "Удаление Closed-Lid helper CodexAwake")
            )
            closedLidActionMessage = t("Complete the administrator prompt in Terminal.", "Подтвердите запрос администратора в Терминале.")
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
            UserDefaults.standard.set(path, forKey: "CodexWorkspacePath")
            newChat()
        }
    }

    @discardableResult
    func sendPrompt(_ prompt: String) -> Bool {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatIsSending else { return false }
        guard let workspacePath, appServerState == .running, let client else {
            appendSystemMessage(chatUnavailableReason ?? t("Codex is not ready yet.", "Codex пока не готов."))
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
        closedLidStatusTask?.cancel()
        closedLidStatusTask = nil
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
            return t("Choose a project folder before sending a message.", "Перед отправкой сообщения выберите папку проекта.")
        }
        if appServerState != .running {
            if codexPath == nil {
                return t("Codex runtime is not ready. Restart the server or choose a Codex binary in Diagnostics.", "Среда Codex не готова. Перезапустите сервер или выберите исполняемый файл Codex в Диагностике.")
            }
            return t("Codex App Server is \(appServerState.rawValue). Wait for READY or press Restart.", "Сервер приложения Codex: \(appServerState.rawValue). Дождитесь статуса «ГОТОВ» или нажмите «Перезапустить».")
        }
        if client == nil {
            return t("Codex is connecting. Try again in a moment.", "Codex подключается. Повторите через несколько секунд.")
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
        markChatDisconnected(t("Connection to the managed Codex server was lost.", "Соединение с управляемым сервером Codex потеряно."))
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
        value.appVersion = "1.5.1 (10)"
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

    private func startClosedLidStatusMonitoring() {
        guard closedLidStatusTask == nil else { return }
        closedLidStatusTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let value = await power.refreshClosedLidStatus()
                if value != closedLidProtection {
                    closedLidProtection = value
                    if value.leaseActive {
                        closedLidActionMessage = t("Closed-Lid lease active. The display may be closed.", "Аренда Closed-Lid активна. Крышку можно закрыть.")
                    } else if value.requested, value.helperInstalled, value.helperReachable {
                        closedLidActionMessage = t("Closed-Lid armed; the lease starts with sleep protection.", "Closed-Lid готов; аренда начнётся вместе с защитой от сна.")
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
                appendSystemMessage(t("Codex turn ended with status: \(status).", "Ход Codex завершён со статусом: \(status)."))
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
            return t("Allow network access to \(host)?", "Разрешить сетевой доступ к \(host)?")
        }
        return kind == .command
            ? t("Allow this command?", "Разрешить эту команду?")
            : t("Allow these file changes?", "Разрешить эти изменения файлов?")
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
            return t("Codex wants to run a command in the selected workspace.", "Codex хочет выполнить команду в выбранном проекте.")
        }
        if let root = params?["grantRoot"]?.stringValue {
            return t("Codex wants to write inside \(root).", "Codex хочет записать данные в \(root).")
        }
        return t("Codex wants to apply file changes in the selected workspace.", "Codex хочет изменить файлы в выбранном проекте.")
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
