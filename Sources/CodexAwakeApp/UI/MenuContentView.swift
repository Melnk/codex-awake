import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("CodexAwake")
            .font(.headline)
        Text("\(t("App Server", "Сервер приложения")): \(appServerStatus)")
        Text("Codex: \(model.codexVersion ?? t("Not found", "Не найден"))")
        Text("Codex Desktop: \(model.codexDesktopRunning ? t("Running", "Запущен") : t("Not Running", "Не запущен"))")
        Text("\(t("Active sessions", "Активные сессии")): \(model.totalActiveSessionCount)")
        Text("\(t("Keep Awake", "Защита от сна")): \(model.assertionHeld ? t("ON", "ВКЛ") : t("OFF", "ВЫКЛ"))")
        Text("\(t("Closed-Lid", "Закрытая крышка")): \(closedLidMenuStatus)")

        if model.activity.certainty == .unknownReconnecting {
            Text(t("Activity unknown — reconnecting", "Статус неизвестен — переподключение"))
        }

        if !model.firstRunAcknowledged {
            Divider()
            Text(
                t(
                    "Tracks cockpit tasks and Codex CLI/TUI sessions connected to this app's managed App Server.",
                    "Отслеживает задачи cockpit и сессии Codex CLI/TUI, подключённые к серверу приложения."))
            Text(
                t(
                    "Tracks Codex Desktop task lifecycle without reading prompt or response text.",
                    "Отслеживает жизненный цикл задач Codex Desktop, не читая запросы и ответы."))
            Text(
                t(
                    "Optional Closed-Lid mode uses a short privileged lease and requires one-time administrator approval.",
                    "Режим закрытой крышки использует короткую привилегированную аренду и требует однократного подтверждения администратора."
                ))
            Button(t("I Understand", "Понятно")) { model.acknowledgeFirstRun() }
                .accessibilityLabel(
                    t("Acknowledge CodexAwake tracking scope", "Подтвердить понимание области отслеживания CodexAwake"))
        }

        if model.totalActiveSessionCount > 0 {
            Divider()
            Text(t("Active sessions", "Активные сессии"))
            ForEach(model.codexDesktopActiveSessionIDs.sorted(), id: \.self) { id in
                Text("• Desktop \(abbreviated(id))")
            }
            ForEach(model.activity.activeThreadIds.sorted(), id: \.self) { id in
                Text("• \(t("Managed", "Управляемая")) \(abbreviated(id))")
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
            t("Keep Awake while Codex App is Running", "Не давать Mac уснуть, пока открыт Codex"),
            isOn: Binding(
                get: { model.keepAwakeForCodexDesktop },
                set: { model.setKeepAwakeForCodexDesktop($0) }
            ))
        Toggle(
            t("Closed-Lid Protection", "Работа с закрытой крышкой"),
            isOn: Binding(
                get: { model.closedLidProtectionEnabled },
                set: { model.setClosedLidProtectionEnabled($0) }
            ))
        if !model.closedLidProtection.helperInstalled || !model.closedLidProtection.helperReachable {
            Button(t("Install / Update Closed-Lid Helper…", "Установить / обновить helper…")) {
                model.installClosedLidHelper()
            }
        } else {
            Button(t("Remove Closed-Lid Helper…", "Удалить Closed-Lid helper…")) { model.removeClosedLidHelper() }
        }
        Toggle(
            t("Launch at Login", "Запускать при входе"),
            isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

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

        Divider()
        Button(t("Diagnostics…", "Диагностика…")) { openWindow(id: "diagnostics") }
            .keyboardShortcut(",")
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

    private func abbreviated(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(8))…\(value.suffix(4))"
    }

    private func t(_ english: String, _ russian: String) -> String {
        model.appLanguage.text(english, russian)
    }

    private var closedLidMenuStatus: String {
        if model.closedLidProtection.leaseActive { return t("Lease Active", "Активен") }
        if !model.closedLidProtection.helperInstalled { return t("Helper Required", "Нужен helper") }
        if !model.closedLidProtection.helperReachable { return t("Helper Needs Update", "Нужно обновление helper") }
        return model.closedLidProtectionEnabled ? t("Armed", "Готов") : t("Off", "Выключен")
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
