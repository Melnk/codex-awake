import CodexAwakeCore
import SwiftUI

struct ReliableChatMessageRow: View, Equatable {
    let message: CodexChatMessage
    let language: AppLanguage
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user { Spacer(minLength: 70) }
            if message.role != .user { avatar }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Text(roleLabel)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(roleColor)
                    if message.isStreaming { ProgressView().controlSize(.mini) }
                    if let deliveryTitle {
                        Text(deliveryTitle)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(deliveryColor)
                    }
                    Spacer()
                }

                Text(renderedText)
                    .font(.system(size: 13))
                    .foregroundStyle(CockpitPalette.silver)
                    .textSelection(.enabled)
                    .lineSpacing(3)

                if let failureReason = message.failureReason {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(failureReason)
                            .font(.system(size: 10))
                            .foregroundStyle(CockpitPalette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: retry) {
                            Label(language.text("Retry", "Повторить"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(CockpitSecondaryButtonStyle())
                    }
                }
            }
            .padding(13)
            .frame(maxWidth: message.role == .user ? 540 : .infinity, alignment: .leading)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(borderColor))

            if message.role != .user { Spacer(minLength: 34) }
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message && lhs.language == rhs.language
    }

    private var renderedText: AttributedString {
        // Parsing Markdown for every streamed token becomes increasingly
        // expensive as the response grows. Render the live tail as plain text
        // and parse it once when Codex marks the message as complete.
        guard !message.isStreaming else { return AttributedString(message.text) }
        return (try? AttributedString(markdown: message.text)) ?? AttributedString(message.text)
    }

    private var roleLabel: String {
        switch message.role {
        case .user: language.text("YOU", "ВЫ")
        case .assistant:
            message.phase == "commentary"
                ? language.text("CODEX · PROGRESS", "CODEX · ХОД РАБОТЫ")
                : "CODEX"
        case .system: language.text("SYSTEM", "СИСТЕМА")
        }
    }

    private var deliveryTitle: String? {
        switch message.delivery {
        case .queued: language.text("QUEUED", "В ОЧЕРЕДИ")
        case .sending: language.text("SENDING", "ОТПРАВКА")
        case .sent: nil
        case .failed: language.text("NOT SENT", "НЕ ОТПРАВЛЕНО")
        case nil: nil
        }
    }

    private var deliveryColor: Color {
        switch message.delivery {
        case .failed: CockpitPalette.danger
        case .queued: CockpitPalette.amber
        default: CockpitPalette.ice
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
        case .user:
            message.delivery == .failed
                ? CockpitPalette.danger.opacity(0.35)
                : CockpitPalette.ice.opacity(0.22)
        case .assistant: CockpitPalette.silver.opacity(0.12)
        case .system: CockpitPalette.amber.opacity(0.22)
        }
    }

    private var avatar: some View {
        let color = message.role == .assistant ? CockpitPalette.ice : CockpitPalette.amber
        return Image(systemName: message.role == .assistant ? "sparkles" : "exclamationmark.triangle")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 27, height: 27)
            .background(color.opacity(0.10), in: Circle())
            .overlay(Circle().stroke(color.opacity(0.25)))
    }
}

struct ChatActivityView: View {
    let activities: [CodexToolActivity]
    let language: AppLanguage

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(language.text("Activity", "Активность"), systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(
                        language.text(
                            "Paths only · file contents stay private", "Только пути · содержимое файлов приватно")
                    )
                    .font(.system(size: 8))
                    .foregroundStyle(CockpitPalette.muted)
                }
                ForEach(Array(activities.suffix(8).reversed())) { activity in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: symbol(activity.kind))
                            .foregroundStyle(color(activity.status))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(localizedTitle(activity))
                                    .font(.system(size: 10, weight: .semibold))
                                Spacer()
                                Text(statusTitle(activity.status))
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(color(activity.status))
                            }
                            if let detail = activity.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(CockpitPalette.muted)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                            ForEach(activity.changedFiles.prefix(6), id: \.self) { path in
                                Text(path)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(CockpitPalette.muted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(8)
                    .background(CockpitPalette.panelRaised.opacity(0.58), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(10)
        }
        .background(CockpitPalette.canvas.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private func localizedTitle(_ activity: CodexToolActivity) -> String {
        switch activity.kind {
        case .command: language.text("Command", "Команда")
        case .fileChange: language.text("File changes", "Изменения файлов")
        case .webSearch: language.text("Web search", "Поиск в интернете")
        case .image: language.text("Image operation", "Работа с изображением")
        case .collaboration: language.text("Collaboration", "Совместная работа")
        case .mcp, .other: activity.title
        }
    }

    private func statusTitle(_ status: CodexToolStatus) -> String {
        switch status {
        case .running: language.text("RUNNING", "ВЫПОЛНЯЕТСЯ")
        case .completed: language.text("DONE", "ГОТОВО")
        case .failed: language.text("FAILED", "ОШИБКА")
        case .declined: language.text("DECLINED", "ОТКЛОНЕНО")
        }
    }

    private func symbol(_ kind: CodexToolKind) -> String {
        switch kind {
        case .command: "terminal"
        case .fileChange: "doc.badge.gearshape"
        case .mcp: "shippingbox"
        case .webSearch: "globe"
        case .image: "photo"
        case .collaboration: "person.2"
        case .other: "gearshape"
        }
    }

    private func color(_ status: CodexToolStatus) -> Color {
        switch status {
        case .running: CockpitPalette.ice
        case .completed: .green
        case .failed: CockpitPalette.danger
        case .declined: CockpitPalette.amber
        }
    }
}

struct ChatStatusPill: View {
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

struct ReliableThinkingIndicator: View {
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
