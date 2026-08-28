import AppKit
import CodexAwakeCore
import SwiftUI

extension Notification.Name {
    static let codexAwakeOpenCockpit = Notification.Name("com.melnikoleg.CodexAwake.openCockpit")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminationPending = false
    private var terminationReplySent = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        guard claimPrimaryApplicationInstance() else {
            NSApplication.shared.terminate(nil)
            return
        }
        model?.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.refreshSystemIntegrationStatus()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending, let model else { return .terminateNow }
        terminationPending = true
        Task { @MainActor in
            let watchdog = Task { @MainActor [weak self, weak sender] in
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                guard let self, let sender else { return }
                self.finishTermination(of: sender)
            }
            await model.shutdown()
            watchdog.cancel()
            finishTermination(of: sender)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .codexAwakeOpenCockpit, object: nil)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            model?.handleAutomationURL(url)
        }
    }

    private func claimPrimaryApplicationInstance() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentURL = Bundle.main.bundleURL.standardizedFileURL
        let otherInstances = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.melnikoleg.CodexAwake"
        ).filter { $0.processIdentifier != currentPID }

        guard !otherInstances.isEmpty else { return true }

        let isInstalledCopy = currentURL.path.hasPrefix("/Applications/")
        if isInstalledCopy {
            // The installed copy is authoritative. Stop stray developer/dist
            // copies so they cannot duplicate monitoring and permission prompts.
            for application in otherInstances {
                _ = application.terminate()
            }
            return true
        }

        let preferred =
            otherInstances.first {
                $0.bundleURL?.standardizedFileURL.path.hasPrefix("/Applications/") == true
            } ?? otherInstances[0]
        preferred.activate(options: [.activateAllWindows])
        return false
    }

    private func finishTermination(of application: NSApplication) {
        guard !terminationReplySent else { return }
        terminationReplySent = true
        application.reply(toApplicationShouldTerminate: true)
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
                activeCount: model.totalActiveSessionCount,
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
        .commands {
            CommandMenu(model.appLanguage.text("Automation", "Автоматизация")) {
                Button(model.appLanguage.text("Toggle Protection", "Переключить защиту")) {
                    model.setAutoKeepAwake(!model.autoKeepAwake)
                }
                .keyboardShortcut("a", modifiers: [.command, .option])

                Divider()
                Button(profileCommandTitle(.work)) { model.applyProtectionProfile(.work) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button(profileCommandTitle(.nightTask)) { model.applyProtectionProfile(.nightTask) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button(profileCommandTitle(.closedLid)) { model.applyProtectionProfile(.closedLid) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button(profileCommandTitle(.presentation)) { model.applyProtectionProfile(.presentation) }
                    .keyboardShortcut("4", modifiers: [.command, .option])
            }
        }

        Window("CodexAwake Diagnostics", id: "diagnostics") {
            DiagnosticsView(diagnostics: model.diagnostics)
                .environmentObject(model)
                .preferredColorScheme(model.interfaceTheme.colorScheme)
                .environment(\.locale, model.appLanguage.locale)
        }
        .defaultSize(width: 620, height: 520)
        .windowResizability(.contentMinSize)
    }

    private var menuBarSymbol: String {
        if model.activity.certainty == .unknownReconnecting { return "bolt.trianglebadge.exclamationmark" }
        if model.closedLidProtection.connectionState == .reconnecting,
            model.closedLidProtectionEnabled
        {
            return "bolt.trianglebadge.exclamationmark"
        }
        if model.assertionHeld || model.closedLidProtection.leaseActive { return "bolt.circle.fill" }
        return "bolt.circle"
    }

    private func profileCommandTitle(_ profile: ProtectionProfileID) -> String {
        switch profile {
        case .work: model.appLanguage.text("Profile: Work", "Профиль: Работа")
        case .nightTask: model.appLanguage.text("Profile: Night Task", "Профиль: Ночная задача")
        case .closedLid: model.appLanguage.text("Profile: Closed Lid", "Профиль: Закрытая крышка")
        case .presentation: model.appLanguage.text("Profile: Presentation", "Профиль: Презентация")
        }
    }

}

private struct CockpitLaunchingMenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @State private var didRequestInitialWindow = false

    let symbol: String
    let activeCount: Int
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            if activeCount > 0 {
                Text("\(activeCount)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
        }
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
