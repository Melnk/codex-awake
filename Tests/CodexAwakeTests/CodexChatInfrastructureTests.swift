import CodexAwakeCore
import Foundation
import XCTest

final class CodexChatInfrastructureTests: XCTestCase {
    func testАрхивЧатаСохраняетсяИВосстанавливается() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAwakeChatTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("chat-history.json")
        let sut = FileCodexChatRepository(fileURL: fileURL)
        let conversation = CodexConversation(
            threadId: "thread-restored",
            title: "Saved request",
            settings: .init(
                workspacePath: "/tmp/project",
                permissionMode: .fullAccess
            ),
            messages: [
                .init(
                    role: .user,
                    text: "Continue this work",
                    delivery: .sending,
                    requestSettings: .init(
                        workspacePath: "/tmp/project",
                        permissionMode: .fullAccess
                    )
                )
            ]
        )
        let archive = CodexChatArchive(
            activeConversationID: conversation.id,
            conversations: [conversation]
        )

        // Act
        try await sut.save(archive)
        let restored = try await sut.load()
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)

        // Assert
        XCTAssertEqual(restored.activeConversationID, conversation.id)
        XCTAssertEqual(restored.conversations.first?.threadId, "thread-restored")
        XCTAssertEqual(restored.conversations.first?.messages.first?.delivery, .queued)
        XCTAssertEqual(restored.conversations.first?.settings.permissionMode, .workspaceWrite)
        XCTAssertEqual(
            restored.conversations.first?.messages.first?.requestSettings?.permissionMode,
            .workspaceWrite
        )
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
    }

    func testСписокМоделейДекодируетсяИзРеальногоPayload() async throws {
        // Arrange
        let transport = ScriptedTransport()
        let client = makeClient(transport: transport)
        try await client.connect()

        // Act
        let models = try await client.listModels()

        // Assert
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].id, "gpt-test")
        XCTAssertEqual(models[0].defaultReasoningEffort, "medium")
        XCTAssertEqual(models[0].reasoningOptions.map(\.id), ["low", "medium"])
        XCTAssertTrue(transport.sent.contains { $0.contains("\"method\":\"model/list\"") })
        await client.disconnect()
    }

    func testПродолжениеЧатаИспользуетThreadResume() async throws {
        // Arrange
        let transport = ScriptedTransport()
        let client = makeClient(transport: transport)
        try await client.connect()
        let settings = CodexChatRequestSettings(
            workspacePath: "/tmp/project",
            modelID: "gpt-test",
            reasoningEffort: "high",
            permissionMode: .workspaceWrite
        )

        // Act
        let threadID = try await client.resumeThread(
            threadId: "cockpit-thread",
            settings: settings
        )

        // Assert
        XCTAssertEqual(threadID, "cockpit-thread")
        let request = transport.sent.first { $0.contains("\"method\":\"thread/resume\"") } ?? ""
        XCTAssertTrue(request.contains("\"threadId\":\"cockpit-thread\""))
        XCTAssertTrue(request.contains("\"sandbox\":\"workspace-write\""))
        XCTAssertTrue(request.contains("\"model\":\"gpt-test\""))
        await client.disconnect()
    }

    func testНастройкиХодаПередаютсяБезНеизвестныхВариантов() async throws {
        // Arrange
        let transport = ScriptedTransport()
        let client = makeClient(transport: transport)
        try await client.connect()
        let settings = CodexChatRequestSettings(
            workspacePath: "/tmp/project",
            modelID: "gpt-test",
            reasoningEffort: "high",
            permissionMode: .fullAccess
        )

        // Act
        _ = try await client.startTurn(
            threadId: "cockpit-thread",
            messageID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            text: "Inspect",
            settings: settings
        )

        // Assert
        let request = transport.sent.first { $0.contains("\"method\":\"turn/start\"") } ?? ""
        XCTAssertTrue(request.contains("\"type\":\"dangerFullAccess\""))
        XCTAssertTrue(request.contains("\"approvalPolicy\":\"on-request\""))
        XCTAssertTrue(request.contains("\"effort\":\"high\""))
        XCTAssertTrue(request.contains("11111111-1111-1111-1111-111111111111"))
        await client.disconnect()
    }

    func testИзменённыеФайлыДекодируютсяБезСодержимогоDiff() {
        // Arrange
        let params = JSONValue.object([
            "threadId": .string("thread-a"),
            "turnId": .string("turn-a"),
            "item": .object([
                "id": .string("change-a"),
                "type": .string("fileChange"),
                "status": .string("completed"),
                "changes": .array([
                    .object([
                        "path": .string("/tmp/project/Sources/App.swift"),
                        "kind": .object(["type": .string("update")]),
                        "diff": .string("private source diff"),
                    ])
                ]),
            ]),
        ])

        // Act
        let event = AppServerMessageCodec.event(method: "item/completed", params: params)

        // Assert
        guard case .itemCompleted(_, _, _, let activity?) = event else {
            return XCTFail("Expected file activity")
        }
        XCTAssertEqual(activity.changedFiles, ["/tmp/project/Sources/App.swift"])
        XCTAssertNil(activity.detail)
        XCTAssertEqual(activity.status, .completed)
    }

    func testСтруктурированныйКодОшибкиСохраняетсяДляПонятногоМаппинга() {
        // Arrange
        let params = JSONValue.object([
            "threadId": .string("thread-a"),
            "error": .object([
                "message": .string("request failed"),
                "codexErrorInfo": .string("usageLimitExceeded"),
            ]),
        ])

        // Act
        let event = AppServerMessageCodec.event(method: "error", params: params)

        // Assert
        XCTAssertEqual(
            event,
            .runtimeError(
                threadId: "thread-a",
                message: "usageLimitExceeded: request failed"
            )
        )
    }

    private func makeClient(transport: ScriptedTransport) -> AppServerClient {
        AppServerClient(
            endpoint: "unix:///tmp/fake.sock",
            socketPath: "/tmp/fake.sock",
            timeout: .seconds(1),
            transportFactory: { _ in transport },
            eventHandler: { _ in },
            disconnectHandler: { _ in }
        )
    }
}
