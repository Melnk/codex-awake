import Foundation
import Security

/// Describes the legacy root helper installed by the explicit sudo script.
/// Compatibility is checked before any privileged XPC connection is opened.
public enum ClosedLidHelperInstallation {
    public static var isInstalled: Bool {
        FileManager.default.isExecutableFile(
            atPath: ClosedLidHelperConstants.installedExecutablePath
        )
            && FileManager.default.fileExists(
                atPath: ClosedLidHelperConstants.installedPlistPath
            )
    }

    public static var isCompatible: Bool {
        guard
            isInstalled,
            let plist = NSDictionary(
                contentsOfFile: ClosedLidHelperConstants.installedPlistPath
            ) as? [String: Any],
            let arguments = plist["ProgramArguments"] as? [String]
        else { return false }

        if let expected = argument(after: "--client-cdhash", in: arguments),
            let actual = applicationCodeHash
        {
            return expected.caseInsensitiveCompare(actual) == .orderedSame
        }
        if let expected = argument(after: "--client-team-id", in: arguments),
            let actual = applicationTeamIdentifier
        {
            return expected == actual
        }
        return false
    }

    private static func argument(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
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
