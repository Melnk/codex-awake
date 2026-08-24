import Foundation
import ServiceManagement

public enum ClosedLidHelperServiceState: String, Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

public enum ClosedLidHelperServiceError: LocalizedError, Sendable {
    case missingFromApplicationBundle

    public var errorDescription: String? {
        switch self {
        case .missingFromApplicationBundle:
            "The Closed-Lid service is missing from this application build. Reinstall CodexAwake and try again."
        }
    }
}

/// Owns registration of the bundled launch daemon. macOS performs the actual
/// privileged approval; CodexAwake never receives or stores an administrator password.
public struct ClosedLidHelperServiceManager: Sendable {
    public init() {}

    public var state: ClosedLidHelperServiceState {
        Self.state
    }

    public static var state: ClosedLidHelperServiceState {
        state(
            for: service.status,
            bundledServiceIsPresent: bundledServiceIsPresent
        )
    }

    public static func state(
        for systemStatus: SMAppService.Status,
        bundledServiceIsPresent: Bool
    ) -> ClosedLidHelperServiceState {
        switch systemStatus {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound:
            // Before the first daemon registration, BackgroundTaskManagement
            // can report "record not found" even though both bundle files are
            // present. Only treat it as a broken build after verifying disk.
            bundledServiceIsPresent ? .notRegistered : .unavailable
        @unknown default: .unavailable
        }
    }

    public static var isRegistered: Bool {
        state == .enabled || state == .requiresApproval
    }

    @discardableResult
    public func register() throws -> ClosedLidHelperServiceState {
        switch state {
        case .enabled, .requiresApproval:
            return state
        case .notRegistered:
            try Self.service.register()
            return state
        case .unavailable:
            throw ClosedLidHelperServiceError.missingFromApplicationBundle
        }
    }

    public func unregister() throws {
        guard state != .notRegistered, state != .unavailable else { return }
        try Self.service.unregister()
    }

    public func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static var service: SMAppService {
        .daemon(plistName: ClosedLidHelperConstants.bundledPlistName)
    }

    private static var bundledServiceIsPresent: Bool {
        let applicationURL = Bundle.main.bundleURL
        let plistURL =
            applicationURL
            .appendingPathComponent("Contents/Library/LaunchDaemons", isDirectory: true)
            .appendingPathComponent(ClosedLidHelperConstants.bundledPlistName)
        let executableURL =
            applicationURL
            .appendingPathComponent("Contents/Library/PrivilegedHelperTools", isDirectory: true)
            .appendingPathComponent(ClosedLidHelperConstants.label)
        return FileManager.default.fileExists(atPath: plistURL.path)
            && FileManager.default.isExecutableFile(atPath: executableURL.path)
    }
}
