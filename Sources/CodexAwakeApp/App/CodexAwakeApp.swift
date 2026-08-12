import AppKit
import SwiftUI

extension Notification.Name {
    static let codexAwakeOpenCockpit = Notification.Name("com.melnikoleg.CodexAwake.openCockpit")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminationPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .codexAwakeOpenCockpit, object: nil)
        return true
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
                .preferredColorScheme(model.interfaceTheme.colorScheme)
                .environment(\.locale, model.appLanguage.locale)
        } label: {
            CockpitLaunchingMenuBarLabel(
                symbol: menuBarSymbol,
                activeCount: model.activity.activeCount,
                language: model.appLanguage
            )
        }
        .menuBarExtraStyle(.menu)

        Window("CodexAwake Cockpit", id: "cockpit") {
            CockpitView()
                .environmentObject(model)
                .preferredColorScheme(model.interfaceTheme.colorScheme)
                .environment(\.locale, model.appLanguage.locale)
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        Window("CodexAwake Diagnostics", id: "diagnostics") {
            DiagnosticsView()
                .environmentObject(model)
                .preferredColorScheme(model.interfaceTheme.colorScheme)
                .environment(\.locale, model.appLanguage.locale)
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

private struct CockpitLaunchingMenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @State private var didRequestInitialWindow = false

    let symbol: String
    let activeCount: Int
    let language: AppLanguage

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel(
                language.text(
                    "CodexAwake, \(activeCount) active managed Codex threads",
                    "CodexAwake, активных управляемых потоков Codex: \(activeCount)"
                )
            )
            .task {
                guard !didRequestInitialWindow else { return }
                didRequestInitialWindow = true
                await presentCockpit()
            }
            .onReceive(NotificationCenter.default.publisher(for: .codexAwakeOpenCockpit)) { _ in
                Task { await presentCockpit() }
            }
    }

    @MainActor
    private func presentCockpit() async {
        openWindow(id: "cockpit")
        try? await Task.sleep(for: .milliseconds(120))
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows
            .first(where: { $0.title == "CodexAwake Cockpit" })?
            .makeKeyAndOrderFront(nil)
    }
}
