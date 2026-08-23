import AppKit
import CodexAwakeCore
import SwiftUI

enum CockpitPalette {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let panelRaised = Color(nsColor: .textBackgroundColor)
    static let silver = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)
    static let ice = Color(red: 0.43, green: 0.22, blue: 0.98)
    static let iceDeep = Color(red: 0.28, green: 0.10, blue: 0.76)
    static let violetSoft = Color(red: 0.70, green: 0.42, blue: 1.0)
    static let blueSoft = Color(red: 0.28, green: 0.56, blue: 1.0)
    static let amber = Color(red: 0.96, green: 0.66, blue: 0.22)
    static let danger = Color(red: 0.95, green: 0.30, blue: 0.31)
}

private enum CompactCockpitSection {
    case overview
    case chat
}

struct CockpitView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var compactSection = CompactCockpitSection.overview

    var body: some View {
        GeometryReader { geometry in
            let usesCompactLayout = geometry.size.width < 900

            ZStack {
                CockpitBackground()

                VStack(spacing: 0) {
                    topBar

                    if usesCompactLayout {
                        compactNavigation
                        compactContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(reduceMotion ? .identity : .opacity)
                    } else {
                        HSplitView {
                            controlDeck
                                .padding(.trailing, 10)
                                .frame(minWidth: 280, idealWidth: 340, maxWidth: 560)
                            chatDeck
                                .padding(.leading, 10)
                                .frame(minWidth: 460)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }

                if model.firstRunAcknowledged, let approval = model.approvalRequests.first {
                    ApprovalOverlay(request: approval)
                        .environmentObject(model)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if !model.firstRunAcknowledged {
                    OnboardingView()
                        .environmentObject(model)
                        .transition(reduceMotion ? .identity : .opacity)
                        .zIndex(2)
                }
            }
        }
        .frame(minWidth: 660, minHeight: 540)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: compactSection)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.firstRunAcknowledged)
    }

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            fullTopBar
            compactTopBar
        }
    }

    private var fullTopBar: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 48, height: 48)
                .shadow(color: CockpitPalette.ice.opacity(0.24), radius: 14, y: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text("CodexAwake")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(t("Keep your Codex work running", "Работа Codex без перехода в сон"))
                    .font(.system(size: 11))
                    .foregroundStyle(CockpitPalette.muted)
            }

            StatusPill(
                text: model.appServerState == .running
                    ? t("CODEX READY", "CODEX ГОТОВ") : t("CONNECTING", "ПОДКЛЮЧЕНИЕ"),
                color: serverAccent
            )
            .padding(.leading, 8)

            Spacer()

            Label(
                t("\(model.totalActiveSessionCount) active", "Активных: \(model.totalActiveSessionCount)"),
                systemImage: model.totalActiveSessionCount > 0 ? "waveform.path.ecg" : "waveform"
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(CockpitPalette.muted)

            LanguageSwitcher(
                selection: Binding(
                    get: { model.appLanguage },
                    set: { model.setAppLanguage($0) }
                ))

            ThemeSwitcher(
                language: model.appLanguage,
                selection: Binding(
                    get: { model.interfaceTheme },
                    set: { model.setInterfaceTheme($0) }
                ))
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .background(CockpitPalette.panelRaised.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CockpitPalette.separator.opacity(0.65))
                .frame(height: 1)
        }
    }

    private var compactTopBar: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("CodexAwake")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(
                    model.totalActiveSessionCount == 0
                        ? t("Ready", "Готово")
                        : t("Active: \(model.totalActiveSessionCount)", "Активных: \(model.totalActiveSessionCount)")
                )
                .font(.caption)
                .foregroundStyle(CockpitPalette.muted)
            }

            Spacer()
            StatusPill(
                text: model.appServerState == .running ? t("READY", "ГОТОВ") : t("CONNECTING", "ПОДКЛЮЧЕНИЕ"),
                color: serverAccent
            )
            compactPreferencesMenu
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(CockpitPalette.panelRaised.opacity(0.76))
        .overlay(alignment: .bottom) {
            Rectangle().fill(CockpitPalette.separator.opacity(0.65)).frame(height: 1)
        }
    }

    private var compactPreferencesMenu: some View {
        Menu {
            Picker(
                t("Appearance", "Оформление"),
                selection: Binding(
                    get: { model.interfaceTheme },
                    set: { model.setInterfaceTheme($0) }
                )
            ) {
                ForEach(InterfaceTheme.allCases) { theme in
                    Label(theme.title(in: model.appLanguage), systemImage: theme.symbol).tag(theme)
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
        } label: {
            Image(systemName: "slider.horizontal.3")
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(t("Appearance and language", "Оформление и язык"))
        .accessibilityLabel(t("Appearance and language", "Оформление и язык"))
    }

    private var compactNavigation: some View {
        HStack(spacing: 8) {
            compactNavigationButton(
                .overview,
                title: t("Overview", "Обзор"),
                icon: "gauge.with.dots.needle.67percent"
            )
            compactNavigationButton(
                .chat,
                title: t("Chat", "Чат"),
                icon: "bubble.left.and.bubble.right"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func compactNavigationButton(
        _ section: CompactCockpitSection,
        title: String,
        icon: String
    ) -> some View {
        Button {
            compactSection = section
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(compactSection == section ? Color.white : CockpitPalette.silver)
        .background(
            compactSection == section ? CockpitPalette.ice : CockpitPalette.panelRaised.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(compactSection == section ? CockpitPalette.iceDeep : CockpitPalette.separator)
        )
        .keyboardShortcut(section == .overview ? "1" : "2", modifiers: [.command])
        .accessibilityValue(
            compactSection == section ? t("Selected", "Выбрано") : t("Not selected", "Не выбрано"))
    }

    @ViewBuilder
    private var compactContent: some View {
        switch compactSection {
        case .overview:
            controlDeck
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        case .chat:
            chatDeck
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private var controlDeck: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                powerControl
                AutomationView()
                powerModesControl
                closedLidControl

                HStack(spacing: 10) {
                    InstrumentCard(
                        label: t("CODEX APP", "ПРИЛОЖЕНИЕ CODEX"),
                        value: model.codexDesktopRunning ? t("ON", "ВКЛ") : t("OFF", "ВЫКЛ"),
                        icon: "macwindow",
                        accent: model.codexDesktopRunning ? CockpitPalette.ice : CockpitPalette.muted
                    )
                    InstrumentCard(
                        label: t("ACTIVE SESSIONS", "АКТИВНЫЕ СЕССИИ"),
                        value: "\(model.totalActiveSessionCount)",
                        icon: "waveform.path.ecg",
                        accent: model.totalActiveSessionCount > 0 ? CockpitPalette.ice : CockpitPalette.muted
                    )
                }

                activeTasks
                externalChatGPTNotice
                launchAtLoginControl

                HStack(spacing: 10) {
                    Button(t("Diagnostics", "Диагностика")) { openWindow(id: "diagnostics") }
                        .buttonStyle(CockpitSecondaryButtonStyle())
                    Button(t("Restart", "Перезапустить")) { model.restartServer() }
                        .buttonStyle(CockpitSecondaryButtonStyle())
                        .disabled(model.appServerState == .starting || model.appServerState == .stopping)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var powerControl: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: model.autoKeepAwake
                    ? [CockpitPalette.iceDeep, CockpitPalette.ice, CockpitPalette.blueSoft]
                    : [Color.gray.opacity(0.72), Color.gray.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            AmbientBlob()
                .frame(width: 150, height: 130)
                .offset(x: 34, y: 30)
                .opacity(model.autoKeepAwake ? 0.82 : 0.25)

            VStack(alignment: .leading, spacing: 13) {
                Button {
                    model.setAutoKeepAwake(!model.autoKeepAwake)
                } label: {
                    HStack {
                        Label(t("Sleep protection", "Защита от сна"), systemImage: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Spacer()
                        PremiumSwitchIndicator(isOn: model.autoKeepAwake)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("Automatic sleep protection", "Автоматическая защита от сна"))
                .accessibilityValue(
                    model.autoKeepAwake ? t("On", "Включено") : t("Off", "Выключено"))

                Text(powerHeadline)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(powerSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: 225, alignment: .leading)

                HStack(spacing: 7) {
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                    Text(model.autoKeepAwake ? t("ON", "ВКЛ") : t("OFF", "ВЫКЛ"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.4)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.white.opacity(0.16), in: Capsule())
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 210)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: CockpitPalette.ice.opacity(0.18), radius: 22, y: 12)
    }

    private var activeTasks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("ACTIVE SESSIONS", "АКТИВНЫЕ СЕССИИ"))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(CockpitPalette.muted)
                Spacer()
                Circle()
                    .fill(model.totalActiveSessionCount > 0 ? CockpitPalette.ice : CockpitPalette.muted.opacity(0.45))
                    .frame(width: 6, height: 6)
                    .shadow(color: CockpitPalette.ice, radius: model.totalActiveSessionCount > 0 ? 5 : 0)
            }

            if model.taskSnapshot.active.isEmpty {
                Label(t("No active Codex sessions", "Нет активных сессий Codex"), systemImage: "checkmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CockpitPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(CockpitPalette.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(CockpitPalette.separator.opacity(0.55)))
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(model.taskSnapshot.active) { task in
                        TaskOverviewRow(task: task, language: model.appLanguage) {
                            model.openTask(task)
                        }
                    }
                }
            }

            if !model.taskSnapshot.recent.isEmpty {
                HStack {
                    Text(t("RECENTLY FINISHED", "НЕДАВНО ЗАВЕРШЕНЫ"))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(CockpitPalette.muted)
                    Spacer()
                    Text("\(model.taskSnapshot.recent.count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CockpitPalette.muted)
                }
                .padding(.top, 4)

                LazyVStack(spacing: 7) {
                    ForEach(model.taskSnapshot.recent) { task in
                        TaskOverviewRow(task: task, language: model.appLanguage) {
                            model.openTask(task)
                        }
                    }
                }
            }
        }
    }

    private var powerModesControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("THREE POWER MODES", "ТРИ РЕЖИМА ПИТАНИЯ"))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(CockpitPalette.muted)

            PowerModeToggle(
                title: t("Keep Mac awake", "Не давать Mac уснуть"),
                subtitle: t("Background work keeps running", "Фоновые задачи продолжат работать"),
                icon: "moon.zzz",
                accent: model.powerAssertions.systemSleepPrevented ? CockpitPalette.ice : CockpitPalette.muted,
                language: model.appLanguage,
                isOn: Binding(
                    get: { model.preventSystemSleep },
                    set: { model.setPreventSystemSleep($0) }
                )
            )

            PowerModeToggle(
                title: t("Keep display on", "Не выключать экран"),
                subtitle: t("Prevents display dimming and sleep", "Экран не погаснет и не перейдёт в сон"),
                icon: "display",
                accent: model.powerAssertions.displaySleepPrevented ? CockpitPalette.ice : CockpitPalette.muted,
                language: model.appLanguage,
                isOn: Binding(
                    get: { model.preventDisplaySleep },
                    set: { model.setPreventDisplaySleep($0) }
                )
            )

        }
    }

    private var launchAtLoginControl: some View {
        PremiumToggleCard(
            title: t("Launch at login", "Запускать при входе"),
            subtitle: launchAtLoginSubtitle,
            icon: "person.crop.circle.badge.checkmark",
            accent: model.launchAtLogin ? CockpitPalette.ice : CockpitPalette.muted,
            language: model.appLanguage,
            isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            )
        )
    }

    private var externalChatGPTNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: model.codexDesktopRunning ? "dot.radiowaves.left.and.right" : "power")
                .foregroundStyle(model.codexDesktopRunning ? CockpitPalette.ice : CockpitPalette.silver)
            VStack(alignment: .leading, spacing: 3) {
                Text(t("Codex app", "Приложение Codex"))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.9)
                Text(codexDesktopPresenceDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(CockpitPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(CockpitPalette.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(CockpitPalette.separator.opacity(0.58)))
    }

    private var closedLidControl: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                model.setClosedLidProtectionEnabled(!model.closedLidProtectionEnabled)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: model.closedLidProtection.leaseActive ? "lock.open.display" : "lock.display")
                        .foregroundStyle(closedLidAccent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Closed-lid mode", "Режим закрытой крышки"))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .textCase(.uppercase)
                            .tracking(0.9)
                        Text(closedLidStatusText)
                            .font(.system(size: 10))
                            .foregroundStyle(CockpitPalette.muted)
                    }
                    Spacer()
                    PremiumSwitchIndicator(isOn: model.closedLidProtectionEnabled)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("Closed-lid mode", "Режим закрытой крышки"))
            .accessibilityValue(
                model.closedLidProtectionEnabled ? t("On", "Включено") : t("Off", "Выключено")
            )
            .accessibilityHint(closedLidStatusText)

            if !model.closedLidProtection.helperInstalled {
                Button(t("One-time helper setup…", "Однократная настройка helper…")) {
                    model.installClosedLidHelper()
                }
                .buttonStyle(CockpitSecondaryButtonStyle())
                .font(.system(size: 10, weight: .semibold))
                .disabled(model.closedLidHelperActionInProgress)
            } else if !model.closedLidProtection.helperReachable {
                HStack(spacing: 8) {
                    Button(t("Retry", "Повторить")) {
                        model.retryClosedLidHelperConnection()
                    }
                    .buttonStyle(CockpitSecondaryButtonStyle())

                    Button(t("Repair / Update…", "Восстановить / обновить…")) {
                        model.installClosedLidHelper()
                    }
                    .buttonStyle(CockpitSecondaryButtonStyle())
                }
                .font(.system(size: 10, weight: .semibold))
                .disabled(model.closedLidHelperActionInProgress)
            }

            Text(
                model.closedLidActionMessage
                    ?? t(
                        "Requires administrator approval once. Restores normal sleep when its lease expires.",
                        "Требует однократного подтверждения администратора. После окончания аренды обычный сон восстановится."
                    )
            )
            .font(.system(size: 9))
            .foregroundStyle(model.closedLidProtection.lastError == nil ? CockpitPalette.muted : CockpitPalette.amber)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(CockpitPalette.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(closedLidAccent.opacity(0.22)))
    }

    private var chatDeck: some View {
        CodexChatView()
    }

    private var codexDesktopPresenceDescription: String {
        if model.codexDesktopRunning {
            if !model.codexDesktopActiveSessionIDs.isEmpty {
                let count = model.codexDesktopActiveSessionIDs.count
                return t(
                    "\(count) active \(count == 1 ? "session" : "sessions") detected. Your prompts and answers stay private.",
                    "Обнаружено активных сессий: \(count). Ваши запросы и ответы остаются приватными."
                )
            }
            return model.keepAwakeForCodexDesktop
                ? t(
                    "Codex is open. This Mac stays awake between tasks.",
                    "Codex открыт. Mac не уснёт даже между задачами.")
                : t(
                    "Codex is open. Only active tasks prevent sleep.",
                    "Codex открыт. Сон блокируют только активные задачи.")
        }
        return t(
            "Codex is closed. Open it to enable app-based protection.", "Codex закрыт. Откройте его для защиты от сна.")
    }

    private var powerSubtitle: String {
        guard model.autoKeepAwake else {
            return t(
                "Turn it on to protect active Codex work from sleep.",
                "Включите защиту, чтобы активная работа Codex не прерывалась сном.")
        }
        if model.closedLidProtection.leaseActive {
            return t(
                "Closed-lid mode is active. You can close your MacBook.",
                "Режим закрытой крышки активен. MacBook можно закрыть.")
        }
        if model.assertionHeld, model.powerAssertions.systemSleepPrevented,
            !model.powerAssertions.displaySleepPrevented
        {
            return t(
                "Background work continues; the display may turn off normally.",
                "Фоновая работа продолжится; экран может выключиться как обычно."
            )
        }
        if model.assertionHeld, model.powerAssertions.displaySleepPrevented,
            !model.powerAssertions.systemSleepPrevented
        {
            return t(
                "The display stays on while Codex protection is active.",
                "Экран останется включённым, пока активна защита Codex."
            )
        }
        if model.assertionHeld, !model.codexDesktopActiveSessionIDs.isEmpty {
            return t("An active Codex session is protected from sleep.", "Активная сессия Codex защищена от сна.")
        }
        if model.assertionHeld, model.codexDesktopRunning, model.keepAwakeForCodexDesktop {
            return t("Codex is open, so sleep protection is active.", "Codex открыт, поэтому защита от сна активна.")
        }
        return model.assertionHeld
            ? t("Sleep protection is active.", "Защита от сна активна.")
            : t(
                "Ready — protection starts with your next Codex task.",
                "Готово — защита включится со следующей задачей Codex.")
    }

    private var powerHeadline: String {
        guard model.autoKeepAwake else { return t("Protection is paused", "Защита приостановлена") }
        if model.closedLidProtection.leaseActive {
            return t("Closed-lid protection active", "Защита закрытой крышки активна")
        }
        if model.assertionHeld {
            if model.powerAssertions.systemSleepPrevented, model.powerAssertions.displaySleepPrevented {
                return t("Mac and display stay awake", "Mac и экран не уснут")
            }
            if model.powerAssertions.systemSleepPrevented {
                return t("Mac stays awake", "Mac не уснёт")
            }
            return t("Display stays on", "Экран не погаснет")
        }
        if !model.preventSystemSleep, !model.preventDisplaySleep {
            return t("Choose a protection mode", "Выберите режим защиты")
        }
        return t("Protection is ready", "Защита готова")
    }

    private var closedLidAccent: Color {
        if model.closedLidProtection.leaseActive { return CockpitPalette.ice }
        if model.closedLidProtectionEnabled, model.closedLidProtection.helperInstalled { return CockpitPalette.amber }
        return CockpitPalette.muted
    }

    private var closedLidStatusText: String {
        if model.closedLidProtection.leaseActive {
            return t("Active — you can close the lid", "Активен — крышку можно закрыть")
        }
        if !model.closedLidProtection.helperInstalled {
            return t("One-time setup required", "Нужна однократная настройка")
        }
        if !model.closedLidProtection.helperReachable {
            return t("Reconnecting automatically", "Автоматическое переподключение")
        }
        if model.closedLidProtectionEnabled {
            if !model.autoKeepAwake {
                return t(
                    "Blocked — turn on Sleep protection first",
                    "Заблокирован — сначала включите защиту от сна"
                )
            }
            if !model.automationDecision.shouldProtect,
                let blocker = model.automationDecision.blockers.first
            {
                switch blocker {
                case .externalPowerRequired:
                    return t(
                        "Blocked — connect power or turn off “Only on external power”",
                        "Заблокирован — подключите зарядку или выключите «Только от зарядки»"
                    )
                case .noActiveTasks:
                    return t(
                        "Waiting — start a task or turn off automatic stop",
                        "Ожидание — запустите задачу или выключите автоотключение"
                    )
                case .codexNotRunning:
                    return t("Waiting for Codex to start", "Ожидание запуска Codex")
                case .outsideSchedule:
                    return t("Blocked by the current schedule", "Заблокирован текущим расписанием")
                case .noSelectedProjectActive:
                    return t("Waiting for a selected project", "Ожидание выбранного проекта")
                }
            }
            return t("Ready — starts with protected work", "Готов — включится при защищённой работе")
        }
        return t("Off — closing the lid sleeps normally", "Выключен — при закрытии крышки Mac уснёт")
    }

    private var launchAtLoginSubtitle: String {
        switch model.launchAtLoginState {
        case .enabled:
            t("Starts automatically after sign-in", "Автоматически запускается после входа")
        case .disabled:
            t("Start CodexAwake manually", "CodexAwake запускается вручную")
        case .requiresApproval:
            t("Allow it in System Settings > Login Items", "Разрешите в Настройках > Объекты входа")
        case .unavailable:
            t("Move the app to Applications first", "Сначала перенесите приложение в «Программы»")
        }
    }

    private var serverAccent: Color {
        switch model.appServerState {
        case .running: CockpitPalette.ice
        case .failed: CockpitPalette.danger
        case .reconnecting, .starting: CockpitPalette.amber
        default: CockpitPalette.muted
        }
    }

    private func abbreviated(_ value: String) -> String {
        guard value.count > 14 else { return value }
        return "\(value.prefix(8))…\(value.suffix(4))"
    }

    private func t(_ english: String, _ russian: String) -> String {
        model.appLanguage.text(english, russian)
    }
}

private struct TaskOverviewRow: View {
    let task: CodexTaskRecord
    let language: AppLanguage
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: task.source == .desktop ? "macwindow" : statusSymbol)
                    .foregroundStyle(statusColor)
                    .frame(width: 16, height: 17)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(task.projectName)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(statusTitle)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(statusColor)
                    }

                    if let path = task.workspacePath {
                        Text(path)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(CockpitPalette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: 5) {
                        Text(abbreviated(task.threadId))
                        Text("·")
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(duration(until: task.status.isActive ? context.date : task.updatedAt))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(CockpitPalette.muted)
                }
            }
            .padding(10)
            .background(statusColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(statusColor.opacity(0.13)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(language.text("Open this task", "Открыть эту задачу"))
    }

    private var statusTitle: String {
        switch task.status {
        case .waiting: language.text("WAITING", "ОЖИДАЕТ")
        case .thinking: language.text("THINKING", "ДУМАЕТ")
        case .runningTool: language.text("TOOLS", "ИНСТРУМЕНТЫ")
        case .waitingForApproval: language.text("APPROVAL", "ПОДТВЕРЖДЕНИЕ")
        case .completed: language.text("DONE", "ГОТОВО")
        case .error: language.text("ERROR", "ОШИБКА")
        }
    }

    private var statusSymbol: String {
        switch task.status {
        case .waiting: "clock"
        case .thinking: "sparkles"
        case .runningTool: "wrench.and.screwdriver"
        case .waitingForApproval: "hand.raised"
        case .completed: "checkmark.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .waiting: CockpitPalette.muted
        case .thinking, .runningTool: CockpitPalette.ice
        case .waitingForApproval: CockpitPalette.amber
        case .completed: Color.green
        case .error: CockpitPalette.danger
        }
    }

    private func duration(until end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(task.startedAt)))
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func abbreviated(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))…\(value.suffix(4))"
    }
}

private struct ApprovalOverlay: View {
    @EnvironmentObject private var model: AppModel
    let request: CodexApprovalRequest

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 13) {
                    ZStack {
                        Circle().fill(CockpitPalette.amber.opacity(0.12))
                        Circle().stroke(CockpitPalette.amber.opacity(0.4))
                        Image(systemName: request.kind == .command ? "terminal" : "doc.badge.gearshape")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(CockpitPalette.amber)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("CODEX APPROVAL", "ПОДТВЕРЖДЕНИЕ CODEX"))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(CockpitPalette.amber)
                        Text(request.title)
                            .font(.system(size: 19, weight: .medium, design: .rounded))
                    }
                }

                Text(request.detail)
                    .font(.system(size: 12, design: request.kind == .command ? .monospaced : .default))
                    .foregroundStyle(CockpitPalette.silver)
                    .textSelection(.enabled)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CockpitPalette.canvas.opacity(0.76), in: RoundedRectangle(cornerRadius: 11))

                Text(
                    t(
                        "Review the request before allowing it. “For session” applies the same decision to later matching requests in this Codex session.",
                        "Проверьте запрос перед подтверждением. «Для сессии» применит это решение к следующим похожим запросам в текущей сессии Codex."
                    )
                )
                .font(.caption)
                .foregroundStyle(CockpitPalette.muted)

                HStack(spacing: 10) {
                    Button(t("Decline", "Отклонить")) { model.resolveApproval(request, decision: .decline) }
                        .buttonStyle(CockpitSecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(t("Allow for Session", "Разрешить для сессии")) {
                        model.resolveApproval(request, decision: .acceptForSession)
                    }
                    .buttonStyle(CockpitSecondaryButtonStyle())
                    Button(t("Allow Once", "Разрешить один раз")) { model.resolveApproval(request, decision: .accept) }
                        .buttonStyle(CockpitPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 540)
            .background(CockpitPanel(cornerRadius: 22))
            .shadow(color: .black.opacity(0.28), radius: 38, y: 18)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(t("Codex operation requires approval", "Операция Codex требует подтверждения"))
        }
    }

    private func t(_ english: String, _ russian: String) -> String {
        model.appLanguage.text(english, russian)
    }
}

private struct InstrumentCard: View {
    let label: String
    let value: String
    let icon: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(accent)
                Spacer()
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                    .shadow(color: accent, radius: 4)
            }
            Text(value)
                .font(.system(size: 16, weight: .light, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .tracking(1)
                .foregroundStyle(CockpitPalette.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CockpitPalette.panelRaised.opacity(0.66), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(CockpitPalette.silver.opacity(0.11)))
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.09), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.23)))
    }
}

private struct PowerModeToggle: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let language: AppLanguage
    @Binding var isOn: Bool

    var body: some View {
        PremiumToggleCard(
            title: title,
            subtitle: subtitle,
            icon: icon,
            accent: accent,
            language: language,
            isOn: $isOn
        )
    }
}

struct ThemeSwitcher: View {
    let language: AppLanguage
    @Binding var selection: InterfaceTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(InterfaceTheme.allCases) { theme in
                Button {
                    if reduceMotion {
                        selection = theme
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) { selection = theme }
                    }
                } label: {
                    Image(systemName: theme.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 38, height: 32)
                        .foregroundStyle(selection == theme ? Color.white : CockpitPalette.muted)
                        .background(
                            selection == theme ? CockpitPalette.ice : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(language.text("\(theme.title) appearance", "Тема: \(theme.title(in: language))"))
                .accessibilityLabel(
                    language.text(
                        "Use \(theme.title.lowercased()) appearance", "Использовать тему «\(theme.title(in: language))»"
                    )
                )
                .accessibilityValue(
                    selection == theme
                        ? language.text("Selected", "Выбрано") : language.text("Not selected", "Не выбрано"))
            }
        }
        .padding(4)
        .background(CockpitPalette.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CockpitPalette.separator.opacity(0.62)))
    }
}

struct LanguageSwitcher: View {
    @Binding var selection: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    if reduceMotion {
                        selection = language
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) { selection = language }
                    }
                } label: {
                    Text(language.code)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(width: 38, height: 32)
                        .foregroundStyle(selection == language ? Color.white : CockpitPalette.muted)
                        .background(
                            selection == language ? CockpitPalette.ice : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(language.title)
                .accessibilityLabel("\(language.title) / \(language.code)")
                .accessibilityValue(
                    selection == language
                        ? selection.text("Selected", "Выбрано") : selection.text("Not selected", "Не выбрано"))
            }
        }
        .padding(4)
        .background(CockpitPalette.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CockpitPalette.separator.opacity(0.62)))
    }
}

private struct AmbientBlob: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(.white.opacity(0.16))
                .rotationEffect(.degrees(-18))
            Circle()
                .fill(CockpitPalette.violetSoft.opacity(0.80))
                .frame(width: 82, height: 82)
                .blur(radius: 13)
                .offset(x: -22, y: -15)
            Circle()
                .fill(CockpitPalette.blueSoft.opacity(0.72))
                .frame(width: 74, height: 74)
                .blur(radius: 15)
                .offset(x: 23, y: 19)
            Ellipse()
                .stroke(.white.opacity(0.28), lineWidth: 1)
                .padding(9)
                .rotationEffect(.degrees(14))
        }
        .compositingGroup()
    }
}

struct CockpitBackground: View {
    var body: some View {
        ZStack {
            CockpitPalette.canvas
            LinearGradient(
                colors: [CockpitPalette.violetSoft.opacity(0.075), .clear, CockpitPalette.blueSoft.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(CockpitPalette.violetSoft.opacity(0.08))
                .frame(width: 500, height: 500)
                .blur(radius: 90)
                .offset(x: 380, y: -260)
        }
        .ignoresSafeArea()
    }
}

struct CockpitPanel: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [CockpitPalette.panelRaised.opacity(0.94), CockpitPalette.panel.opacity(0.90)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [CockpitPalette.separator.opacity(0.76), CockpitPalette.separator.opacity(0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

struct CockpitPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [CockpitPalette.violetSoft, CockpitPalette.iceDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .shadow(color: CockpitPalette.ice.opacity(configuration.isPressed ? 0.10 : 0.24), radius: 9)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct CockpitSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(CockpitPalette.silver)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(CockpitPalette.panelRaised.opacity(0.80), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(CockpitPalette.silver.opacity(0.17)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct CockpitDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(3)
            .background(CockpitPalette.danger.opacity(0.78), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.16)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
