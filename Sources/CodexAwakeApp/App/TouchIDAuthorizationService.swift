import Foundation
import LocalAuthentication

enum TouchIDAuthorizationError: LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Touch ID confirmation was cancelled. The Closed-Lid service was not changed."
        case .failed(let message):
            "Touch ID confirmation failed: \(message)"
        }
    }
}

/// Touch ID confirms the user's intent. ServiceManagement remains responsible
/// for granting and revoking the daemon's privileged system registration.
@MainActor
final class TouchIDAuthorizationService {
    func authorizeIfAvailable(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var policyError: NSError?
        guard
            context.canEvaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                error: &policyError
            ), context.biometryType == .touchID
        else {
            return false
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch let error as LAError {
            switch error.code {
            case .appCancel, .systemCancel, .userCancel:
                throw TouchIDAuthorizationError.cancelled
            default:
                throw TouchIDAuthorizationError.failed(error.localizedDescription)
            }
        } catch {
            throw TouchIDAuthorizationError.failed(error.localizedDescription)
        }
    }
}
