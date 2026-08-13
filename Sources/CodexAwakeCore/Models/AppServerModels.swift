import Foundation

public enum AppServerState: String, Sendable, Codable, CaseIterable {
    case stopped
    case starting
    case running
    case reconnecting
    case stopping
    case failed
}

public enum ActivityCertainty: String, Sendable, Codable {
    case known
    case unknownReconnecting
}

public struct ThreadRuntimeStatus: Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case active
        case idle
        case notLoaded
        case systemError
        case unknown
    }

    public let kind: Kind
    public let activeFlags: Set<String>

    public init(kind: Kind, activeFlags: Set<String> = []) {
        self.kind = kind
        self.activeFlags = activeFlags
    }

    public var isActive: Bool { kind == .active }

    public static func parse(_ value: JSONValue?) -> ThreadRuntimeStatus {
        guard let object = value?.objectValue else { return .init(kind: .unknown) }
        let rawType = object["type"]?.stringValue ?? "unknown"
        let flags = Set(object["activeFlags"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        return .init(kind: Kind(rawValue: rawType) ?? .unknown, activeFlags: flags)
    }
}

public struct TurnKey: Hashable, Sendable, Codable {
    public let threadId: String
    public let turnId: String

    public init(threadId: String, turnId: String) {
        self.threadId = threadId
        self.turnId = turnId
    }
}

public struct ActivitySnapshot: Equatable, Sendable {
    public let activeThreadIds: Set<String>
    public let activeTurnKeys: Set<TurnKey>
    public let loadedThreadCount: Int
    public let certainty: ActivityCertainty

    public init(
        activeThreadIds: Set<String> = [],
        activeTurnKeys: Set<TurnKey> = [],
        loadedThreadCount: Int = 0,
        certainty: ActivityCertainty = .known
    ) {
        self.activeThreadIds = activeThreadIds
        self.activeTurnKeys = activeTurnKeys
        self.loadedThreadCount = loadedThreadCount
        self.certainty = certainty
    }

    public var activeCount: Int { activeThreadIds.count }
}

public enum AppServerEvent: Equatable, Sendable {
    case threadStarted(threadId: String, workspacePath: String?)
    case turnStarted(TurnKey)
    case turnCompleted(TurnKey, status: String?)
    case threadStatusChanged(threadId: String, status: ThreadRuntimeStatus)
    case threadClosed(threadId: String)
    case itemStarted(
        threadId: String,
        itemId: String,
        kind: CodexTaskItemKind,
        activity: CodexToolActivity?
    )
    case itemCompleted(
        threadId: String,
        itemId: String,
        kind: CodexTaskItemKind,
        activity: CodexToolActivity?
    )
    case agentMessageDelta(threadId: String, turnId: String, itemId: String, delta: String)
    case agentMessageCompleted(threadId: String, turnId: String, itemId: String, text: String, phase: String?)
    case runtimeError(threadId: String?, message: String)
    case ignored(method: String)
    case unknown(method: String)
}

public struct AppServerServerRequest: Equatable, Sendable {
    public let id: Int
    public let method: String
    public let params: JSONValue?

    public init(id: Int, method: String, params: JSONValue?) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public enum CodexAwakeError: LocalizedError, Equatable, Sendable {
    case codexNotFound
    case codexNotExecutable(String)
    case incompatibleCodex(String)
    case socketPathTooLong
    case socketOwnedByAnotherProcess
    case invalidSocket(String)
    case serverStartFailed(String)
    case connectionFailed(String)
    case timeout(String)
    case malformedMessage
    case remoteError(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .codexNotFound: return "Codex CLI was not found. Choose an executable Codex binary in Diagnostics."
        case .codexNotExecutable(let path): return "The selected Codex binary is not executable: \(path)"
        case .incompatibleCodex(let detail):
            return "This Codex CLI does not expose the required App Server features: \(detail)"
        case .socketPathTooLong: return "The local Unix socket path exceeds the macOS limit."
        case .socketOwnedByAnotherProcess: return "The runtime socket is in use by a process CodexAwake does not own."
        case .invalidSocket(let detail): return "Unsafe stale socket: \(detail)"
        case .serverStartFailed(let detail): return "Codex App Server could not start: \(detail)"
        case .connectionFailed(let detail): return "Could not connect to the local Codex App Server: \(detail)"
        case .timeout(let method): return "App Server request timed out: \(method)"
        case .malformedMessage: return "The App Server sent malformed JSON."
        case .remoteError(let code, let message): return "App Server error \(code): \(message)"
        }
    }
}
