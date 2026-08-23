import Foundation

public struct PowerAssertionConfiguration: Codable, Equatable, Sendable {
    public var preventSystemSleep: Bool
    public var preventDisplaySleep: Bool

    public init(preventSystemSleep: Bool = true, preventDisplaySleep: Bool = true) {
        self.preventSystemSleep = preventSystemSleep
        self.preventDisplaySleep = preventDisplaySleep
    }
}

public struct PowerAssertionSnapshot: Equatable, Sendable {
    public var protectionRequested: Bool
    public var systemSleepPrevented: Bool
    public var displaySleepPrevented: Bool

    public init(
        protectionRequested: Bool = false,
        systemSleepPrevented: Bool = false,
        displaySleepPrevented: Bool = false
    ) {
        self.protectionRequested = protectionRequested
        self.systemSleepPrevented = systemSleepPrevented
        self.displaySleepPrevented = displaySleepPrevented
    }

    public var anyAssertionHeld: Bool {
        systemSleepPrevented || displaySleepPrevented
    }
}

public protocol PowerAssertionConfiguring: PowerAssertionControlling {
    func setConfiguration(_ configuration: PowerAssertionConfiguration) async throws
    func assertionSnapshot() async -> PowerAssertionSnapshot
}
