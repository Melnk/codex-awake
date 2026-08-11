import SwiftUI

private enum CockpitPalette {
    static let canvas = Color(red: 0.025, green: 0.03, blue: 0.035)
    static let panel = Color(red: 0.055, green: 0.065, blue: 0.072)
    static let panelRaised = Color(red: 0.075, green: 0.087, blue: 0.096)
    static let silver = Color(red: 0.77, green: 0.81, blue: 0.84)
    static let muted = Color(red: 0.50, green: 0.55, blue: 0.59)
    static let ice = Color(red: 0.36, green: 0.90, blue: 0.96)
    static let iceDeep = Color(red: 0.04, green: 0.48, blue: 0.60)
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

            HStack(spacing: 0) {
                controlDeck
                    .frame(width: 314)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, CockpitPalette.silver.opacity(0.28), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1)
                    .padding(.vertical, 22)

                chatDeck
            }
            .padding(18)

            if let approval = model.approvalRequests.first {
                ApprovalOverlay(request: approval)
                    .environmentObject(model)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(minWidth: 980, minHeight: 650)
        .preferredColorScheme(.dark)
    }

    private var controlDeck: some View {
        VStack(alignment: .leading, spacing: 18) {
            brandHeader
            powerControl

            HStack(spacing: 10) {
                InstrumentCard(
                    label: "APP SERVER",
                    value: model.appServerState.rawValue.uppercased(),
                    icon: "point.3.connected.trianglepath.dotted",
                    accent: serverAccent
                )
                InstrumentCard(
                    label: "ACTIVE TASKS",
                    value: "\(model.activity.activeCount)",
                    icon: "waveform.path.ecg",
                    accent: model.activity.activeCount > 0 ? CockpitPalette.ice : CockpitPalette.muted
                )
            }

            activeTasks
            externalChatGPTNotice
            Spacer(minLength: 4)

            HStack(spacing: 10) {
                Button("Diagnostics") { openWindow(id: "diagnostics") }
                    .buttonStyle(CockpitSecondaryButtonStyle())
                Button("Restart") { model.restartServer() }
                    .buttonStyle(CockpitSecondaryButtonStyle())
                    .disabled(model.appServerState == .starting || model.appServerState == .stopping)
            }
        }
        .padding(18)
        .background(CockpitPanel(cornerRadius: 26))
        .padding(.trailing, 18)
    }

    private var brandHeader: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [CockpitPalette.silver, .white, CockpitPalette.muted, CockpitPalette.silver],
                            center: .center
                        ),
                        lineWidth: 1.5
                    )
                Circle()
                    .stroke(CockpitPalette.silver.opacity(0.2), lineWidth: 6)
                    .padding(5)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(CockpitPalette.ice)
            }
            .frame(width: 44, height: 44)
            .shadow(color: CockpitPalette.ice.opacity(0.22), radius: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text("CODEX AWAKE")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.96))
                Text("GRAND TOURING INTERFACE")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(CockpitPalette.muted)
            }
        }
    }

    private var powerControl: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    model.setAutoKeepAwake(!model.autoKeepAwake)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    (model.autoKeepAwake ? CockpitPalette.iceDeep : Color.black).opacity(0.40),
                                    CockpitPalette.panel,
                                    Color.black.opacity(0.96)
                                ],
                                center: .center,
                                startRadius: 3,
                                endRadius: 72
                            )
                        )
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [CockpitPalette.muted, .white, CockpitPalette.muted.opacity(0.3), CockpitPalette.silver],
                                center: .center
                            ),
                            lineWidth: 2
                        )
                    Circle()
                        .trim(from: 0.07, to: 0.93)
                        .stroke(
                            model.autoKeepAwake ? CockpitPalette.ice : CockpitPalette.muted.opacity(0.34),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(90))
                        .padding(9)
                    Image(systemName: "power")
                        .font(.system(size: 38, weight: .ultraLight))
                        .foregroundStyle(model.autoKeepAwake ? Color.white : CockpitPalette.muted)
                        .shadow(color: model.autoKeepAwake ? CockpitPalette.ice : .clear, radius: 12)
                }
                .frame(width: 130, height: 130)
                .shadow(color: model.autoKeepAwake ? CockpitPalette.ice.opacity(0.28) : .black.opacity(0.55), radius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Automatic keep awake")
            .accessibilityValue(model.autoKeepAwake ? "On" : "Off")

            VStack(spacing: 4) {
                Text(model.autoKeepAwake ? "ON" : "OFF")
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(model.autoKeepAwake ? CockpitPalette.ice : CockpitPalette.muted)
                Text(powerSubtitle)
                    .font(.caption)
                    .foregroundStyle(CockpitPalette.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var activeTasks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MANAGED ACTIVE TASKS")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(CockpitPalette.muted)
                Spacer()
                Circle()
                    .fill(model.activity.activeCount > 0 ? CockpitPalette.ice : CockpitPalette.muted.opacity(0.45))
                    .frame(width: 6, height: 6)
                    .shadow(color: CockpitPalette.ice, radius: model.activity.activeCount > 0 ? 5 : 0)
            }

            if model.activity.activeThreadIds.isEmpty {
                Text("No active managed task")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CockpitPalette.silver.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 11))
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(model.activity.activeThreadIds.sorted(), id: \.self) { id in
                            HStack(spacing: 9) {
                                Image(systemName: "waveform")
                                    .foregroundStyle(CockpitPalette.ice)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(id == model.chatThreadID ? "Cockpit task" : "Remote Codex task")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(abbreviated(id))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(CockpitPalette.muted)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(CockpitPalette.ice.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .frame(maxHeight: 100)
            }
        }
    }

    private var externalChatGPTNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "lock.shield")
                .foregroundStyle(CockpitPalette.silver)
            VStack(alignment: .leading, spacing: 3) {
                Text("CHATGPT DESKTOP · EXTERNAL")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1)
                Text("Independent ChatGPT chats are private and are not exposed to third-party monitoring. Only tasks connected to this cockpit are counted.")
                    .font(.system(size: 10))
                    .foregroundStyle(CockpitPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .background(CockpitPalette.silver.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CockpitPalette.silver.opacity(0.12)))
    }

    private var chatDeck: some View {
        VStack(spacing: 0) {
            chatHeader
            chatTimeline
            composer
        }
        .padding(.leading, 18)
    }

    private var chatHeader: some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("CODEX CONSOLE")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .tracking(2.4)
                    StatusPill(text: model.appServerState == .running ? "READY" : "OFFLINE", color: serverAccent)
                }
                Text("Authenticated Codex App Server · streamed agent events")
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
            .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(CockpitPalette.silver.opacity(0.10)))
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
                Image(systemName: "command.circle")
                    .font(.system(size: 38, weight: .ultraLight))
                    .foregroundStyle(CockpitPalette.silver)
            }
            Text(model.workspacePath == nil ? "SELECT A PROJECT" : "READY FOR A NEW TASK")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .tracking(2)
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
        HStack(alignment: .bottom, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Ask Codex to inspect, explain, build, or fix…")
                        .font(.system(size: 13))
                        .foregroundStyle(CockpitPalette.muted.opacity(0.75))
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
            }
            .background(CockpitPalette.panelRaised.opacity(0.82), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(CockpitPalette.silver.opacity(0.16)))

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
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send to Codex (Command-Return)")
            }
        }
        .padding(.top, 13)
        .padding(.horizontal, 5)
    }

    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model.workspacePath != nil
            && model.appServerState == .running
            && !model.chatIsSending
    }

    private var powerSubtitle: String {
        guard model.autoKeepAwake else { return "automatic sleep protection disabled" }
        return model.assertionHeld ? "idle sleep protection engaged" : "armed for active Codex tasks"
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
            return "Choose a working folder. Codex will be limited to that workspace and will ask before sensitive actions."
        }
        if model.appServerState != .running {
            return "The managed Codex App Server is not ready. Install or select Codex CLI, then restart the server."
        }
        return "This console uses your existing Codex authentication through the local App Server. No API key is stored by CodexAwake."
    }

    private func submitPrompt() {
        let submitted = prompt
        prompt = ""
        model.sendPrompt(submitted)
    }

    private func abbreviated(_ value: String) -> String {
        guard value.count > 14 else { return value }
        return "\(value.prefix(8))…\(value.suffix(4))"
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
                    .foregroundStyle(message.role == .system ? CockpitPalette.silver : .white.opacity(0.91))
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
                    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 11))

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
            .shadow(color: .black.opacity(0.75), radius: 38, y: 18)
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

private struct CockpitBackground: View {
    var body: some View {
        ZStack {
            CockpitPalette.canvas
            LinearGradient(
                colors: [Color.white.opacity(0.035), .clear, CockpitPalette.iceDeep.opacity(0.055)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                for x in stride(from: 0.0, through: size.width, by: 48) {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(.white.opacity(0.013)), lineWidth: 0.5)
                }
            }
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
                    colors: [CockpitPalette.panelRaised.opacity(0.92), CockpitPalette.panel.opacity(0.90)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.20), CockpitPalette.silver.opacity(0.05), .black.opacity(0.6)],
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
            .foregroundStyle(Color.black.opacity(0.86))
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color.white, CockpitPalette.ice.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
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
