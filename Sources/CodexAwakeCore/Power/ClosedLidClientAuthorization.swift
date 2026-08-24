import Foundation
import Security

public enum ClosedLidClientAuthorizationError: LocalizedError, Equatable {
    case invalidArguments
    case invalidCodeHash
    case invalidTeamIdentifier
    case invalidApplicationBundle
    case invalidApplicationSignature(OSStatus)
    case unexpectedApplicationIdentifier

    public var errorDescription: String? {
        switch self {
        case .invalidArguments: "Missing or invalid authorized client identity"
        case .invalidCodeHash: "Invalid authorized client CDHash"
        case .invalidTeamIdentifier: "Invalid authorized client Team ID"
        case .invalidApplicationBundle: "The Closed-Lid service is not running from a valid application bundle"
        case .invalidApplicationSignature(let status):
            "The CodexAwake application signature could not be verified (\(status))"
        case .unexpectedApplicationIdentifier: "The Closed-Lid service belongs to an unexpected application"
        }
    }
}

public enum ClosedLidClientAuthorization {
    public static func codeSigningRequirement(arguments: [String]) throws -> String {
        if arguments.count == 1 {
            return try codeSigningRequirement(forBundledHelperAt: arguments[0])
        }
        guard arguments.count == 3 else { throw ClosedLidClientAuthorizationError.invalidArguments }
        switch arguments[1] {
        case "--client-cdhash":
            let value = arguments[2].lowercased()
            guard value.count == 40, value.allSatisfy(\.isHexDigit) else {
                throw ClosedLidClientAuthorizationError.invalidCodeHash
            }
            return "cdhash H\"\(value)\""
        case "--client-team-id":
            let value = arguments[2]
            guard value.count == 10,
                value.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) })
            else {
                throw ClosedLidClientAuthorizationError.invalidTeamIdentifier
            }
            return
                #"anchor apple generic and identifier "com.melnikoleg.CodexAwake" and certificate leaf[subject.OU] = "\#(value)""#
        default:
            throw ClosedLidClientAuthorizationError.invalidArguments
        }
    }

    public static func containingApplicationURL(forBundledHelperAt executablePath: String) throws -> URL {
        let executableURL = URL(fileURLWithPath: executablePath).standardizedFileURL
        let privilegedHelperTools = executableURL.deletingLastPathComponent()
        let library = privilegedHelperTools.deletingLastPathComponent()
        let contents = library.deletingLastPathComponent()
        let application = contents.deletingLastPathComponent()

        guard privilegedHelperTools.lastPathComponent == "PrivilegedHelperTools",
            library.lastPathComponent == "Library",
            contents.lastPathComponent == "Contents",
            application.pathExtension == "app"
        else {
            throw ClosedLidClientAuthorizationError.invalidApplicationBundle
        }
        return application
    }

    private static func codeSigningRequirement(forBundledHelperAt executablePath: String) throws -> String {
        let applicationURL = try containingApplicationURL(forBundledHelperAt: executablePath)
        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(applicationURL as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            throw ClosedLidClientAuthorizationError.invalidApplicationSignature(status)
        }

        status = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSCheckAllArchitectures),
            nil
        )
        guard status == errSecSuccess else {
            throw ClosedLidClientAuthorizationError.invalidApplicationSignature(status)
        }

        var signingInformation: CFDictionary?
        status = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard status == errSecSuccess, let information = signingInformation as? [String: Any] else {
            throw ClosedLidClientAuthorizationError.invalidApplicationSignature(status)
        }
        guard information[kSecCodeInfoIdentifier as String] as? String == "com.melnikoleg.CodexAwake" else {
            throw ClosedLidClientAuthorizationError.unexpectedApplicationIdentifier
        }

        if let teamIdentifier = information[kSecCodeInfoTeamIdentifier as String] as? String,
            teamIdentifier.count == 10,
            teamIdentifier.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) })
        {
            return
                #"anchor apple generic and identifier "com.melnikoleg.CodexAwake" and certificate leaf[subject.OU] = "\#(teamIdentifier)""#
        }

        guard let codeHash = information[kSecCodeInfoUnique as String] as? Data,
            codeHash.count == 20
        else {
            throw ClosedLidClientAuthorizationError.invalidCodeHash
        }
        return "cdhash H\"\(codeHash.map { String(format: "%02x", $0) }.joined())\""
    }
}
