@testable import CodexAwakeApp
import CodexAwakeCore
import Foundation
import XCTest

@MainActor
final class CodexChatSessionTests: XCTestCase {
    func testВтороеСообщениеЖдётВОчередиИОтправляетсяПослеЗавершения() async throws {
        // Arrange
        let repository = InMemoryChatRepository()
        let client = RecordingChatClient()
        let sut = CodexChatSession(language: .english, repository: repository)
        await sut.restore(defaultWorkspacePath: "/tmp")
        sut.attach(client: client)
        let settings = CodexChatRequestSettings(workspacePath: "/tmp")

        // Act
        XCTAssertTrue(sut.enqueue("First", settings: settings, unavailableReason: nil))
        XCTAssertTrue(sut.enqueue("Second", settings: settings, unavailableReason: nil))
        try await waitUntil { await client.startedTurns.count == 1 }

        // Assert
        XCTAssertTrue(sut.isSending)
        XCTAssertEqual(sut.queuedCount, 1)
        let firstBatch = await client.listStartedTexts()
        XCTAssertEqual(firstBatch, ["First"])

        // Act
        sut.handle(.turnCompleted(.init(threadId: "thread-a", turnId: "turn-1"), status: "completed"))
        try await waitUntil { await client.startedTurns.count == 2 }

        // Assert
        let completedBatch = await client.listStartedTexts()
        XCTAssertEqual(completedBatch, ["First", "Second"])
        XCTAssertEqual(sut.queuedCount, 0)
    }

    func testОшибкаОтправкиПоказываетПричинуИОставляетПовтор() async throws {
        // Arrange
        let repository = InMemoryChatRepository()
        let client = RecordingChatClient(
            turnError: CodexAwakeError.remoteError(
                code: -32600,
                message: "Invalid request: unknown variant broken"
            )
        )
        let sut = CodexChatSession(language: .english, repository: repository)
        await sut.restore(defaultWorkspacePath: "/tmp")
        sut.attach(client: client)
        let settings = CodexChatRequestSettings(workspacePath: "/tmp")

        // Act
        XCTAssertTrue(sut.enqueue("Send me", settings: settings, unavailableReason: nil))
        try await waitUntil { sut.messages.first?.delivery == .failed }

        // Assert
        let message = try XCTUnwrap(sut.messages.first)
        XCTAssertEqual(message.delivery, .failed)
        XCTAssertNotNil(message.failureReason)
        XCTAssertFalse(message.failureReason?.contains("-32600") ?? true)
        XCTAssertTrue(message.failureReason?.contains("settings") ?? false)
    }

    func testНедоступныйCodexНеТеряетСообщение() async {
        // Arrange
        let repository = InMemoryChatRepository()
        let sut = CodexChatSession(language: .russian, repository: repository)
        await sut.restore(defaultWorkspacePath: "/tmp")
        let settings = CodexChatRequestSettings(workspacePath: "/tmp")

        // Act
        let accepted = sut.enqueue(
            "Сохрани запрос",
            settings: settings,
            unavailableReason: "Codex подключается."
        )

        // Assert
        XCTAssertTrue(accepted)
        XCTAssertEqual(sut.messages.first?.delivery, .failed)
        XCTAssertTrue(sut.messages.first?.failureReason?.contains("Codex подключается") ?? false)
    }

    func testПовторОтправляетРанееНеОтправленноеСообщение() async throws {
        // Arrange
        let repository = InMemoryChatRepository()
        let failingClient = RecordingChatClient(
            turnError: CodexAwakeError.connectionFailed("offline")
        )
        let sut = CodexChatSession(language: .english, repository: repository)
        await sut.restore(defaultWorkspacePath: "/tmp")
        sut.attach(client: failingClient)
        let settings = CodexChatRequestSettings(workspacePath: "/tmp")
        XCTAssertTrue(sut.enqueue("Retry me", settings: settings, unavailableReason: nil))
        try await waitUntil { sut.messages.first?.delivery == .failed }
        let messageID = try XCTUnwrap(sut.messages.first?.id)
        let workingClient = RecordingChatClient()
        sut.attach(client: workingClient)

        // Act
        sut.retry(messageID: messageID, unavailableReason: nil)
        try await waitUntil { await workingClient.startedTurns.count == 1 }

        // Assert
        let retriedTexts = await workingClient.listStartedTexts()
        XCTAssertEqual(retriedTexts, ["Retry me"])
        XCTAssertEqual(sut.messages.first?.delivery, .sent)
    }

    func testПодтверждениеКомандыОтвечаетПоСхемеAppServer() async throws {
        // Arrange
        let sut = CodexChatSession(
            language: .english,
            repository: InMemoryChatRepository()
        )
        await sut.restore(defaultWorkspacePath: "/tmp")
        sut.conversations[0].threadId = "thread-a"
        let request = AppServerServerRequest(
            id: 7,
            method: "item/commandExecution/requestApproval",
            params: .object([
                "threadId": .string("thread-a"),
                "turnId": .string("turn-a"),
                "command": .string("swift test"),
            ])
        )

        // Act
        let responseTask = Task { await sut.handleServerRequest(request) }
        try await waitUntil { sut.approvalRequests.count == 1 }
        sut.resolve(try XCTUnwrap(sut.approvalRequests.first), decision: .accept)
        let response = await responseTask.value

        // Assert
        XCTAssertEqual(response?["decision"]?.stringValue, "accept")
    }

    func testПодтверждениеРазрешенийНеРасширяетЗапрошенныйНабор() async throws {
        // Arrange
        let sut = CodexChatSession(
            language: .english,
            repository: InMemoryChatRepository()
        )
        await sut.restore(defaultWorkspacePath: "/tmp")
        sut.conversations[0].threadId = "thread-a"
        let requested = JSONValue.object([
            "network": .object(["enabled": .bool(true)])
        ])
        let request = AppServerServerRequest(
            id: 8,
            method: "item/permissions/requestApproval",
            params: .object([
                "threadId": .string("thread-a"),
                "turnId": .string("turn-a"),
                "permissions": requested,
            ])
        )

        // Act
        let responseTask = Task { await sut.handleServerRequest(request) }
        try await waitUntil { sut.approvalRequests.count == 1 }
        sut.resolve(try XCTUnwrap(sut.approvalRequests.first), decision: .acceptForSession)
        let response = await responseTask.value

        // Assert
        XCTAssertEqual(response?["permissions"], requested)
        XCTAssertEqual(response?["scope"]?.stringValue, "session")
    }

    func testТехническийЛимитПреобразуетсяВПонятнуюОшибку() {
        // Arrange
        let error = CodexAwakeError.remoteError(
            code: -1,
            message: "usageLimitExceeded: request failed"
        )

        // Act
        let failure = CodexChatFailurePresenter.present(error, language: .russian)

        // Assert
        XCTAssertEqual(failure.title, "Достигнут лимит Codex")
        XCTAssertFalse(failure.displayText.contains("usageLimitExceeded"))
        XCTAssertFalse(failure.displayText.contains("-1"))
    }

    func testОтложенноеСохранениеБерётПоследнееПотоковоеСостояниеОдинРаз() async throws {
        // Arrange
        let repository = InMemoryChatRepository()
        let sut = CodexChatSession(language: .english, repository: repository)
        await sut.restore(defaultWorkspacePath: "/tmp")
        sut.conversations[0].threadId = "thread-a"

        // Act
        sut.updateAgentMessage(threadId: "thread-a", itemId: "answer-a", delta: "Fast ")
        sut.updateAgentMessage(threadId: "thread-a", itemId: "answer-a", delta: "stream")
        sut.updateAgentMessage(threadId: "thread-a", itemId: "answer-a", delta: " output")
        try await Task.sleep(for: .milliseconds(260))

        // Assert
        let archive = await repository.archive
        let saveCount = await repository.saveCount
        XCTAssertEqual(archive.conversations.first?.messages.last?.text, "Fast stream output")
        XCTAssertEqual(saveCount, 1)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition was not met before timeout")
    }
}

private actor InMemoryChatRepository: CodexChatPersisting {
    var archive = CodexChatArchive()
    var saveCount = 0

    func load() -> CodexChatArchive { archive }
    func save(_ archive: CodexChatArchive) {
        self.archive = archive
        saveCount += 1
    }
}

private actor RecordingChatClient: CodexChatClient {
    struct StartedTurn: Sendable {
        let id: String
        let text: String
    }

    private let turnError: Error?
    private(set) var startedTurns: [StartedTurn] = []

    init(turnError: Error? = nil) {
        self.turnError = turnError
    }

    func listModels() -> [CodexModelOption] { [] }

    func startThread(settings: CodexChatRequestSettings) -> String { "thread-a" }

    func resumeThread(threadId: String, settings: CodexChatRequestSettings) -> String {
        threadId
    }

    func startTurn(
        threadId: String,
        messageID: UUID,
        text: String,
        settings: CodexChatRequestSettings
    ) throws -> String {
        if let turnError { throw turnError }
        let id = "turn-\(startedTurns.count + 1)"
        startedTurns.append(.init(id: id, text: text))
        return id
    }

    func interruptTurn(threadId: String, turnId: String) {}

    func listStartedTexts() -> [String] {
        startedTurns.map(\.text)
    }
}
