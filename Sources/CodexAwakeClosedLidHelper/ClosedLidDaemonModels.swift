import Foundation

struct PersistedLeaseState: Codable {
    var originalSettings: [String: Int]
    var leases: [String: Date]
}

enum ClosedLidDaemonError: LocalizedError {
    case notRoot
    case invalidClientHash
    case invalidLease
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRoot: "Closed-Lid helper must run as root"
        case .invalidClientHash: "Missing or invalid authorized client CDHash"
        case .invalidLease: "Invalid Closed-Lid lease request"
        case .commandFailed(let message): message
        }
    }
}

struct LeaseRequestValidator {
    func validate(token: String, duration: TimeInterval? = nil) throws {
        guard !token.isEmpty, token.utf8.count <= 128 else {
            throw ClosedLidDaemonError.invalidLease
        }
        if let duration, !duration.isFinite || duration <= 0 {
            throw ClosedLidDaemonError.invalidLease
        }
    }
}
