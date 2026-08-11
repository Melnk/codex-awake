import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("CodexAwake")
            .font(.headline)
        Text("App Server: \(model.appServerState.rawValue.capitalized)")
        Text("Codex: \(model.codexVersion ?? "Not found")")
        Text("Active threads: \(model.activity.activeCount)")
        Text("Keep Awake: \(model.assertionHeld ? "ON" : "OFF")")

        if model.activity.certainty == .unknownReconnecting {
            Text("Activity unknown — reconnecting")
        }

        if !model.firstRunAcknowledged {
            Divider()
            Text("Tracks cockpit tasks and Codex CLI/TUI sessions connected to this app's managed App Server.")
            Text("Independent ChatGPT Desktop chats are not exposed to third-party monitoring.")
            Text("It prevents idle sleep; it does not bypass lid-close sleep.")
            Button("I Understand") { model.acknowledgeFirstRun() }
                .accessibilityLabel("Acknowledge CodexAwake tracking scope")
        }

        if !model.activity.activeThreadIds.isEmpty {
            Divider()
            Text("Active sessions")
            ForEach(model.activity.activeThreadIds.sorted(), id: \.self) { id in
                Text("• Thread \(abbreviated(id))")
            }
        }

        Divider()
        Text("Managed CodexAwake tasks are tracked")
        Text("Independent ChatGPT Desktop chats are private")
        Text("Prevents idle sleep only; lid-close policy still applies")
        Button("Open Cockpit…") { openWindow(id: "cockpit") }
            .keyboardShortcut("k")
            .accessibilityLabel("Open the CodexAwake cockpit")
        Button("Open Codex") { model.openCodex() }
            .disabled(model.codexCommand == nil || model.appServerState != .running)
            .keyboardShortcut("o")
            .accessibilityLabel("Open Codex connected to the CodexAwake App Server")
        Button("Copy Codex command") { model.copyCodexCommand() }
            .disabled(model.codexCommand == nil)
            .accessibilityLabel("Copy the managed Codex remote command")

        Divider()
        Toggle("Auto Keep Awake", isOn: Binding(
            get: { model.autoKeepAwake },
            set: { model.setAutoKeepAwake($0) }
        ))
        Toggle("Launch at Login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))

        Divider()
        Button("Diagnostics…") { openWindow(id: "diagnostics") }
            .keyboardShortcut(",")
        if model.appServerState == .stopped || model.appServerState == .failed {
            Button("Start App Server") { Task { await model.startManagedServer() } }
        } else {
            Button("Restart App Server") { model.restartServer() }
            Button("Stop App Server") { model.stopServer() }
        }

        Divider()
        Button("Quit CodexAwake") { model.requestQuit() }
            .keyboardShortcut("q")
    }

    private func abbreviated(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(8))…\(value.suffix(4))"
    }
}
