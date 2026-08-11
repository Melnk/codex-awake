import Foundation

enum CodexChatRole: String, Sendable {
    case user
    case assistant
    case system
}

struct CodexChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: CodexChatRole
    var text: String
    let itemId: String?
    var phase: String?
    var isStreaming: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: CodexChatRole,
        text: String,
        itemId: String? = nil,
        phase: String? = nil,
        isStreaming: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.itemId = itemId
        self.phase = phase
        self.isStreaming = isStreaming
        self.createdAt = createdAt
    }
}

enum CodexApprovalKind: String, Sendable {
    case command = "Command"
    case fileChange = "File change"
}

struct CodexApprovalRequest: Identifiable, Equatable, Sendable {
    let id: Int
    let kind: CodexApprovalKind
    let title: String
    let detail: String
    let threadId: String?
    let turnId: String?
}

enum CodexApprovalDecision: String, Sendable {
    case accept
    case acceptForSession
    case decline
    case cancel
}
