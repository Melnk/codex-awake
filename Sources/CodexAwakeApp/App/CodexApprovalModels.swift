import CodexAwakeCore
import Foundation

enum CodexApprovalKind: String, Sendable {
    case command
    case fileChange
    case permissions
}

struct CodexApprovalRequest: Identifiable, Equatable, Sendable {
    let id: Int
    let kind: CodexApprovalKind
    let title: String
    let detail: String
    let threadId: String?
    let turnId: String?
    let requestedPermissions: JSONValue?
}

enum CodexApprovalDecision: String, Sendable {
    case accept
    case acceptForSession
    case decline
    case cancel
}
