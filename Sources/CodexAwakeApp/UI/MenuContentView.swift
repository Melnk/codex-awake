import CodexAwakeCore
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.compactMenuBarEnabled {
                compactMenu
            } else {
                detailedMenu
            }
        }
    }

    @ViewBuilder
    private var compactMenu: some View {
        Text("CodexAwake")
            .font(.headline)
        Text(compactStatus)
        Text("\(t("Active tasks", "Активные задачи")): \(model.totalActiveSessionCount)")

        if !model.firstRunAcknowledged {
            Divider()
            Button(t("Finish First-Run Setup…", "Завершить первоначальную настройку…")) {
                openWindow(id: "cockpit")
            }
        }

        if !model.taskSnapshot.active.isEmpty {
            Divider()
            ForEach(model.taskSnapshot.active.prefix(3)) { task in
                Button("• \(task.projectName) · \(taskStatus(task.status))") {
                    model.openTask(task)
                }
            }
        }

        Divider()
        Button(t("Open Cockpit…", "Открыть главное окно…")) { openWindow(id: "cockpit") }
            .keyboardShortcut("k")
        Toggle(
            t("Sleep Protection", "Защита от сна"),
            isOn: Binding(
                get: { model.autoKeepAwake },
                set: { model.setAutoKeepAwake($0) }
            ))
        Button(t("Show All Controls", "Показать все настройки")) {
            model.setCompactMenuBarEnabled(false)
        }

        Divider()
        Button(t("Quit CodexAwake", "Выйти из CodexAwake")) { model.requestQuit() }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var detailedMenu: some View {
        Text("CodexAwake")
            .font(.headline)
        Text("\(t("App Server", "Сервер приложения")): \(appServerStatus)")
        Text("Codex: \(model.codexVersion ?? t("Not found", "Не найден"))")
        Text("Codex Desktop: \(model.codexDesktopRunning ? t("Running", "Запущен") : t("Not Running", "Не запущен"))")
        Text("\(t("Active sessions", "Активные сессии")): \(model.totalActiveSessionCount)")
        Text("\(t("System sleep", "Системный сон")): \(systemSleepStatus)")
        Text("\(t("Display sleep", "Выключение экрана")): \(displaySleepStatus)")
        Text("\(t("Closed-Lid", "Закрытая крышка")): \(closedLidMenuStatus)")

        if model.activity.certainty == .unknownReconnecting {
            Text(t("Activity unknown — reconnecting", "Статус неизвестен — переподключение"))
        }

        if !model.firstRunAcknowledged {
            Divider()
            Button(t("Finish First-Run Setup…", "Завершить первоначальную настройку…")) {
                openWindow(id: "cockpit")
            }
        }

        if model.totalActiveSessionCount > 0 {
            Divider()
            Text(t("Active sessions", "Активные сессии"))
            ForEach(model.taskSnapshot.active) { task in
                Button("• \(task.projectName) · \(taskStatus(task.status))") {
                    model.openTask(task)
                }
            }
        }

        if !model.taskSnapshot.recent.isEmpty {
            Divider()
            Text(t("Recently finished", "Недавно завершены"))
            ForEach(model.taskSnapshot.recent.prefix(5)) { task in
                Button("• \(task.projectName) · \(taskStatus(task.status))") {
                    model.openTask(task)
                }
            }
        }

        Divider()
        Text(
            t(
                "Managed and Codex Desktop task lifecycles are tracked",
                "Отслеживается жизненный цикл управляемых задач и Codex Desktop"))
        Text(t("Prompt and response text stays private", "Текст запросов и ответов остаётся приватным"))
        Text(
            t(
                "Closed-Lid only activates while a protected Codex session is held",
                "Режим закрытой крышки активен только при защищённой сессии Codex"))
        Button(t("Open Cockpit…", "Открыть главное окно…")) { openWindow(id: "cockpit") }
            .keyboardShortcut("k")
            .accessibilityLabel(t("Open the CodexAwake cockpit", "Открыть главное окно CodexAwake"))
        Button(t("Open Codex", "Открыть Codex")) { model.openCodex() }
            .disabled(model.codexCommand == nil || model.appServerState != .running)
            .keyboardShortcut("o")
            .accessibilityLabel(
                t(
                    "Open Codex connected to the CodexAwake App Server",
                    "Открыть Codex, подключённый к серверу CodexAwake"))
        Button(t("Copy Codex command", "Скопировать команду Codex")) { model.copyCodexCommand() }
            .disabled(model.codexCommand == nil)
            .accessibilityLabel(
                t("Copy the managed Codex remote command", "Скопировать команду управляемого подключения Codex"))

        Divider()
        Toggle(
            t("Auto Keep Awake", "Автоматическая защита от сна"),
            isOn: Binding(
                get: { model.autoKeepAwake },
                set: { model.setAutoKeepAwake($0) }
            ))
        Toggle(
            t("Prevent Mac Sleep", "Не давать Mac уснуть"),
            isOn: Binding(
                get: { model.preventSystemSleep },
                set: { model.setPreventSystemSleep($0) }
            ))
        Toggle(
            t("Keep Display On", "Не выключать экран"),
            isOn: Binding(
                get: { model.preventDisplaySleep },
                set: { model.setPreventDisplaySleep($0) }
            ))
        Toggle(
            t("Allow Sleep with No Active Tasks", "Разрешать сон без активных задач"),
            isOn: Binding(
                get: { model.allowSleepWhenCodexIdle },
                set: { model.setAllowSleepWhenCodexIdle($0) }
            ))
        Toggle(
            t("Closed-Lid Protection", "Работа с закрытой крышкой"),
            isOn: Binding(
                get: { model.closedLidProtectionEnabled },
                set: { model.setClosedLidProtectionEnabled($0) }
            ))
        if !model.closedLidProtection.helperInstalled {
            Button(t("One-time Closed-Lid Helper Setup…", "Однократная настройка Closed-Lid helper…")) {
                model.installClosedLidHelper()
            }
            .disabled(model.closedLidHelperActionInProgress)
        } else if !model.closedLidProtection.helperReachable {
            Button(t("Retry Helper Connection", "Повторить подключение к helper")) {
                model.retryClosedLidHelperConnection()
            }
            .disabled(model.closedLidHelperActionInProgress)
            Button(t("Repair / Update Closed-Lid Helper…", "Восстановить / обновить Closed-Lid helper…")) {
                model.installClosedLidHelper()
            }
            .disabled(model.closedLidHelperActionInProgress)
        } else {
            Button(t("Remove Closed-Lid Helper…", "Удалить Closed-Lid helper…")) { model.removeClosedLidHelper() }
        }
        Toggle(
            t("Launch at Login", "Запускать при входе"),
            isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
        if model.launchAtLoginState == .requiresApproval {
            Text(t("Approve in System Settings > Login Items", "Разрешите в Настройках > Объекты входа"))
        } else if model.launchAtLoginState == .unavailable {
            Text(t("Move CodexAwake to Applications first", "Сначала перенесите CodexAwake в «Программы»"))
        }

        Picker(
            t("Appearance", "Оформление"),
            selection: Binding(
                get: { model.interfaceTheme },
                set: { model.setInterfaceTheme($0) }
            )
        ) {
            ForEach(InterfaceTheme.allCases) { theme in
                Label(theme.title(in: model.appLanguage), systemImage: theme.symbol)
                    .tag(theme)
            }
        }

        Picker(
            t("Language", "Язык"),
            selection: Binding(
                get: { model.appLanguage },
                set: { model.setAppLanguage($0) }
            )
        ) {
            ForEach(AppLanguage.allCases) { language in
                Text(language.title).tag(language)
            }
        }

        Toggle(
            t("Compact Menu Bar", "Компактное меню"),
            isOn: Binding(
                get: { model.compactMenuBarEnabled },
                set: { model.setCompactMenuBarEnabled($0) }
            ))

        Divider()
        Button(t("Diagnostics…", "Диагностика…")) { openWindow(id: "diagnostics") }
            .keyboardShortcut(",")
        Button(t("Show Welcome Guide…", "Показать вводный гид…")) {
            model.showOnboarding()
            openWindow(id: "cockpit")
        }
        if model.appServerState == .stopped || model.appServerState == .failed {
            Button(t("Start App Server", "Запустить сервер приложения")) { Task { await model.startManagedServer() } }
        } else {
            Button(t("Restart App Server", "Перезапустить сервер приложения")) { model.restartServer() }
            Button(t("Stop App Server", "Остановить сервер приложения")) { model.stopServer() }
        }

        Divider()
        Button(t("Quit CodexAwake", "Выйти из CodexAwake")) { model.requestQuit() }
            .keyboardShortcut("q")
    }

    private func taskStatus(_ status: CodexTaskStatus) -> String {
        switch status {
        case .waiting: t("waiting", "ожидает")
        case .thinking: t("thinking", "думает")
        case .runningTool: t("tools", "инструменты")
        case .waitingForApproval: t("approval", "подтверждение")
        case .completed: t("done", "готово")
        case .error: t("error", "ошибка")
        }
    }

    private var compactStatus: String {
        if model.activity.certainty == .unknownReconnecting {
            return t("Reconnecting to Codex…", "Переподключение к Codex…")
        }
        if model.assertionHeld {
            return t("Protection active", "Защита активна")
        }
        if model.appServerState == .running {
            return t("Ready for the next task", "Готово к следующей задаче")
        }
        return t("Codex App Server is \(appServerStatus)", "Сервер Codex: \(appServerStatus)")
    }

    private func t(_ english: String, _ russian: String) -> String {
        model.appLanguage.text(english, russian)
    }

    private var closedLidMenuStatus: String {
        if model.closedLidProtection.leaseActive { return t("Lease Active", "Активен") }
        if !model.closedLidProtection.helperInstalled { return t("Helper Required", "Нужен helper") }
        if !model.closedLidProtection.helperReachable { return t("Reconnecting", "Переподключение") }
        return model.closedLidProtectionEnabled ? t("Armed", "Готов") : t("Off", "Выключен")
    }

    private var systemSleepStatus: String {
        if model.powerAssertions.systemSleepPrevented { return t("BLOCKED", "ЗАБЛОКИРОВАН") }
        return model.preventSystemSleep ? t("Ready", "Готов") : t("Allowed", "Разрешён")
    }

    private var displaySleepStatus: String {
        if model.powerAssertions.displaySleepPrevented { return t("BLOCKED", "ЗАБЛОКИРОВАНО") }
        return model.preventDisplaySleep ? t("Ready", "Готово") : t("Allowed", "Разрешено")
    }

    private var appServerStatus: String {
        switch model.appServerState {
        case .stopped: t("Stopped", "Остановлен")
        case .starting: t("Starting", "Запускается")
        case .running: t("Running", "Работает")
        case .stopping: t("Stopping", "Останавливается")
        case .reconnecting: t("Reconnecting", "Переподключается")
        case .failed: t("Failed", "Ошибка")
        }
    }
}
