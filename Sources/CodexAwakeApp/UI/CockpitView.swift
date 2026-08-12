import AppKit
import CodexAwakeCore
import SwiftUI

private enum CockpitPalette {
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

struct CockpitView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var prompt = ""
    @FocusState private var promptFocused: Bool

    var body: some View {
        ZStack {
            CockpitBackground()

            VStack(spacing: 0) {
                topBar

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

            if let approval = model.approvalRequests.first {
                ApprovalOverlay(request: approval)
                    .environmentObject(model)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(minWidth: 860, minHeight: 620)
    }

    private var topBar: some View {
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

    private var controlDeck: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                powerControl
                powerModesControl

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
                HStack(spacing: 11) {
                    Image(systemName: "macwindow.and.cursorarrow")
                        .foregroundStyle(CockpitPalette.ice)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("While Codex is open", "Пока Codex открыт"))
                            .font(.system(size: 11, weight: .semibold))
                        Text(
                            t(
                                "Keep this Mac and display awake between tasks",
                                "Не выключать Mac и экран между задачами")
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(CockpitPalette.muted)
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.keepAwakeForCodexDesktop },
                            set: { model.setKeepAwakeForCodexDesktop($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(13)
                .background(CockpitPalette.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(CockpitPalette.separator.opacity(0.58)))

                closedLidControl

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
                HStack {
                    Label(t("Sleep protection", "Защита от сна"), systemImage: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.autoKeepAwake },
                            set: { model.setAutoKeepAwake($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.white.opacity(0.88))
                }

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
            Text(t("PROTECTION MODES", "РЕЖИМЫ ЗАЩИТЫ"))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(CockpitPalette.muted)

            PowerModeToggle(
                title: t("Keep Mac awake", "Не давать Mac уснуть"),
                subtitle: t("Background work keeps running", "Фоновые задачи продолжат работать"),
                icon: "moon.zzz",
                accent: model.powerAssertions.systemSleepPrevented ? CockpitPalette.ice : CockpitPalette.muted,
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
                isOn: Binding(
                    get: { model.preventDisplaySleep },
                    set: { model.setPreventDisplaySleep($0) }
                )
            )

            PowerModeToggle(
                title: t("Launch at login", "Запускать при входе"),
                subtitle: launchAtLoginSubtitle,
                icon: "person.crop.circle.badge.checkmark",
                accent: model.launchAtLogin ? CockpitPalette.ice : CockpitPalette.muted,
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
        }
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
            HStack(spacing: 9) {
                Image(systemName: model.closedLidProtection.leaseActive ? "lock.open.display" : "lock.display")
                    .foregroundStyle(closedLidAccent)
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
                Toggle(
                    "",
                    isOn: Binding(
                        get: { model.closedLidProtectionEnabled },
                        set: { model.setClosedLidProtectionEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

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
        VStack(spacing: 0) {
            chatHeader
            chatTimeline
            composer
        }
        .padding(18)
        .background(CockpitPanel(cornerRadius: 28))
    }

    private var chatHeader: some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(t("Chat with Codex", "Чат с Codex"))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    StatusPill(
                        text: model.appServerState == .running ? t("READY", "ГОТОВ") : t("OFFLINE", "НЕ В СЕТИ"),
                        color: serverAccent)
                }
                Text(
                    t(
                        "Your local Codex session — no separate API key",
                        "Локальная сессия Codex — отдельный API-ключ не нужен")
                )
                .font(.caption)
                .foregroundStyle(CockpitPalette.muted)
            }
            Spacer()

            Button {
                model.chooseWorkspace()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t("PROJECT", "ПРОЕКТ"))
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(1)
                        Text(workspaceName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(CockpitSecondaryButtonStyle())
            .help(model.workspacePath ?? t("Choose a project folder", "Выберите папку проекта"))

            Button {
                model.newChat()
                promptFocused = true
            } label: {
                Label(t("New task", "Новая задача"), systemImage: "plus")
            }
            .buttonStyle(CockpitSecondaryButtonStyle())
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 11)
    }

    private var chatTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 15) {
                    if model.chatMessages.isEmpty {
                        emptyChat
                    } else {
                        ForEach(model.chatMessages) { message in
                            ChatMessageRow(message: message, language: model.appLanguage)
                                .id(message.id)
                        }
                    }

                    if model.chatIsSending, !model.chatMessages.contains(where: { $0.isStreaming }) {
                        ThinkingIndicator(language: model.appLanguage)
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 22)
            }
            .background(CockpitPalette.canvas.opacity(0.56), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(CockpitPalette.separator.opacity(0.58)))
            .onChange(of: model.chatMessages.count) { _, _ in
                if let last = model.chatMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: model.chatIsSending) { _, sending in
                if sending {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("thinking", anchor: .bottom) }
                }
            }
        }
    }

    private var emptyChat: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(CockpitPalette.ice.opacity(0.06))
                    .frame(width: 92, height: 92)
                Circle()
                    .stroke(CockpitPalette.silver.opacity(0.22), lineWidth: 1)
                    .frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .ultraLight))
                    .foregroundStyle(CockpitPalette.silver)
            }
            Text(
                model.workspacePath == nil
                    ? t("Choose a project", "Выберите проект")
                    : t("What would you like to build?", "Что вы хотите сделать?")
            )
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(emptyChatDescription)
                .font(.system(size: 12))
                .foregroundStyle(CockpitPalette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            if model.workspacePath == nil {
                Button(t("Choose Project…", "Выбрать проект…")) { model.chooseWorkspace() }
                    .buttonStyle(CockpitPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField(
                    t(
                        "Ask Codex to inspect, explain, build, or fix…",
                        "Попросите Codex проверить, объяснить, собрать или исправить…"),
                    text: $prompt,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...6)
                .focused($promptFocused)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
                .background(CockpitPalette.panelRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(CockpitPalette.separator.opacity(0.72)))
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        prompt.append("\n")
                        return .handled
                    }
                    guard canAttemptSend else { return .handled }
                    submitPrompt()
                    return .handled
                }

                if model.chatIsSending {
                    Button {
                        model.interruptChat()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(CockpitDangerButtonStyle())
                    .disabled(model.chatTurnID == nil)
                    .help(t("Stop current task", "Остановить текущую задачу"))
                } else {
                    Button {
                        submitPrompt()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(CockpitPrimaryButtonStyle())
                    .disabled(!canAttemptSend)
                    .help(model.chatUnavailableReason ?? t("Send to Codex", "Отправить в Codex"))
                }
            }

            HStack(spacing: 6) {
                Image(systemName: model.chatUnavailableReason == nil ? "return" : "exclamationmark.circle")
                Text(composerStatusText)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(model.chatUnavailableReason == nil ? CockpitPalette.muted : CockpitPalette.amber)
            .padding(.leading, 9)
        }
        .padding(.top, 13)
        .padding(.horizontal, 5)
    }

    private var canAttemptSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.chatIsSending
    }

    private var composerStatusText: String {
        model.chatUnavailableReason
            ?? t("Enter to send · Shift+Enter for a new line", "Enter — отправить · Shift+Enter — новая строка")
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

    private var workspaceName: String {
        guard let workspacePath = model.workspacePath else { return t("Choose folder", "Выбрать папку") }
        return URL(fileURLWithPath: workspacePath).lastPathComponent
    }

    private var emptyChatDescription: String {
        if model.workspacePath == nil {
            return t(
                "Choose the folder Codex should work in. It will ask before sensitive actions.",
                "Выберите папку для работы Codex. Перед важными действиями он спросит разрешение.")
        }
        if model.appServerState != .running {
            return t(
                "Codex is connecting. This usually takes only a moment.",
                "Codex подключается. Обычно это занимает несколько секунд.")
        }
        return t(
            "Use your existing Codex sign-in right here. CodexAwake never stores an API key.",
            "Используйте текущий вход в Codex. CodexAwake не хранит API-ключ.")
    }

    private func submitPrompt() {
        if model.sendPrompt(prompt) {
            prompt = ""
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

private struct ChatMessageRow: View {
    let message: CodexChatMessage
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user { Spacer(minLength: 70) }

            if message.role == .assistant {
                avatar(systemName: "sparkles", color: CockpitPalette.ice)
            } else if message.role == .system {
                avatar(systemName: "exclamationmark.triangle", color: CockpitPalette.amber)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(roleLabel)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(roleColor)
                    if message.isStreaming {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Spacer()
                }
                Text(renderedText)
                    .font(.system(size: 13))
                    .foregroundStyle(CockpitPalette.silver)
                    .textSelection(.enabled)
                    .lineSpacing(3)
            }
            .padding(13)
            .frame(maxWidth: message.role == .user ? 520 : .infinity, alignment: .leading)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(borderColor))

            if message.role != .user { Spacer(minLength: 34) }
        }
    }

    private var renderedText: AttributedString {
        (try? AttributedString(markdown: message.text)) ?? AttributedString(message.text)
    }

    private var roleLabel: String {
        switch message.role {
        case .user: language.text("YOU", "ВЫ")
        case .assistant:
            message.phase == "commentary" ? language.text("CODEX · PROGRESS", "CODEX · ХОД РАБОТЫ") : "CODEX"
        case .system: language.text("SYSTEM", "СИСТЕМА")
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user: CockpitPalette.silver
        case .assistant: CockpitPalette.ice
        case .system: CockpitPalette.amber
        }
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: CockpitPalette.iceDeep.opacity(0.19)
        case .assistant: CockpitPalette.panelRaised.opacity(0.77)
        case .system: CockpitPalette.amber.opacity(0.075)
        }
    }

    private var borderColor: Color {
        switch message.role {
        case .user: CockpitPalette.ice.opacity(0.22)
        case .assistant: CockpitPalette.silver.opacity(0.12)
        case .system: CockpitPalette.amber.opacity(0.22)
        }
    }

    private func avatar(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 27, height: 27)
            .background(color.opacity(0.10), in: Circle())
            .overlay(Circle().stroke(color.opacity(0.25)))
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
                    Spacer()
                    Button(t("Allow for Session", "Разрешить для сессии")) {
                        model.resolveApproval(request, decision: .acceptForSession)
                    }
                    .buttonStyle(CockpitSecondaryButtonStyle())
                    Button(t("Allow Once", "Разрешить один раз")) { model.resolveApproval(request, decision: .accept) }
                        .buttonStyle(CockpitPrimaryButtonStyle())
                }
            }
            .padding(24)
            .frame(width: 540)
            .background(CockpitPanel(cornerRadius: 22))
            .shadow(color: .black.opacity(0.28), radius: 38, y: 18)
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

private struct ThinkingIndicator: View {
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(CockpitPalette.ice)
            Text(language.text("Codex is working…", "Codex работает…"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CockpitPalette.muted)
            Spacer()
        }
        .padding(.horizontal, 10)
    }
}

private struct PowerModeToggle: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CockpitPalette.silver)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(CockpitPalette.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(12)
        .background(CockpitPalette.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CockpitPalette.separator.opacity(0.55)))
        .accessibilityHint(subtitle)
    }
}

private struct ThemeSwitcher: View {
    let language: AppLanguage
    @Binding var selection: InterfaceTheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(InterfaceTheme.allCases) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = theme
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

private struct LanguageSwitcher: View {
    @Binding var selection: AppLanguage

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = language
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

private struct CockpitBackground: View {
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

private struct CockpitPanel: View {
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

private struct CockpitPrimaryButtonStyle: ButtonStyle {
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

private struct CockpitSecondaryButtonStyle: ButtonStyle {
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

private struct CockpitDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(3)
            .background(CockpitPalette.danger.opacity(0.78), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.16)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
