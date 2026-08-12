import Foundation

public enum CodexTaskSource: String, Codable, Sendable {
    case managed
    case desktop
}

public enum CodexTaskStatus: String, Codable, Sendable, CaseIterable {
    case waiting
    case thinking
    case runningTool
    case waitingForApproval
    case completed
    case error

    public var isActive: Bool {
        switch self {
        case .waiting, .thinking, .runningTool, .waitingForApproval:
            true
        case .completed, .error:
            false
        }
    }
}

public struct CodexTaskRecord: Identifiable, Equatable, Sendable {
    public let threadId: String
    public let source: CodexTaskSource
    public var projectName: String
    public var workspacePath: String?
    public var startedAt: Date
    public var updatedAt: Date
    public var status: CodexTaskStatus

    public init(
        threadId: String,
        source: CodexTaskSource,
        projectName: String,
        workspacePath: String? = nil,
        startedAt: Date,
        updatedAt: Date,
        status: CodexTaskStatus
    ) {
        self.threadId = threadId
        self.source = source
        self.projectName = projectName
        self.workspacePath = workspacePath
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.status = status
    }

    public var id: String { "\(source.rawValue):\(threadId)" }
}

public struct CodexTaskSnapshot: Equatable, Sendable {
    public let active: [CodexTaskRecord]
    public let recent: [CodexTaskRecord]

    public init(active: [CodexTaskRecord] = [], recent: [CodexTaskRecord] = []) {
        self.active = active
        self.recent = recent
    }

    public var activeCount: Int { active.count }
    public var all: [CodexTaskRecord] { active + recent }
}

public struct CodexThreadSummary: Equatable, Sendable {
    public let id: String
    public let workspacePath: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let status: ThreadRuntimeStatus

    public init(
        id: String,
        workspacePath: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        status: ThreadRuntimeStatus
    ) {
        self.id = id
        self.workspacePath = workspacePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
    }
}

public enum CodexTaskItemKind: String, Equatable, Sendable {
    case agentMessage
    case commandExecution
    case fileChange
    case mcpToolCall
    case dynamicToolCall
    case collabToolCall
    case collabAgentToolCall
    case subAgentActivity
    case webSearch
    case imageView
    case imageGeneration
    case unknown

    public init(wireValue: String) {
        self = Self(rawValue: wireValue) ?? .unknown
    }

    public var isToolActivity: Bool {
        switch self {
        case .commandExecution, .fileChange, .mcpToolCall, .dynamicToolCall,
            .collabToolCall, .collabAgentToolCall, .subAgentActivity, .webSearch,
            .imageView, .imageGeneration:
            true
        case .agentMessage, .unknown:
            false
        }
    }
}
