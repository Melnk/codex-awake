import Foundation
import OSLog

public actor AppServerClient {
    public typealias TransportFactory = @Sendable (String) -> any LocalWebSocketTransport
    public typealias EventHandler = @Sendable (AppServerEvent) async -> Void
    public typealias ServerRequestHandler = @Sendable (AppServerServerRequest) async -> JSONValue?
    public typealias DisconnectHandler = @Sendable (String) async -> Void

    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<JSONValue, Error>
    }

    private let endpoint: String
    private let socketPath: String
    private let timeout: Duration
    private let transportFactory: TransportFactory
    private let eventHandler: EventHandler
    private let serverRequestHandler: ServerRequestHandler
    private let disconnectHandler: DisconnectHandler
    private let logger = Logger(subsystem: "com.melnikoleg.CodexAwake", category: "AppServerClient")

    private var transport: (any LocalWebSocketTransport)?
    private var receiveTask: Task<Void, Never>?
    private var nextRequestID = 1
    private var pending: [Int: PendingRequest] = [:]
    private(set) public var isConnected = false

    public init(
        endpoint: String,
        socketPath: String,
        timeout: Duration = .seconds(10),
        transportFactory: @escaping TransportFactory = { UnixWebSocketTransport(socketPath: $0) },
        eventHandler: @escaping EventHandler,
        serverRequestHandler: @escaping ServerRequestHandler = { _ in nil },
        disconnectHandler: @escaping DisconnectHandler
    ) {
        self.endpoint = endpoint
        self.socketPath = socketPath
        self.timeout = timeout
        self.transportFactory = transportFactory
        self.eventHandler = eventHandler
        self.serverRequestHandler = serverRequestHandler
        self.disconnectHandler = disconnectHandler
    }

    public func connect() async throws {
        guard !isConnected else { return }
        let newTransport = transportFactory(socketPath)
        try await Task.detached { try newTransport.connect() }.value
        transport = newTransport
        isConnected = true
        receiveTask = Task { [weak self] in await self?.receiveLoop(using: newTransport) }

        do {
            _ = try await request(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("codex_awake"),
                        "title": .string("CodexAwake"),
                        "version": .string(AppBuildInfo.marketingVersion),
                    ])
                ])
            )
            try await send(text: AppServerMessageCodec.notification(method: "initialized"))
            logger.notice(
                "Initialized local App Server observer connection at \(self.endpoint, privacy: .public)")
        } catch {
            await disconnect(notify: false)
            throw error
        }
    }

    public func disconnect(notify: Bool = false) async {
        receiveTask?.cancel()
        receiveTask = nil
        transport?.close()
        transport = nil
        isConnected = false
        failPending(with: CodexAwakeError.connectionFailed("Disconnected"))
        if notify { await disconnectHandler("Disconnected") }
    }

    public func reconcileStatuses() async throws -> (
        loaded: Set<String>,
        statuses: [String: ThreadRuntimeStatus],
        summaries: [CodexThreadSummary]
    ) {
        let loadedResult = try await request(method: "thread/loaded/list")
        let ids = Set(loadedResult["data"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        var statuses: [String: ThreadRuntimeStatus] = [:]
        var summaries: [CodexThreadSummary] = []
        for id in ids {
            let result = try await request(
                method: "thread/read",
                params: .object(["threadId": .string(id), "includeTurns": .bool(false)])
            )
            statuses[id] = .parse(result["thread"]?["status"])
            if let thread = result["thread"], let summary = Self.threadSummary(from: thread) {
                summaries.append(summary)
            }
        }
        return (ids, statuses, summaries)
    }

    public func listModels() async throws -> [CodexModelOption] {
        let result = try await request(
            method: "model/list",
            params: .object([
                "limit": .number(100),
                "includeHidden": .bool(false),
            ])
        )
        return result["data"]?.arrayValue?.compactMap(Self.modelOption) ?? []
    }

    public func startThread(cwd: String) async throws -> String {
        try await startThread(
            settings: .init(workspacePath: cwd)
        )
    }

    public func startThread(settings: CodexChatRequestSettings) async throws -> String {
        var params: [String: JSONValue] = [
            "cwd": .string(settings.workspacePath),
            "approvalPolicy": .string("on-request"),
            "sandbox": .string(settings.permissionMode.sandboxMode),
            "serviceName": .string("codex_awake"),
        ]
        if let modelID = settings.modelID { params["model"] = .string(modelID) }
        let result = try await request(
            method: "thread/start",
            params: .object(params)
        )
        guard let threadId = result["thread"]?["id"]?.stringValue else {
            throw CodexAwakeError.malformedMessage
        }
        return threadId
    }

    public func resumeThread(threadId: String, settings: CodexChatRequestSettings) async throws -> String {
        var params: [String: JSONValue] = [
            "threadId": .string(threadId),
            "cwd": .string(settings.workspacePath),
            "approvalPolicy": .string("on-request"),
            "sandbox": .string(settings.permissionMode.sandboxMode),
        ]
        if let modelID = settings.modelID { params["model"] = .string(modelID) }
        let result = try await request(method: "thread/resume", params: .object(params))
        guard let resumedThreadId = result["thread"]?["id"]?.stringValue else {
            throw CodexAwakeError.malformedMessage
        }
        return resumedThreadId
    }

    public func startTurn(threadId: String, text: String, cwd: String) async throws -> String {
        try await startTurn(
            threadId: threadId,
            messageID: UUID(),
            text: text,
            settings: .init(workspacePath: cwd)
        )
    }

    public func startTurn(
        threadId: String,
        messageID: UUID,
        text: String,
        settings: CodexChatRequestSettings
    ) async throws -> String {
        var params: [String: JSONValue] = [
            "threadId": .string(threadId),
            "clientUserMessageId": .string(messageID.uuidString),
            "input": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(text),
                ])
            ]),
            "cwd": .string(settings.workspacePath),
            "approvalPolicy": .string("on-request"),
            "sandboxPolicy": settings.permissionMode.sandboxPolicy(
                workspacePath: settings.workspacePath
            ),
        ]
        if let modelID = settings.modelID { params["model"] = .string(modelID) }
        if let effort = settings.reasoningEffort { params["effort"] = .string(effort) }
        let result = try await request(
            method: "turn/start",
            params: .object(params)
        )
        guard let turnId = result["turn"]?["id"]?.stringValue else {
            throw CodexAwakeError.malformedMessage
        }
        return turnId
    }

    public func interruptTurn(threadId: String, turnId: String) async throws {
        _ = try await request(
            method: "turn/interrupt",
            params: .object([
                "threadId": .string(threadId),
                "turnId": .string(turnId),
            ])
        )
    }

    public func request(method: String, params: JSONValue = .object([:])) async throws -> JSONValue {
        guard isConnected else { throw CodexAwakeError.connectionFailed("Not connected") }
        let id = nextRequestID
        nextRequestID += 1
        let text = try AppServerMessageCodec.request(id: id, method: method, params: params)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = PendingRequest(method: method, continuation: continuation)
            Task { [weak self] in
                do {
                    try await Task.sleep(for: self?.timeout ?? .seconds(10))
                    await self?.timeOutRequest(id: id)
                } catch {}
            }
            Task { [weak self] in
                do {
                    try await self?.send(text: text)
                } catch {
                    await self?.failRequest(id: id, error: error)
                }
            }
        }
    }

    private func receiveLoop(using transport: any LocalWebSocketTransport) async {
        do {
            while !Task.isCancelled {
                let text = try await Task.detached { try transport.receive() }.value
                guard let text else { break }
                do {
                    try await handle(AppServerMessageCodec.decode(text))
                } catch CodexAwakeError.malformedMessage {
                    logger.error("Ignored malformed JSON from the local App Server")
                    await eventHandler(.unknown(method: "malformed"))
                }
            }
        } catch {
            if !Task.isCancelled {
                logger.error(
                    "App Server connection ended: \(SafeDisplay.sanitizedError(error), privacy: .public)")
            }
        }

        if self.transport != nil {
            self.transport = nil
            isConnected = false
            failPending(with: CodexAwakeError.connectionFailed("Connection closed"))
            await disconnectHandler("Connection closed")
        }
    }

    private func handle(_ message: AppServerWireMessage) async throws {
        switch message {
        case .response(let id, let result):
            pending.removeValue(forKey: id)?.continuation.resume(returning: result)
        case .error(let id, let code, let message):
            pending.removeValue(forKey: id)?.continuation.resume(
                throwing: CodexAwakeError.remoteError(code: code, message: message))
        case .notification(let method, let params):
            await eventHandler(AppServerMessageCodec.event(method: method, params: params))
        case .serverRequest(let id, let method, let params):
            let request = AppServerServerRequest(id: id, method: method, params: params)
            if let result = await serverRequestHandler(request) {
                try await send(text: AppServerMessageCodec.response(id: id, result: result))
            } else {
                try await send(text: AppServerMessageCodec.methodNotFound(id: id))
            }
        }
    }

    private func send(text: String) async throws {
        guard let transport else { throw CodexAwakeError.connectionFailed("Not connected") }
        try await Task.detached { try transport.send(text: text) }.value
    }

    private func timeOutRequest(id: Int) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.continuation.resume(throwing: CodexAwakeError.timeout(request.method))
    }

    private func failRequest(id: Int, error: Error) {
        pending.removeValue(forKey: id)?.continuation.resume(throwing: error)
    }

    private func failPending(with error: Error) {
        let values = pending.values
        pending.removeAll()
        for request in values { request.continuation.resume(throwing: error) }
    }

    private static func threadSummary(from value: JSONValue) -> CodexThreadSummary? {
        guard let id = value["id"]?.stringValue else { return nil }
        return CodexThreadSummary(
            id: id,
            workspacePath: value["cwd"]?.stringValue,
            createdAt: date(from: value["createdAt"]),
            updatedAt: date(from: value["updatedAt"]),
            status: .parse(value["status"])
        )
    }

    private static func modelOption(from value: JSONValue) -> CodexModelOption? {
        guard let id = value["id"]?.stringValue,
            let model = value["model"]?.stringValue,
            let displayName = value["displayName"]?.stringValue,
            let defaultEffort = value["defaultReasoningEffort"]?.stringValue
        else { return nil }

        let efforts =
            value["supportedReasoningEfforts"]?.arrayValue?.compactMap { option -> CodexReasoningOption? in
                guard let effort = option["reasoningEffort"]?.stringValue else { return nil }
                return .init(id: effort, description: option["description"]?.stringValue ?? "")
            } ?? []
        return .init(
            id: id,
            model: model,
            displayName: displayName,
            description: value["description"]?.stringValue ?? "",
            isDefault: value["isDefault"]?.boolValue ?? false,
            defaultReasoningEffort: defaultEffort,
            reasoningOptions: efforts
        )
    }

    private static func date(from value: JSONValue?) -> Date? {
        switch value {
        case .number(let raw):
            let seconds = raw > 10_000_000_000 ? raw / 1_000 : raw
            return Date(timeIntervalSince1970: seconds)
        case .string(let raw):
            return ISO8601DateFormatter().date(from: raw)
        default:
            return nil
        }
    }
}
