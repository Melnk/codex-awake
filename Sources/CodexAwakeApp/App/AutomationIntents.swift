import AppIntents
import CodexAwakeCore
import Foundation

@MainActor
final class AutomationCommandCenter {
    static let shared = AutomationCommandCenter()
    weak var model: AppModel?

    private init() {}

    func toggleProtection() -> Bool? {
        guard let model else { return nil }
        model.setAutoKeepAwake(!model.autoKeepAwake)
        return model.autoKeepAwake
    }

    func applyProfile(_ id: ProtectionProfileID) -> Bool {
        guard let model else { return false }
        model.applyProtectionProfile(id)
        return true
    }

    func status() -> SharedStatusSnapshot? {
        guard let model else { return SharedStatusStorage.read() }
        return SharedStatusSnapshot(
            protectionEnabled: model.autoKeepAwake,
            assertionHeld: model.assertionHeld,
            activeTaskCount: model.totalActiveSessionCount,
            profile: model.selectedProtectionProfile,
            isOnExternalPower: model.isOnExternalPower,
            protectedSeconds: model.protectionStatistics.protectedSeconds,
            sleepPreventionSessions: model.protectionStatistics.sleepPreventionSessions
        )
    }
}

enum ShortcutProtectionProfile: String, AppEnum {
    case work
    case nightTask
    case closedLid
    case presentation

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Protection Profile")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .work: "Work",
        .nightTask: "Night Task",
        .closedLid: "Closed Lid",
        .presentation: "Presentation",
    ]

    var profileID: ProtectionProfileID {
        ProtectionProfileID(rawValue: rawValue) ?? .work
    }
}

struct ToggleCodexAwakeProtectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle CodexAwake Protection"
    static let description = IntentDescription("Turns CodexAwake automatic sleep protection on or off.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let enabled = AutomationCommandCenter.shared.toggleProtection() else {
            return .result(dialog: "Open CodexAwake and try again.")
        }
        return .result(dialog: enabled ? "CodexAwake protection is on." : "CodexAwake protection is off.")
    }
}

struct ApplyCodexAwakeProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply CodexAwake Profile"
    static let description = IntentDescription("Applies a saved CodexAwake automation profile.")
    static let openAppWhenRun = true

    @Parameter(title: "Profile")
    var profile: ShortcutProtectionProfile

    static var parameterSummary: some ParameterSummary {
        Summary("Apply \(\.$profile) in CodexAwake")
    }

    init() {}

    init(profile: ShortcutProtectionProfile) {
        self.profile = profile
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AutomationCommandCenter.shared.applyProfile(profile.profileID) else {
            return .result(dialog: "Open CodexAwake and try again.")
        }
        return .result(dialog: "The CodexAwake profile is active.")
    }
}

struct GetCodexAwakeStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get CodexAwake Status"
    static let description = IntentDescription("Reports privacy-safe protection and active-task state.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let status = AutomationCommandCenter.shared.status() else {
            return .result(dialog: "CodexAwake has not published a status yet.")
        }
        let state = status.assertionHeld ? "active" : "standby"
        return .result(
            dialog:
                "CodexAwake is \(state). Active tasks: \(status.activeTaskCount). Profile: \(status.profile.rawValue)."
        )
    }
}

struct CodexAwakeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleCodexAwakeProtectionIntent(),
            phrases: [
                "Toggle protection in \(.applicationName)",
                "Toggle \(.applicationName)",
            ],
            shortTitle: "Toggle Protection",
            systemImageName: "bolt.circle"
        )
        AppShortcut(
            intent: ApplyCodexAwakeProfileIntent(),
            phrases: [
                "Apply a profile in \(.applicationName)",
                "Change \(.applicationName) profile",
            ],
            shortTitle: "Apply Profile",
            systemImageName: "slider.horizontal.3"
        )
        AppShortcut(
            intent: GetCodexAwakeStatusIntent(),
            phrases: [
                "Get \(.applicationName) status",
                "Is \(.applicationName) active",
            ],
            shortTitle: "Get Status",
            systemImageName: "waveform.path.ecg"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .purple
}
