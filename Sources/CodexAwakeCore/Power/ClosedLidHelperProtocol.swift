import Foundation

public enum ClosedLidHelperConstants {
    public static let label = "com.melnikoleg.CodexAwake.ClosedLidService"
    public static let machServiceName = label
    public static let bundledPlistName = "\(label).plist"
    public static let legacyLabel = "com.melnikoleg.CodexAwake.ClosedLidHelper"
    public static let legacyMachServiceName = legacyLabel
    public static let legacyInstalledExecutablePath = "/Library/PrivilegedHelperTools/\(legacyLabel)"
    public static let legacyInstalledPlistPath = "/Library/LaunchDaemons/\(legacyLabel).plist"
    public static let leaseDuration: TimeInterval = 120
    public static let renewalInterval: Duration = .seconds(30)
}

@objc public protocol ClosedLidHelperXPCProtocol {
    func status(withReply reply: @escaping (Bool, TimeInterval, String?) -> Void)
    func acquireLease(
        token: String,
        duration: TimeInterval,
        withReply reply: @escaping (Bool, TimeInterval, String?) -> Void
    )
    func renewLease(
        token: String,
        duration: TimeInterval,
        withReply reply: @escaping (Bool, TimeInterval, String?) -> Void
    )
    func releaseLease(token: String, withReply reply: @escaping (Bool, TimeInterval, String?) -> Void)
}

public struct ClosedLidHelperStatus: Equatable, Sendable {
    public var disablesSleep: Bool
    public var leaseExpiresAt: Date?
    public var error: String?

    public init(disablesSleep: Bool, leaseExpiresAt: Date? = nil, error: String? = nil) {
        self.disablesSleep = disablesSleep
        self.leaseExpiresAt = leaseExpiresAt
        self.error = error
    }
}

public protocol ClosedLidHelperCommunicating: Sendable {
    func status() async throws -> ClosedLidHelperStatus
    func acquire(token: String, duration: TimeInterval) async throws -> ClosedLidHelperStatus
    func renew(token: String, duration: TimeInterval) async throws -> ClosedLidHelperStatus
    func release(token: String) async throws -> ClosedLidHelperStatus
}
