import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminationPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model?.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending, let model else { return .terminateNow }
        terminationPending = true
        Task { @MainActor in
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct CodexAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        appDelegate.model = model
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(model)
        } label: {
            Image(systemName: menuBarSymbol)
                .accessibilityLabel("CodexAwake, \(model.activity.activeCount) active managed Codex threads")
        }
        .menuBarExtraStyle(.menu)

        Window("CodexAwake Cockpit", id: "cockpit") {
            CockpitView()
                .environmentObject(model)
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        Window("CodexAwake Diagnostics", id: "diagnostics") {
            DiagnosticsView()
                .environmentObject(model)
        }
        .defaultSize(width: 620, height: 520)
        .windowResizability(.contentMinSize)
    }

    private var menuBarSymbol: String {
        if model.activity.certainty == .unknownReconnecting { return "bolt.trianglebadge.exclamationmark" }
        if model.assertionHeld { return "bolt.circle.fill" }
        return "bolt.circle"
    }

}
