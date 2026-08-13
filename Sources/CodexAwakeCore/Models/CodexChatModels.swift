import Foundation

public enum CodexChatRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public enum CodexMessageDelivery: String, Codable, Sendable {
    case queued
    case sending
    case sent
    case failed
}

public enum CodexPermissionMode: String, Codable, CaseIterable, Sendable {
    case readOnly
    case workspaceWrite
    case fullAccess

    public var sandboxMode: String {
        switch self {
        case .readOnly: "read-only"
        case .workspaceWrite: "workspace-write"
        case .fullAccess: "danger-full-access"
        }
    }

    public func sandboxPolicy(workspacePath: String) -> JSONValue {
        switch self {
        case .readOnly:
            .object([
                "type": .string("readOnly"),
                "networkAccess": .bool(false),
            ])
        case .workspaceWrite:
            .object([
                "type": .string("workspaceWrite"),
                "writableRoots": .array([.string(workspacePath)]),
                "networkAccess": .bool(true),
            ])
        case .fullAccess:
            .object(["type": .string("dangerFullAccess")])
        }
    }
}

public struct CodexChatRequestSettings: Codable, Equatable, Sendable {
    public var workspacePath: String
    public var modelID: String?
    public var reasoningEffort: String?
    public var permissionMode: CodexPermissionMode

    public init(
        workspacePath: String,
        modelID: String? = nil,
        reasoningEffort: String? = nil,
        permissionMode: CodexPermissionMode = .workspaceWrite
    ) {
        self.workspacePath = workspacePath
        self.modelID = modelID
        self.reasoningEffort = reasoningEffort
        self.permissionMode = permissionMode
    }
}

public struct CodexChatMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let role: CodexChatRole
    public var text: String
    public var itemId: String?
    public var phase: String?
    public var isStreaming: Bool
    public var delivery: CodexMessageDelivery?
    public var failureReason: String?
    public var requestSettings: CodexChatRequestSettings?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: CodexChatRole,
        text: String,
        itemId: String? = nil,
        phase: String? = nil,
        isStreaming: Bool = false,
        delivery: CodexMessageDelivery? = nil,
        failureReason: String? = nil,
        requestSettings: CodexChatRequestSettings? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.itemId = itemId
        self.phase = phase
        self.isStreaming = isStreaming
        self.delivery = delivery
        self.failureReason = failureReason
        self.requestSettings = requestSettings
        self.createdAt = createdAt
    }
}

public enum CodexToolKind: String, Codable, Sendable {
    case command
    case fileChange
    case mcp
    case webSearch
    case image
    case collaboration
    case other
}

public enum CodexToolStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case declined
}

public struct CodexToolActivity: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let turnId: String?
    public let kind: CodexToolKind
    public var title: String
    public var detail: String?
    public var changedFiles: [String]
    public var status: CodexToolStatus
    public let startedAt: Date
    public var completedAt: Date?

    public init(
        id: String,
        turnId: String?,
        kind: CodexToolKind,
        title: String,
        detail: String? = nil,
        changedFiles: [String] = [],
        status: CodexToolStatus = .running,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.turnId = turnId
        self.kind = kind
        self.title = title
        self.detail = detail
        self.changedFiles = changedFiles
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public struct CodexConversation: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var threadId: String?
    public var title: String
    public var settings: CodexChatRequestSettings
    public var messages: [CodexChatMessage]
    public var tools: [CodexToolActivity]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        threadId: String? = nil,
        title: String,
        settings: CodexChatRequestSettings,
        messages: [CodexChatMessage] = [],
        tools: [CodexToolActivity] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.threadId = threadId
        self.title = title
        self.settings = settings
        self.messages = messages
        self.tools = tools
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CodexChatArchive: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var activeConversationID: UUID?
    public var conversations: [CodexConversation]

    public init(
        version: Int = Self.currentVersion,
        activeConversationID: UUID? = nil,
        conversations: [CodexConversation] = []
    ) {
        self.version = version
        self.activeConversationID = activeConversationID
        self.conversations = conversations
    }
}
