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
    @Published var powerAssertions = PowerAssertionSnapshot()
    @Published var lastSafeError: String?
    @Published var reconnectCount = 0
    @Published var launchAtLogin = false
    @Published var launchAtLoginState: LaunchAtLoginState = .disabled
    @Published var firstRunAcknowledged: Bool
    @Published var autoKeepAwake: Bool
    @Published var preventSystemSleep: Bool
    @Published var preventDisplaySleep: Bool
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
    @Published var compactMenuBarEnabled: Bool
    @Published var taskSnapshot = CodexTaskSnapshot()

    let diagnostics = DiagnosticsStore()
    let chat: CodexChatSession
    private let logger = Logger(subsystem: "com.melnikoleg.CodexAwake", category: "App")
    private let tracker = ThreadActivityTracker()
    private let taskRegistry = CodexTaskRegistry()
    private lazy var taskNotifications = TaskNotificationService()
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
    private var diagnosticsObservation: AnyCancellable?
    private var isShuttingDown = false
    private var lastEventAt: Date?
    private var lastReconciliationAt: Date?
    private let startedAt = Date()
    private var didLoadTaskRegistry = false

    init(preferences: any AppPreferencesStoring = UserDefaultsAppPreferences()) {
        self.preferences = preferences
        let auto = preferences.autoKeepAwake
        let preventSystemSleep = preferences.preventSystemSleep
        let preventDisplaySleep = preferences.preventDisplaySleep
        let keepForDesktop = preferences.keepAwakeForCodexDesktop
        let closedLid = preferences.closedLidProtectionEnabled
        interfaceTheme =
            InterfaceTheme(
                rawValue: preferences.interfaceTheme ?? ""
            ) ?? .system
        let selectedLanguage =
            AppLanguage(
                rawValue: preferences.appLanguage ?? ""
            ) ?? .systemDefault
        appLanguage = selectedLanguage
        compactMenuBarEnabled = preferences.compactMenuBarEnabled
        chat = CodexChatSession(language: selectedLanguage)
        autoKeepAwake = auto
        self.preventSystemSleep = preventSystemSleep
        self.preventDisplaySleep = preventDisplaySleep
        keepAwakeForCodexDesktop = keepForDesktop
        closedLidProtectionEnabled = closedLid
        firstRunAcknowledged = preferences.completedOnboardingVersion >= AppBuildInfo.onboardingVersion
        if let savedWorkspace = preferences.workspacePath,
            FileManager.default.fileExists(atPath: savedWorkspace)
        {
            workspacePath = savedWorkspace
        } else {
            workspacePath = nil
        }
        let power = PowerProtectionManager(
            idle: PowerAssertionManager(
                configuration: .init(
                    preventSystemSleep: preventSystemSleep,
                    preventDisplaySleep: preventDisplaySleep
                )
            ),
            closedLidRequested: closedLid
        )
        self.power = power
        coordinator = AwakeCoordinator(
            power: power,
            autoKeepAwake: auto,
            keepAwakeForCodexDesktop: keepForDesktop
        )
        launchAtLogin = launchManager.isEnabled
        launchAtLoginState = launchManager.state
        chatObservation = chat.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        diagnosticsObservation = diagnostics.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func start() {
        guard connectionLoopTask == nil else { return }
        logger.notice("CodexAwake lifecycle started")
        appendEvent(
            .success,
            "CodexAwake \(AppBuildInfo.displayVersion) started.",
            "CodexAwake \(AppBuildInfo.displayVersion) запущен."
        )
        desktopMonitor.start { [weak self] snapshot in
            self?.handleCodexDesktopSnapshot(snapshot)
        }
        startClosedLidStatusMonitoring()
        Task {
            await chat.restore(defaultWorkspacePath: workspacePath)
            if let restoredWorkspace = chat.activeConversation?.settings.workspacePath,
                FileManager.default.fileExists(atPath: restoredWorkspace)
            {
                workspacePath = restoredWorkspace
                preferences.setWorkspacePath(restoredWorkspace)
            }
            await startManagedServer()
        }
    }

    func refreshSystemIntegrationStatus() {
        let previousState = launchAtLoginState
        launchAtLoginState = launchManager.state
        launchAtLogin = launchManager.isEnabled
        if previousState != launchAtLoginState {
            appendEvent(
                launchAtLoginState == .enabled ? .success : .info,
                launchAtLoginMessage(english: true),
                launchAtLoginMessage(english: false)
            )
        }
        Task {
            closedLidProtection = await power.refreshClosedLidStatus(retryIfNeeded: false)
            await refreshPublishedState()
        }
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
            chat.detach(
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
            chat.detach(
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
        appendEvent(
            .info,
            enabled ? "Automatic Codex protection enabled." : "Automatic Codex protection paused.",
            enabled ? "Автоматическая защита Codex включена." : "Автоматическая защита Codex приостановлена."
        )
        Task {
            await coordinator.setAutoKeepAwake(enabled)
            await refreshPublishedState()
        }
    }

    func setPreventSystemSleep(_ enabled: Bool) {
        preventSystemSleep = enabled
        preferences.setPreventSystemSleep(enabled)
        applyPowerAssertionConfiguration(
            event: enabled ? "System-sleep protection enabled." : "System-sleep protection disabled.",
            russianEvent: enabled ? "Защита от системного сна включена." : "Защита от системного сна выключена."
        )
    }

    func setPreventDisplaySleep(_ enabled: Bool) {
        preventDisplaySleep = enabled
        preferences.setPreventDisplaySleep(enabled)
        applyPowerAssertionConfiguration(
            event: enabled ? "Display-sleep protection enabled." : "Display-sleep protection disabled.",
            russianEvent: enabled ? "Защита экрана от выключения включена." : "Защита экрана от выключения выключена."
        )
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

    func setCompactMenuBarEnabled(_ enabled: Bool) {
        compactMenuBarEnabled = enabled
        preferences.setCompactMenuBarEnabled(enabled)
    }

    func setKeepAwakeForCodexDesktop(_ enabled: Bool) {
        keepAwakeForCodexDesktop = enabled
        preferences.setKeepAwakeForCodexDesktop(enabled)
        Task {
            await coordinator.setKeepAwakeForCodexDesktop(enabled)
            await refreshPublishedState()
        }
    }

    func setAllowSleepWhenCodexIdle(_ enabled: Bool) {
        setKeepAwakeForCodexDesktop(!enabled)
        appendEvent(
            .info,
            enabled
                ? "Normal idle sleep will resume when Codex has no active tasks."
                : "Codex Desktop presence will keep sleep protection active between tasks.",
            enabled
                ? "При отсутствии активных задач Codex будет восстановлен обычный режим сна."
                : "Присутствие Codex Desktop будет сохранять защиту от сна между задачами."
        )
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
        appendEvent(
            .info,
            enabled ? "Closed-Lid protection armed." : "Closed-Lid protection disabled.",
            enabled ? "Защита при закрытой крышке подготовлена." : "Защита при закрытой крышке выключена."
        )
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
        appendEvent(
            .info,
            "Checking Closed-Lid helper compatibility.",
            "Проверяется совместимость Closed-Lid helper."
        )

        Task {
            let status = await power.refreshClosedLidStatus(retryIfNeeded: false)
            closedLidProtection = status
            guard !status.helperInstalled || !status.helperReachable else {
                closedLidActionMessage = t(
                    "Closed-Lid helper is already ready. No password is required.",
                    "Closed-Lid helper уже готов. Пароль не требуется.")
                closedLidHelperActionInProgress = false
                appendEvent(
                    .success,
                    "Closed-Lid helper is ready; no update was needed.",
                    "Closed-Lid helper готов; обновление не потребовалось."
                )
                updateDiagnostics()
                return
            }

            openClosedLidHelperCommand(
                resource: "install-closed-lid-helper",
                title: t("Installing CodexAwake Closed-Lid helper", "Установка Closed-Lid helper CodexAwake")
            )
            closedLidActionMessage = t(
                "Administrator approval is required for this helper install or repair. Repeated ON/OFF changes need no password.",
                "Для установки или восстановления helper нужны права администратора. Дальнейшее включение и выключение — без пароля."
            )
            appendEvent(
                .warning,
                "Closed-Lid helper installer opened for explicit administrator approval.",
                "Установщик Closed-Lid helper открыт для явного подтверждения администратором."
            )
            updateDiagnostics()

            for _ in 0..<10 {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
                let refreshed = await power.refreshClosedLidStatus(retryIfNeeded: false)
                closedLidProtection = refreshed
                if refreshed.helperReachable {
                    closedLidActionMessage = t(
                        "Closed-Lid helper is ready. Future ON/OFF changes need no password.",
                        "Closed-Lid helper готов. Дальнейшее включение и выключение не требует пароля."
                    )
                    appendEvent(
                        .success,
                        "Closed-Lid helper installation or repair completed.",
                        "Установка или восстановление Closed-Lid helper завершено."
                    )
                    break
                }
            }
            closedLidHelperActionInProgress = false
            updateDiagnostics()
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
                    "The helper is still unavailable. Use Repair / Update only if automatic reconnect does not recover it.",
                    "Helper всё ещё недоступен. Используйте «Восстановить / обновить», только если автоподключение не помогло."
                )
            closedLidHelperActionInProgress = false
            appendEvent(
                status.helperReachable ? .success : .warning,
                status.helperReachable
                    ? "Closed-Lid helper connection restored."
                    : "Closed-Lid helper is still unavailable.",
                status.helperReachable
                    ? "Соединение с Closed-Lid helper восстановлено."
                    : "Closed-Lid helper всё ещё недоступен."
            )
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
            launchAtLoginState = launchManager.state
            appendEvent(
                launchAtLoginState == .requiresApproval ? .warning : .success,
                launchAtLoginMessage(english: true),
                launchAtLoginMessage(english: false)
            )
        } catch {
            launchAtLogin = launchManager.isEnabled
            launchAtLoginState = launchManager.state
            record(error)
        }
    }

    func acknowledgeFirstRun() {
        firstRunAcknowledged = true
        preferences.setFirstRunAcknowledged(true)
        preferences.setCompletedOnboardingVersion(AppBuildInfo.onboardingVersion)
    }

    func showOnboarding() {
        firstRunAcknowledged = false
    }

    var codexCommand: String? {
        guard let codexPath, let endpoint else { return nil }
        return CodexCommandBuilder.command(binaryPath: codexPath, endpoint: endpoint)
    }

    var totalActiveSessionCount: Int {
        taskSnapshot.activeCount
    }

    var allowSleepWhenCodexIdle: Bool {
        !keepAwakeForCodexDesktop
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
        NSPasteboard.general.setString(diagnostics.sanitizedText, forType: .string)
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
            chat.updateWorkspace(path)
        }
    }

    @discardableResult
    func sendPrompt(_ prompt: String) -> Bool {
        guard let workspacePath else {
            chat.markUnavailable(
                chatUnavailableReason ?? t("Codex is not ready yet.", "Codex пока не готов."))
            return false
        }
        let settings = CodexChatRequestSettings(
            workspacePath: workspacePath,
            modelID: chat.selectedModelID,
            reasoningEffort: chat.selectedReasoningEffort,
            permissionMode: chat.permissionMode
        )
        return chat.enqueue(
            prompt,
            settings: settings,
            unavailableReason: chatUnavailableReason
        )
    }

    func interruptChat() {
        chat.interrupt()
    }

    func newChat() {
        guard let workspacePath else {
            chooseWorkspace()
            return
        }
        chat.startNewConversation(
            settings: .init(
                workspacePath: workspacePath,
                modelID: chat.selectedModelID,
                reasoningEffort: chat.selectedReasoningEffort,
                permissionMode: chat.permissionMode
            )
        )
    }

    func continueChat(_ id: UUID) {
        chat.selectConversation(id)
        if let path = chat.activeConversation?.settings.workspacePath {
            workspacePath = path
            preferences.setWorkspacePath(path)
        }
    }

    func retryMessage(_ id: UUID) {
        chat.retry(messageID: id, unavailableReason: chatUnavailableReason)
    }

    func setChatModel(_ modelID: String?) {
        chat.selectModel(modelID)
    }

    func setChatReasoningEffort(_ effort: String?) {
        chat.selectReasoningEffort(effort)
    }

    func setChatPermissionMode(_ mode: CodexPermissionMode) {
        chat.selectPermissionMode(mode)
    }

    func resolveApproval(_ request: CodexApprovalRequest, decision: CodexApprovalDecision) {
        chat.resolve(request, decision: decision)
        guard let threadId = request.threadId else { return }
        Task {
            let snapshot = await taskRegistry.markApprovalResolved(threadId: threadId)
            publishTaskSnapshot(snapshot)
        }
    }

    func openTask(_ task: CodexTaskRecord) {
        var link = URLComponents()
        link.scheme = "codex"
        link.host = "threads"
        link.path = "/\(task.threadId)"
        if let url = link.url, NSWorkspace.shared.open(url) {
            return
        }

        let bundleIDs: Set<String> = ["com.openai.codex", "com.openai.chat"]
        NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier.map(bundleIDs.contains) ?? false })?
            .activate(options: [.activateAllWindows])
        chat.markUnavailable(
            t(
                "Could not open the selected task. Codex was brought to the front instead.",
                "Не удалось открыть выбранную задачу. Вместо этого открыто окно Codex."
            ))
    }

    var chatMessages: [CodexChatMessage] { chat.messages }
    var chatTools: [CodexToolActivity] { chat.tools }
    var chatConversations: [CodexConversation] { chat.conversations }
    var activeChatConversationID: UUID? { chat.activeConversationID }
    var chatThreadID: String? { chat.threadID }
    var chatTurnID: String? { chat.turnID }
    var chatIsSending: Bool { chat.isSending }
    var chatQueuedCount: Int { chat.queuedCount }
    var chatModelOptions: [CodexModelOption] { chat.modelOptions }
    var chatSelectedModelID: String? { chat.selectedModelID }
    var chatReasoningOptions: [CodexReasoningOption] { chat.reasoningOptions }
    var chatSelectedReasoningEffort: String? { chat.selectedReasoningEffort }
    var chatPermissionMode: CodexPermissionMode { chat.permissionMode }
    var chatPersistenceWarning: String? { chat.persistenceWarning }
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
        await chat.flushPersistence()
        connectionLoopTask?.cancel()
        connectionLoopTask = nil
        await client?.disconnect()
        client = nil
        await supervisor.stop()
        await coordinator.shutdown()
        assertionHeld = false
        powerAssertions = .init()
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
                chat.attach(client: newClient)
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
        let taskState = await taskRegistry.apply(event)
        publishTaskSnapshot(taskState)
        switch event {
        case .agentMessageDelta, .agentMessageCompleted, .runtimeError, .ignored:
            chat.handle(event)
            return
        case .itemStarted, .itemCompleted:
            // Item lifecycle changes the task status and the active cockpit timeline.
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
        chat.detach(
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
            var taskState = await taskRegistry.reconcileManagedStatuses(reconciled.statuses)
            taskState = await taskRegistry.reconcileManaged(reconciled.summaries)
            publishTaskSnapshot(taskState, notifyTransitions: didLoadTaskRegistry)
            didLoadTaskRegistry = true
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
                let taskState = await taskRegistry.markManagedServerStopped(failed: state == .failed)
                await coordinator.serverConfirmedStopped()
                activity = snapshot
                publishTaskSnapshot(
                    taskState,
                    notifyTransitions: !isShuttingDown && state == .failed
                )
                await refreshPublishedState()
            }
        }
        updateDiagnostics()
    }

    private func record(_ error: Error) {
        lastSafeError = SafeDisplay.sanitizedError(error)
        logger.error("An application operation failed; details are available in the in-app diagnostics")
        appendEvent(
            .error,
            "Operation failed: \(lastSafeError ?? "unknown error")",
            "Операция завершилась ошибкой: \(lastSafeError ?? "неизвестная ошибка")"
        )
        updateDiagnostics()
    }

    private func refreshPublishedState() async {
        let previousAssertions = powerAssertions
        powerAssertions = await power.assertionSnapshot()
        assertionHeld = powerAssertions.anyAssertionHeld
        if powerAssertions.anyAssertionHeld, !previousAssertions.anyAssertionHeld {
            appendEvent(
                .success,
                "Power protection activated for Codex activity.",
                "Защита питания активирована для работы Codex."
            )
        } else if !powerAssertions.anyAssertionHeld, previousAssertions.anyAssertionHeld {
            appendEvent(
                .info,
                "Power assertions released; normal idle sleep is restored.",
                "Системные блокировки сна сняты; обычный режим сна восстановлен."
            )
        }
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
        value.autoKeepAwake = autoKeepAwake
        value.preventSystemSleep = preventSystemSleep
        value.preventDisplaySleep = preventDisplaySleep
        value.compactMenuBarEnabled = compactMenuBarEnabled
        value.powerAssertions = powerAssertions
        value.launchAtLogin = launchAtLogin
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
            let taskState = await taskRegistry.reconcileDesktop(snapshot.activeSessions)
            publishTaskSnapshot(taskState)
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
                    let previous = closedLidProtection
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
                    if value.leaseActive, !previous.leaseActive {
                        appendEvent(
                            .success,
                            "Closed-Lid lease is active; the lid may be closed.",
                            "Аренда Closed-Lid активна; крышку можно закрыть."
                        )
                    } else if value.helperReachable, !previous.helperReachable {
                        appendEvent(
                            .success,
                            "Closed-Lid helper connection is healthy.",
                            "Соединение с Closed-Lid helper работает."
                        )
                    } else if value.helperInstalled, !value.helperReachable,
                        previous.helperReachable || !previous.helperInstalled
                    {
                        appendEvent(
                            .warning,
                            "Closed-Lid helper is unavailable; automatic reconnect is scheduled.",
                            "Closed-Lid helper недоступен; запланировано автоматическое переподключение."
                        )
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

    private func applyPowerAssertionConfiguration(event: String, russianEvent: String) {
        appendEvent(.info, event, russianEvent)
        let configuration = PowerAssertionConfiguration(
            preventSystemSleep: preventSystemSleep,
            preventDisplaySleep: preventDisplaySleep
        )
        Task {
            do {
                try await power.setAssertionConfiguration(configuration)
            } catch {
                record(error)
            }
            await refreshPublishedState()
        }
    }

    private func appendEvent(
        _ level: OperationalEvent.Level,
        _ english: String,
        _ russian: String
    ) {
        diagnostics.append(
            OperationalEvent(level: level, english: english, russian: russian)
        )
    }

    private func launchAtLoginMessage(english: Bool) -> String {
        switch launchAtLoginState {
        case .enabled:
            english ? "Launch at Login enabled." : "Запуск при входе включён."
        case .disabled:
            english ? "Launch at Login disabled." : "Запуск при входе выключен."
        case .requiresApproval:
            english
                ? "Launch at Login needs approval in System Settings > General > Login Items."
                : "Запуск при входе нужно разрешить в Системных настройках > Основные > Объекты входа."
        case .unavailable:
            english
                ? "Launch at Login is unavailable for this app location."
                : "Запуск при входе недоступен для текущего расположения приложения."
        }
    }

    private func t(_ english: String, _ russian: String) -> String {
        appLanguage.text(english, russian)
    }

    private func handleServerRequest(_ request: AppServerServerRequest) async -> JSONValue? {
        if let threadId = request.params?["threadId"]?.stringValue,
            request.method.hasSuffix("/requestApproval")
        {
            let snapshot = await taskRegistry.markWaitingForApproval(threadId: threadId)
            publishTaskSnapshot(snapshot)
        }
        return await chat.handleServerRequest(request)
    }

    private func publishTaskSnapshot(
        _ snapshot: CodexTaskSnapshot,
        notifyTransitions: Bool = true
    ) {
        let previous = Dictionary(uniqueKeysWithValues: taskSnapshot.all.map { ($0.id, $0) })
        taskSnapshot = snapshot
        NSApplication.shared.dockTile.badgeLabel = snapshot.activeCount > 0 ? "\(snapshot.activeCount)" : nil

        guard notifyTransitions else { return }
        for task in snapshot.all {
            let oldStatus = previous[task.id]?.status
            guard oldStatus != task.status else { continue }
            switch task.status {
            case .waiting where oldStatus?.isActive == true && oldStatus != .waiting:
                taskNotifications.post(for: task, kind: .attention, language: appLanguage)
            case .waitingForApproval:
                taskNotifications.post(for: task, kind: .approval, language: appLanguage)
            case .completed where oldStatus?.isActive == true:
                taskNotifications.post(for: task, kind: .completed, language: appLanguage)
            case .error:
                taskNotifications.post(for: task, kind: .error, language: appLanguage)
            default:
                break
            }
        }
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
