import Foundation
import Security
import ServiceManagement

public enum ClosedLidHelperServiceState: String, Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

public enum ClosedLidHelperServiceError: LocalizedError, Sendable {
    case missingFromApplicationBundle
    case signedApplicationRequired

    public var errorDescription: String? {
        switch self {
        case .missingFromApplicationBundle:
            "The Closed-Lid service is missing from this application build. Reinstall CodexAwake and try again."
        case .signedApplicationRequired:
            "Closed-Lid service registration requires an Apple Developer signed build. Touch ID cannot authorize an ad-hoc application as a root daemon."
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
        guard registrationIssue == nil else { return .unavailable }
        return state(
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

    public static var legacyInstallationIsCompatible: Bool {
        guard
            FileManager.default.isExecutableFile(
                atPath: ClosedLidHelperConstants.legacyInstalledExecutablePath
            ),
            let plist = NSDictionary(
                contentsOfFile: ClosedLidHelperConstants.legacyInstalledPlistPath
            ) as? [String: Any],
            let arguments = plist["ProgramArguments"] as? [String]
        else { return false }

        if let index = arguments.firstIndex(of: "--client-cdhash"),
            arguments.indices.contains(index + 1),
            let codeHash = applicationCodeHash
        {
            return arguments[index + 1].caseInsensitiveCompare(codeHash) == .orderedSame
        }
        if let index = arguments.firstIndex(of: "--client-team-id"),
            arguments.indices.contains(index + 1),
            let teamIdentifier = applicationTeamIdentifier
        {
            return arguments[index + 1] == teamIdentifier
        }
        return false
    }

    public var registrationIssue: ClosedLidHelperServiceError? {
        Self.registrationIssue
    }

    @discardableResult
    public func register(replacingExisting: Bool = false) async throws -> ClosedLidHelperServiceState {
        if let issue = registrationIssue { throw issue }
        switch state {
        case .enabled where replacingExisting:
            // Ad-hoc development builds receive a new launch constraint after
            // every signature change. Refresh the BTM record so launchd does
            // not keep rejecting the updated bundled daemon with EX_CONFIG.
            try await Self.service.unregister()
            for _ in 0..<20 where Self.state != .notRegistered {
                try await Task.sleep(for: .milliseconds(100))
            }
            return try await registerAfterBackgroundTaskManagerSettles()
        case .enabled, .requiresApproval:
            return state
        case .notRegistered:
            return try await registerAfterBackgroundTaskManagerSettles()
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

    private func registerAfterBackgroundTaskManagerSettles() async throws
        -> ClosedLidHelperServiceState
    {
        var latestError: Error?
        for attempt in 0..<4 {
            let latestState = state
            if latestState == .enabled || latestState == .requiresApproval {
                return latestState
            }
            do {
                try Self.service.register()
                return state
            } catch {
                latestError = error
                guard attempt < 3 else { throw error }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        throw latestError ?? ClosedLidHelperServiceError.missingFromApplicationBundle
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

    private static var registrationIssue: ClosedLidHelperServiceError? {
        guard bundledServiceIsPresent else { return .missingFromApplicationBundle }
        guard applicationTeamIdentifier != nil else { return .signedApplicationRequired }
        return nil
    }

    private static var applicationTeamIdentifier: String? {
        guard
            let value = applicationSigningInformation?[kSecCodeInfoTeamIdentifier as String] as? String,
            !value.isEmpty
        else { return nil }
        return value
    }

    private static var applicationCodeHash: String? {
        guard
            let data = applicationSigningInformation?[kSecCodeInfoUnique as String] as? Data,
            !data.isEmpty
        else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    private static var applicationSigningInformation: [String: Any]? {
        var staticCode: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode
        else { return nil }

        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &information
            ) == errSecSuccess,
            let values = information as? [String: Any]
        else { return nil }
        return values
    }
}
