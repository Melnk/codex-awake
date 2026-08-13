import Foundation

public enum AppServerWireMessage: Equatable, Sendable {
    case response(id: Int, result: JSONValue)
    case error(id: Int, code: Int, message: String)
    case notification(method: String, params: JSONValue?)
    case serverRequest(id: Int, method: String, params: JSONValue?)
}

public enum AppServerMessageCodec {
    public static func decode(_ text: String) throws -> AppServerWireMessage {
        guard let data = text.data(using: .utf8),
            let root = try? JSONDecoder().decode(JSONValue.self, from: data),
            let object = root.objectValue
        else {
            throw CodexAwakeError.malformedMessage
        }

        let id = object["id"].flatMap(integer(from:))
        if let method = object["method"]?.stringValue {
            if let id {
                return .serverRequest(id: id, method: method, params: object["params"])
            }
            return .notification(method: method, params: object["params"])
        }

        guard let id else { throw CodexAwakeError.malformedMessage }
        if let error = object["error"]?.objectValue {
            let code = error["code"].flatMap(integer(from:)) ?? -1
            let message = error["message"]?.stringValue ?? "Unknown App Server error"
            return .error(id: id, code: code, message: message)
        }
        if let result = object["result"] {
            return .response(id: id, result: result)
        }
        throw CodexAwakeError.malformedMessage
    }

    public static func request(id: Int, method: String, params: JSONValue = .object([:])) throws -> String {
        try encode(
            .object([
                "id": .number(Double(id)),
                "method": .string(method),
                "params": params,
            ]))
    }

    public static func notification(method: String, params: JSONValue = .object([:])) throws -> String {
        try encode(
            .object([
                "method": .string(method),
                "params": params,
            ]))
    }

    public static func methodNotFound(id: Int) throws -> String {
        try encode(
            .object([
                "id": .number(Double(id)),
                "error": .object([
                    "code": .number(-32601),
                    "message": .string("Method not supported by observer client"),
                ]),
            ]))
    }

    public static func response(id: Int, result: JSONValue) throws -> String {
        try encode(
            .object([
                "id": .number(Double(id)),
                "result": result,
            ]))
    }

    public static func event(method: String, params: JSONValue?) -> AppServerEvent {
        let threadId = params?["threadId"]?.stringValue
        let turnId = params?["turn"]?["id"]?.stringValue ?? params?["turnId"]?.stringValue

        switch method {
        case "thread/started":
            guard let id = params?["thread"]?["id"]?.stringValue ?? threadId else {
                return .unknown(method: method)
            }
            return .threadStarted(
                threadId: id,
                workspacePath: params?["thread"]?["cwd"]?.stringValue
            )

        case "turn/started":
            guard let threadId, let turnId else { return .unknown(method: method) }
            return .turnStarted(.init(threadId: threadId, turnId: turnId))

        case "turn/completed":
            guard let threadId, let turnId else { return .unknown(method: method) }
            let status = params?["turn"]?["status"]?.stringValue ?? params?["status"]?.stringValue
            return .turnCompleted(.init(threadId: threadId, turnId: turnId), status: status)

        case "thread/status/changed":
            guard let threadId else { return .unknown(method: method) }
            return .threadStatusChanged(threadId: threadId, status: .parse(params?["status"]))

        case "thread/closed":
            guard let threadId else { return .unknown(method: method) }
            return .threadClosed(threadId: threadId)

        case "item/agentMessage/delta":
            guard let threadId,
                let turnId = params?["turnId"]?.stringValue,
                let itemId = params?["itemId"]?.stringValue,
                let delta = params?["delta"]?.stringValue
            else {
                return .unknown(method: method)
            }
            return .agentMessageDelta(
                threadId: threadId,
                turnId: turnId,
                itemId: itemId,
                delta: delta
            )

        case "item/started":
            guard let threadId,
                let item = params?["item"],
                let itemId = item["id"]?.stringValue,
                let rawKind = item["type"]?.stringValue
            else {
                return .ignored(method: method)
            }
            return .itemStarted(
                threadId: threadId,
                itemId: itemId,
                kind: .init(wireValue: rawKind),
                activity: toolActivity(from: item, turnId: turnId, completed: false)
            )

        case "item/completed":
            guard let threadId, let item = params?["item"],
                let itemId = item["id"]?.stringValue,
                let rawKind = item["type"]?.stringValue
            else { return .ignored(method: method) }

            if rawKind == "agentMessage",
                let turnId = params?["turnId"]?.stringValue,
                let text = item["text"]?.stringValue
            {
                return .agentMessageCompleted(
                    threadId: threadId,
                    turnId: turnId,
                    itemId: itemId,
                    text: text,
                    phase: item["phase"]?.stringValue
                )
            }
            return .itemCompleted(
                threadId: threadId,
                itemId: itemId,
                kind: .init(wireValue: rawKind),
                activity: toolActivity(from: item, turnId: turnId, completed: true)
            )

        case "error":
            let detail =
                params?["error"]?["message"]?.stringValue
                ?? params?["message"]?.stringValue
                ?? "Codex reported an unknown runtime error."
            let kind = errorKind(params?["error"]?["codexErrorInfo"])
            let message = [kind, detail].compactMap { $0 }.joined(separator: ": ")
            return .runtimeError(threadId: threadId, message: String(message.prefix(500)))

        default:
            return .ignored(method: method)
        }
    }

    private static func encode(_ value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodexAwakeError.malformedMessage
        }
        return text
    }

    private static func integer(from value: JSONValue) -> Int? {
        guard case .number(let number) = value, number.rounded() == number else { return nil }
        return Int(number)
    }

    private static func toolActivity(
        from item: JSONValue,
        turnId: String?,
        completed: Bool
    ) -> CodexToolActivity? {
        guard let id = item["id"]?.stringValue, let type = item["type"]?.stringValue else {
            return nil
        }

        let status = toolStatus(item["status"]?.stringValue, completed: completed)
        switch type {
        case "commandExecution":
            return .init(
                id: id,
                turnId: turnId,
                kind: .command,
                title: "Command",
                status: status
            )
        case "fileChange":
            let paths = item["changes"]?.arrayValue?.compactMap { $0["path"]?.stringValue } ?? []
            return .init(
                id: id,
                turnId: turnId,
                kind: .fileChange,
                title: "File changes",
                changedFiles: Array(paths.prefix(100)),
                status: status
            )
        case "mcpToolCall":
            let server = item["server"]?.stringValue
            let tool = item["tool"]?.stringValue
            return .init(
                id: id,
                turnId: turnId,
                kind: .mcp,
                title: [server, tool].compactMap { $0 }.joined(separator: " · "),
                status: status
            )
        case "dynamicToolCall":
            return .init(
                id: id,
                turnId: turnId,
                kind: .mcp,
                title: item["tool"]?.stringValue ?? "Tool",
                status: status
            )
        case "webSearch":
            return .init(
                id: id,
                turnId: turnId,
                kind: .webSearch,
                title: "Web search",
                status: status
            )
        case "imageView", "imageGeneration":
            return .init(
                id: id,
                turnId: turnId,
                kind: .image,
                title: type == "imageView" ? "View image" : "Generate image",
                detail: bounded(item["path"]?.stringValue ?? item["savedPath"]?.stringValue),
                status: status
            )
        case "collabAgentToolCall", "subAgentActivity":
            return .init(
                id: id,
                turnId: turnId,
                kind: .collaboration,
                title: item["tool"]?.stringValue ?? "Collaboration",
                status: status
            )
        default:
            return nil
        }
    }

    private static func toolStatus(_ rawValue: String?, completed: Bool) -> CodexToolStatus {
        switch rawValue {
        case "failed": .failed
        case "declined": .declined
        case "completed": .completed
        default: completed ? .completed : .running
        }
    }

    private static func bounded(_ value: String?) -> String? {
        value.map { String($0.prefix(600)) }
    }

    private static func errorKind(_ value: JSONValue?) -> String? {
        if let rawValue = value?.stringValue { return rawValue }
        return value?.objectValue?.keys.sorted().first
    }

}
