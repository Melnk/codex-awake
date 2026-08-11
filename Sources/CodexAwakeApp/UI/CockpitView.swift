import AppKit
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

                HStack(spacing: 20) {
                    controlDeck
                        .frame(width: 320)
                    chatDeck
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
        .frame(minWidth: 1040, minHeight: 700)
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
                Text("Keep your Codex work running")
                    .font(.system(size: 11))
                    .foregroundStyle(CockpitPalette.muted)
            }

            StatusPill(
                text: model.appServerState == .running ? "CODEX READY" : "CONNECTING",
                color: serverAccent
            )
            .padding(.leading, 8)

            Spacer()

            Label(
                "\(model.totalActiveSessionCount) active",
                systemImage: model.totalActiveSessionCount > 0 ? "waveform.path.ecg" : "waveform"
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(CockpitPalette.muted)

            ThemeSwitcher(selection: Binding(
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

                HStack(spacing: 10) {
                    InstrumentCard(
                        label: "CODEX APP",
                        value: model.codexDesktopRunning ? "ON" : "OFF",
                        icon: "macwindow",
                        accent: model.codexDesktopRunning ? CockpitPalette.ice : CockpitPalette.muted
                    )
                    InstrumentCard(
                        label: "ACTIVE SESSIONS",
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
                        Text("While Codex is open")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Keep this Mac awake even between tasks")
                            .font(.system(size: 9))
                            .foregroundStyle(CockpitPalette.muted)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.keepAwakeForCodexDesktop },
                        set: { model.setKeepAwakeForCodexDesktop($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(13)
                .background(CockpitPalette.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(CockpitPalette.separator.opacity(0.58)))

                closedLidControl

                HStack(spacing: 10) {
                    Button("Diagnostics") { openWindow(id: "diagnostics") }
                        .buttonStyle(CockpitSecondaryButtonStyle())
                    Button("Restart") { model.restartServer() }
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
                    Label("Sleep protection", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.autoKeepAwake },
                        set: { model.setAutoKeepAwake($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.white.opacity(0.88))
                }

                Text(model.autoKeepAwake ? "Your Mac stays awake" : "Protection is paused")
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
                    Text(model.autoKeepAwake ? "ON" : "OFF")
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
                Text("ACTIVE SESSIONS")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(CockpitPalette.muted)
                Spacer()
                Circle()
                    .fill(model.totalActiveSessionCount > 0 ? CockpitPalette.ice : CockpitPalette.muted.opacity(0.45))
                    .frame(width: 6, height: 6)
                    .shadow(color: CockpitPalette.ice, radius: model.totalActiveSessionCount > 0 ? 5 : 0)
            }

            if model.totalActiveSessionCount == 0 {
                Label("No active Codex sessions", systemImage: "checkmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CockpitPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(CockpitPalette.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(CockpitPalette.separator.opacity(0.55)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(model.codexDesktopActiveSessionIDs.sorted(), id: \.self) { id in
                            ActiveSessionRow(
                                title: "Codex Desktop task",
                                id: abbreviated(id),
                                icon: "macwindow",
                                accent: CockpitPalette.ice
                            )
                        }
                        ForEach(model.activity.activeThreadIds.sorted(), id: \.self) { id in
                            ActiveSessionRow(
                                title: id == model.chatThreadID ? "Cockpit task" : "Managed Codex task",
                                id: abbreviated(id),
                                icon: "waveform",
                                accent: CockpitPalette.ice
                            )
                        }
                    }
                }
                .frame(maxHeight: 100)
            }
        }
    }

    private var externalChatGPTNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: model.codexDesktopRunning ? "dot.radiowaves.left.and.right" : "power")
                .foregroundStyle(model.codexDesktopRunning ? CockpitPalette.ice : CockpitPalette.silver)
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex app")
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
                    Text("Closed-lid mode")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(0.9)
                    Text(closedLidStatusText)
                        .font(.system(size: 10))
                        .foregroundStyle(CockpitPalette.muted)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.closedLidProtectionEnabled },
                    set: { model.setClosedLidProtectionEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if !model.closedLidProtection.helperInstalled || !model.closedLidProtection.helperReachable {
                Button("Enable closed-lid mode") { model.installClosedLidHelper() }
                    .buttonStyle(CockpitSecondaryButtonStyle())
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(model.closedLidActionMessage ?? "Requires administrator approval once. Restores normal sleep when its lease expires.")
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
                    Text("Chat with Codex")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    StatusPill(text: model.appServerState == .running ? "READY" : "OFFLINE", color: serverAccent)
                }
                Text("Your local Codex session — no separate API key")
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
                        Text("PROJECT")
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(1)
                        Text(workspaceName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(CockpitSecondaryButtonStyle())
            .help(model.workspacePath ?? "Choose a project folder")

            Button {
                model.newChat()
                promptFocused = true
            } label: {
                Label("New task", systemImage: "plus")
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
                            ChatMessageRow(message: message)
                                .id(message.id)
                        }
                    }

                    if model.chatIsSending, !model.chatMessages.contains(where: { $0.isStreaming }) {
                        ThinkingIndicator()
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
            Text(model.workspacePath == nil ? "Choose a project" : "What would you like to build?")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(emptyChatDescription)
                .font(.system(size: 12))
                .foregroundStyle(CockpitPalette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            if model.workspacePath == nil {
                Button("Choose Project…") { model.chooseWorkspace() }
                    .buttonStyle(CockpitPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .bottom, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("Ask Codex to inspect, explain, build, or fix…")
                            .font(.system(size: 13))
                            .foregroundStyle(CockpitPalette.muted.opacity(0.86))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $prompt)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .focused($promptFocused)
                        .frame(minHeight: 54, maxHeight: 110)
                        .padding(7)
                        .onKeyPress(keys: [.return], phases: .down) { press in
                            guard !press.modifiers.contains(.shift) else { return .ignored }
                            guard canAttemptSend else { return .handled }
                            submitPrompt()
                            return .handled
                        }
                }
                .background(CockpitPalette.panelRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(CockpitPalette.separator.opacity(0.72)))

                if model.chatIsSending {
                    Button {
                        model.interruptChat()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(CockpitDangerButtonStyle())
                    .disabled(model.chatTurnID == nil)
                    .help("Stop current task")
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
                    .help(model.chatUnavailableReason ?? "Send to Codex")
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
        model.chatUnavailableReason ?? "Enter to send · Shift+Enter for a new line"
    }

    private var codexDesktopPresenceDescription: String {
        if model.codexDesktopRunning {
            if !model.codexDesktopActiveSessionIDs.isEmpty {
                let count = model.codexDesktopActiveSessionIDs.count
                return "\(count) active \(count == 1 ? "session" : "sessions") detected. Your prompts and answers stay private."
            }
            return model.keepAwakeForCodexDesktop
                ? "Codex is open. This Mac stays awake between tasks."
                : "Codex is open. Only active tasks prevent sleep."
        }
        return "Codex is closed. Open it to enable app-based protection."
    }

    private var powerSubtitle: String {
        guard model.autoKeepAwake else { return "Turn it on to protect active Codex work from sleep." }
        if model.closedLidProtection.leaseActive {
            return "Closed-lid mode is active. You can close your MacBook."
        }
        if model.assertionHeld, !model.codexDesktopActiveSessionIDs.isEmpty {
            return "An active Codex session is protected from sleep."
        }
        if model.assertionHeld, model.codexDesktopRunning, model.keepAwakeForCodexDesktop {
            return "Codex is open, so sleep protection is active."
        }
        return model.assertionHeld ? "Sleep protection is active." : "Ready — protection starts with your next Codex task."
    }

    private var closedLidAccent: Color {
        if model.closedLidProtection.leaseActive { return CockpitPalette.ice }
        if model.closedLidProtectionEnabled, model.closedLidProtection.helperInstalled { return CockpitPalette.amber }
        return CockpitPalette.muted
    }

    private var closedLidStatusText: String {
        if model.closedLidProtection.leaseActive { return "Active — you can close the lid" }
        if !model.closedLidProtection.helperInstalled { return "One-time setup required" }
        if !model.closedLidProtection.helperReachable { return "A quick update is required" }
        if model.closedLidProtectionEnabled { return "Ready — starts with protected work" }
        return "Off — closing the lid sleeps normally"
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
        guard let workspacePath = model.workspacePath else { return "Choose folder" }
        return URL(fileURLWithPath: workspacePath).lastPathComponent
    }

    private var emptyChatDescription: String {
        if model.workspacePath == nil {
            return "Choose the folder Codex should work in. It will ask before sensitive actions."
        }
        if model.appServerState != .running {
            return "Codex is connecting. This usually takes only a moment."
        }
        return "Use your existing Codex sign-in right here. CodexAwake never stores an API key."
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
}

private struct ActiveSessionRow: View {
    let title: String
    let id: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(id)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(CockpitPalette.muted)
            }
            Spacer()
        }
        .padding(10)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ChatMessageRow: View {
    let message: CodexChatMessage

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
        case .user: "YOU"
        case .assistant: message.phase == "commentary" ? "CODEX · PROGRESS" : "CODEX"
        case .system: "SYSTEM"
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
                        Text("CODEX APPROVAL")
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

                Text("Review the request before allowing it. “For session” applies the same decision to later matching requests in this Codex session.")
                    .font(.caption)
                    .foregroundStyle(CockpitPalette.muted)

                HStack(spacing: 10) {
                    Button("Decline") { model.resolveApproval(request, decision: .decline) }
                        .buttonStyle(CockpitSecondaryButtonStyle())
                    Spacer()
                    Button("Allow for Session") { model.resolveApproval(request, decision: .acceptForSession) }
                        .buttonStyle(CockpitSecondaryButtonStyle())
                    Button("Allow Once") { model.resolveApproval(request, decision: .accept) }
                        .buttonStyle(CockpitPrimaryButtonStyle())
                }
            }
            .padding(24)
            .frame(width: 540)
            .background(CockpitPanel(cornerRadius: 22))
            .shadow(color: .black.opacity(0.28), radius: 38, y: 18)
        }
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
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(CockpitPalette.ice)
            Text("Codex is working…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CockpitPalette.muted)
            Spacer()
        }
        .padding(.horizontal, 10)
    }
}

private struct ThemeSwitcher: View {
    @Binding var selection: InterfaceTheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(InterfaceTheme.allCases) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = theme
                    }
                } label: {
                    Image(systemName: theme.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 32, height: 28)
                        .foregroundStyle(selection == theme ? Color.white : CockpitPalette.muted)
                        .background(
                            selection == theme ? CockpitPalette.ice : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help("\(theme.title) appearance")
                .accessibilityLabel("Use \(theme.title.lowercased()) appearance")
                .accessibilityValue(selection == theme ? "Selected" : "Not selected")
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
