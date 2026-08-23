import Foundation

public protocol AppPreferencesStoring: Sendable {
    var autoKeepAwake: Bool { get }
    var preventSystemSleep: Bool { get }
    var preventDisplaySleep: Bool { get }
    var keepAwakeForCodexDesktop: Bool { get }
    var closedLidProtectionEnabled: Bool { get }
    var firstRunAcknowledged: Bool { get }
    var completedOnboardingVersion: Int { get }
    var interfaceTheme: String? { get }
    var appLanguage: String? { get }
    var compactMenuBarEnabled: Bool { get }
    var workspacePath: String? { get }
    var automationRules: ProtectionAutomationRules { get }
    var protectionProfileID: ProtectionProfileID { get }
    var automationSchemaVersion: Int { get }

    func setAutoKeepAwake(_ enabled: Bool)
    func setPreventSystemSleep(_ enabled: Bool)
    func setPreventDisplaySleep(_ enabled: Bool)
    func setKeepAwakeForCodexDesktop(_ enabled: Bool)
    func setClosedLidProtectionEnabled(_ enabled: Bool)
    func setFirstRunAcknowledged(_ acknowledged: Bool)
    func setCompletedOnboardingVersion(_ version: Int)
    func setInterfaceTheme(_ theme: String)
    func setAppLanguage(_ language: String)
    func setCompactMenuBarEnabled(_ enabled: Bool)
    func setWorkspacePath(_ path: String?)
    func setAutomationRules(_ rules: ProtectionAutomationRules)
    func setProtectionProfileID(_ id: ProtectionProfileID)
    func setAutomationSchemaVersion(_ version: Int)
}

public final class UserDefaultsAppPreferences: AppPreferencesStoring, @unchecked Sendable {
    private enum Key {
        static let autoKeepAwake = "AutoKeepAwake"
        static let preventSystemSleep = "PreventSystemSleep"
        static let preventDisplaySleep = "PreventDisplaySleep"
        static let keepAwakeForCodexDesktop = "KeepAwakeForCodexDesktop"
        static let closedLidProtectionEnabled = "ClosedLidProtectionEnabled"
        static let firstRunAcknowledged = "FirstRunAcknowledged"
        static let completedOnboardingVersion = "CompletedOnboardingVersion"
        static let interfaceTheme = "InterfaceTheme"
        static let appLanguage = "AppLanguage"
        static let compactMenuBarEnabled = "CompactMenuBarEnabled"
        static let workspacePath = "CodexWorkspacePath"
        static let automationRules = "ProtectionAutomationRules"
        static let protectionProfileID = "ProtectionProfileID"
        static let automationSchemaVersion = "AutomationSchemaVersion"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var autoKeepAwake: Bool {
        defaults.object(forKey: Key.autoKeepAwake) as? Bool ?? true
    }

    public var preventSystemSleep: Bool {
        defaults.object(forKey: Key.preventSystemSleep) as? Bool ?? true
    }

    public var preventDisplaySleep: Bool {
        defaults.object(forKey: Key.preventDisplaySleep) as? Bool ?? true
    }

    public var keepAwakeForCodexDesktop: Bool {
        defaults.object(forKey: Key.keepAwakeForCodexDesktop) as? Bool ?? true
    }

    public var closedLidProtectionEnabled: Bool {
        defaults.bool(forKey: Key.closedLidProtectionEnabled)
    }

    public var firstRunAcknowledged: Bool {
        defaults.bool(forKey: Key.firstRunAcknowledged)
    }

    public var completedOnboardingVersion: Int {
        defaults.integer(forKey: Key.completedOnboardingVersion)
    }

    public var interfaceTheme: String? {
        defaults.string(forKey: Key.interfaceTheme)
    }

    public var appLanguage: String? {
        defaults.string(forKey: Key.appLanguage)
    }

    public var compactMenuBarEnabled: Bool {
        defaults.object(forKey: Key.compactMenuBarEnabled) as? Bool ?? true
    }

    public var workspacePath: String? {
        defaults.string(forKey: Key.workspacePath)
    }

    public var automationRules: ProtectionAutomationRules {
        guard
            let data = defaults.data(forKey: Key.automationRules),
            let value = try? JSONDecoder().decode(ProtectionAutomationRules.self, from: data)
        else {
            return ProtectionAutomationRules(
                trigger: keepAwakeForCodexDesktop ? .codexRunning : .activeTasks,
                automaticallyStopsAfterTasks: !keepAwakeForCodexDesktop
            )
        }
        return value
    }

    public var protectionProfileID: ProtectionProfileID {
        defaults.string(forKey: Key.protectionProfileID)
            .flatMap(ProtectionProfileID.init(rawValue:))
            ?? (keepAwakeForCodexDesktop ? .presentation : .work)
    }

    public var automationSchemaVersion: Int {
        defaults.integer(forKey: Key.automationSchemaVersion)
    }

    public func setAutoKeepAwake(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.autoKeepAwake)
    }

    public func setPreventSystemSleep(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.preventSystemSleep)
    }

    public func setPreventDisplaySleep(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.preventDisplaySleep)
    }

    public func setKeepAwakeForCodexDesktop(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.keepAwakeForCodexDesktop)
    }

    public func setClosedLidProtectionEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.closedLidProtectionEnabled)
    }

    public func setFirstRunAcknowledged(_ acknowledged: Bool) {
        defaults.set(acknowledged, forKey: Key.firstRunAcknowledged)
    }

    public func setCompletedOnboardingVersion(_ version: Int) {
        defaults.set(max(0, version), forKey: Key.completedOnboardingVersion)
    }

    public func setInterfaceTheme(_ theme: String) {
        defaults.set(theme, forKey: Key.interfaceTheme)
    }

    public func setAppLanguage(_ language: String) {
        defaults.set(language, forKey: Key.appLanguage)
    }

    public func setCompactMenuBarEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.compactMenuBarEnabled)
    }

    public func setWorkspacePath(_ path: String?) {
        if let path {
            defaults.set(path, forKey: Key.workspacePath)
        } else {
            defaults.removeObject(forKey: Key.workspacePath)
        }
    }

    public func setAutomationRules(_ rules: ProtectionAutomationRules) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: Key.automationRules)
    }

    public func setProtectionProfileID(_ id: ProtectionProfileID) {
        defaults.set(id.rawValue, forKey: Key.protectionProfileID)
    }

    public func setAutomationSchemaVersion(_ version: Int) {
        defaults.set(max(0, version), forKey: Key.automationSchemaVersion)
    }
}
