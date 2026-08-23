import Foundation

public struct SharedStatusSnapshot: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var protectionEnabled: Bool
    public var assertionHeld: Bool
    public var activeTaskCount: Int
    public var profile: ProtectionProfileID
    public var isOnExternalPower: Bool
    public var protectedSeconds: TimeInterval
    public var sleepPreventionSessions: Int

    public init(
        updatedAt: Date = Date(),
        protectionEnabled: Bool = true,
        assertionHeld: Bool = false,
        activeTaskCount: Int = 0,
        profile: ProtectionProfileID = .work,
        isOnExternalPower: Bool = false,
        protectedSeconds: TimeInterval = 0,
        sleepPreventionSessions: Int = 0
    ) {
        self.updatedAt = updatedAt
        self.protectionEnabled = protectionEnabled
        self.assertionHeld = assertionHeld
        self.activeTaskCount = max(0, activeTaskCount)
        self.profile = profile
        self.isOnExternalPower = isOnExternalPower
        self.protectedSeconds = max(0, protectedSeconds)
        self.sleepPreventionSessions = max(0, sleepPreventionSessions)
    }
}

public enum SharedStatusStorage {
    public static let appGroupIdentifier = "group.com.melnikoleg.CodexAwake"
    public static let defaultsKey = "SharedStatusSnapshot"

    public static func write(
        _ snapshot: SharedStatusSnapshot,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)
    ) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    public static func read(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)
    ) -> SharedStatusSnapshot? {
        guard
            let data = defaults?.data(forKey: defaultsKey),
            let value = try? JSONDecoder().decode(SharedStatusSnapshot.self, from: data)
        else { return nil }
        return value
    }
}
