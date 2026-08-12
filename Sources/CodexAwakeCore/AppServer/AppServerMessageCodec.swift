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
                kind: .init(wireValue: rawKind)
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
                kind: .init(wireValue: rawKind)
            )

        case "error":
            let message =
                params?["error"]?["message"]?.stringValue
                ?? params?["message"]?.stringValue
                ?? "Codex reported an unknown runtime error."
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
}
