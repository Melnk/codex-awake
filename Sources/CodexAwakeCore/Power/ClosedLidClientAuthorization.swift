import Foundation

public enum ClosedLidClientAuthorizationError: LocalizedError, Equatable {
    case invalidArguments
    case invalidCodeHash
    case invalidTeamIdentifier

    public var errorDescription: String? {
        switch self {
        case .invalidArguments: "Missing or invalid authorized client identity"
        case .invalidCodeHash: "Invalid authorized client CDHash"
        case .invalidTeamIdentifier: "Invalid authorized client Team ID"
        }
    }
}

public enum ClosedLidClientAuthorization {
    public static func codeSigningRequirement(arguments: [String]) throws -> String {
        guard arguments.count == 3 else {
            throw ClosedLidClientAuthorizationError.invalidArguments
        }
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
}
