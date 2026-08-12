import CodexAwakeCore
import Foundation

actor MockPowerAssertionController: PowerAssertionConfiguring {
    private(set) var acquireCount = 0
    private(set) var releaseCount = 0
    private var held = false
    private var configuration = PowerAssertionConfiguration()

    func acquire() throws {
        guard !held else { return }
        held = true
        acquireCount += 1
    }

    func release() {
        guard held else { return }
        held = false
        releaseCount += 1
    }

    func assertionIsHeld() -> Bool { held }

    func setConfiguration(_ configuration: PowerAssertionConfiguration) {
        self.configuration = configuration
        if held, !configuration.preventSystemSleep, !configuration.preventDisplaySleep {
            held = false
            releaseCount += 1
        }
    }

    func assertionSnapshot() -> PowerAssertionSnapshot {
        PowerAssertionSnapshot(
            protectionRequested: held,
            systemSleepPrevented: held && configuration.preventSystemSleep,
            displaySleepPrevented: held && configuration.preventDisplaySleep
        )
    }
}

actor ManualSleeper: AsyncSleeping {
    private var waiters: [CheckedContinuation<Void, Error>] = []

    func sleep(for duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func fireAll() {
        let current = waiters
        waiters.removeAll()
        current.forEach { $0.resume() }
    }

    var waiterCount: Int { waiters.count }
}

struct MockAppServerClient: Sendable {
    var statuses: [String: ThreadRuntimeStatus] = [:]
    var malformedPayload = false
}

actor MockProcessSupervisor {
    private(set) var states: [AppServerState] = []
    func crash() { states += [.running, .reconnecting] }
    func restart() { states += [.starting, .running] }
}

struct MockBinaryLocator: CodexBinaryLocating {
    var result: Result<CodexBinaryInfo, Error>
    func locate() async throws -> CodexBinaryInfo { try result.get() }
}

final class ScriptedTransport: LocalWebSocketTransport, @unchecked Sendable {
    private let condition = NSCondition()
    private var messages: [String] = []
    private var closed = false
    private(set) var sent: [String] = []

    func connect() throws {}

    func send(text: String) throws {
        condition.lock()
        defer { condition.unlock() }
        sent.append(text)
        guard let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? Int,
            let method = object["method"] as? String
        else { return }

        let response: String?
        switch method {
        case "initialize":
            response = "{\"id\":\(id),\"result\":{}}"
        case "thread/start":
            response = "{\"id\":\(id),\"result\":{\"thread\":{\"id\":\"cockpit-thread\"}}}"
        case "turn/start":
            response = "{\"id\":\(id),\"result\":{\"turn\":{\"id\":\"cockpit-turn\",\"status\":\"inProgress\"}}}"
        case "thread/loaded/list":
            response = "{\"id\":\(id),\"result\":{\"data\":[\"thread-1\"]}}"
        case "thread/read":
            response =
                "{\"id\":\(id),\"result\":{\"thread\":{\"id\":\"thread-1\",\"name\":\"Private chat title\",\"cwd\":\"/tmp/project\",\"preview\":\"private prompt that must not be retained\",\"createdAt\":1786528800,\"updatedAt\":1786528860,\"status\":{\"type\":\"active\",\"activeFlags\":[\"waitingOnApproval\"]}}}}"
        default:
            response = "{\"id\":\(id),\"result\":{}}"
        }
        if let response { messages.append(response) }
        condition.broadcast()
    }

    func receive() throws -> String? {
        condition.lock()
        defer { condition.unlock() }
        while messages.isEmpty && !closed { condition.wait() }
        return messages.isEmpty ? nil : messages.removeFirst()
    }

    func close() {
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
    }

    func push(_ message: String) {
        condition.lock()
        messages.append(message)
        condition.broadcast()
        condition.unlock()
    }
}

actor EventCollector {
    private(set) var events: [AppServerEvent] = []
    private(set) var disconnects = 0
    func append(_ event: AppServerEvent) { events.append(event) }
    func disconnected() { disconnects += 1 }
}
