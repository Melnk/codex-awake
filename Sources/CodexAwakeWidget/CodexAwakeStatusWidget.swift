import CodexAwakeCore
import SwiftUI
import WidgetKit

private struct CodexAwakeStatusEntry: TimelineEntry {
    let date: Date
    let status: SharedStatusSnapshot
}

private struct CodexAwakeStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexAwakeStatusEntry {
        CodexAwakeStatusEntry(
            date: Date(),
            status: .init(
                protectionEnabled: true,
                assertionHeld: true,
                activeTaskCount: 1,
                profile: .work,
                isOnExternalPower: true,
                protectedSeconds: 7_200,
                sleepPreventionSessions: 4
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexAwakeStatusEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexAwakeStatusEntry>) -> Void) {
        let current = entry()
        completion(
            Timeline(
                entries: [current],
                policy: .after(Calendar.current.date(byAdding: .minute, value: 5, to: current.date) ?? current.date)
            )
        )
    }

    private func entry() -> CodexAwakeStatusEntry {
        CodexAwakeStatusEntry(
            date: Date(),
            status: SharedStatusStorage.read() ?? .init(protectionEnabled: false)
        )
    }
}

private struct CodexAwakeStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexAwakeStatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: entry.status.assertionHeld ? "bolt.circle.fill" : "bolt.circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(entry.status.assertionHeld ? Color.white : Color.white.opacity(0.62))
                Spacer()
                Circle()
                    .fill(entry.status.assertionHeld ? Color.green : Color.white.opacity(0.35))
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("CodexAwake")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(entry.status.assertionHeld ? "PROTECTION ACTIVE" : "STANDBY")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.70))
            }

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                metric(value: "\(entry.status.activeTaskCount)", label: "TASKS")
                if family != .systemSmall {
                    metric(value: duration(entry.status.protectedSeconds), label: "PROTECTED")
                    metric(value: "\(entry.status.sleepPreventionSessions)", label: "SESSIONS")
                }
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.17, green: 0.05, blue: 0.42), Color(red: 0.38, green: 0.16, blue: 0.91)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(URL(string: "codexawake://open/cockpit"))
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let hours = max(0, Int(seconds) / 3_600)
        return hours > 0 ? "\(hours)h" : "\(max(0, Int(seconds) / 60))m"
    }
}

@main
struct CodexAwakeStatusWidget: Widget {
    let kind = "CodexAwakeStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexAwakeStatusProvider()) { entry in
            CodexAwakeStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexAwake Status")
        .description("Protection, active tasks, and protected-time statistics without chat content.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
