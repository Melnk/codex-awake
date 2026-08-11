import CodexAwakeCore
import XCTest

final class ProtocolAndLifecycleTests: XCTestCase {
    func testMalformedJSONDoesNotDecode() {
        XCTAssertThrowsError(try AppServerMessageCodec.decode("not-json"))
    }

    func testInitializeAndInitializedHandshake() async throws {
        let transport = ScriptedTransport()
        let collector = EventCollector()
        let client = makeClient(transport: transport, collector: collector)
        try await client.connect()
        try? await Task.sleep(for: .milliseconds(20))
        let sent = transport.sent.joined(separator: "\n")
        XCTAssertTrue(sent.contains("initialize"))
        XCTAssertTrue(sent.contains("initialized"))
        await client.disconnect()
    }

    func testRequestResponseMatchingAndReconciliation() async throws {
        let transport = ScriptedTransport()
        let collector = EventCollector()
        let client = makeClient(transport: transport, collector: collector)
        try await client.connect()
        let result = try await client.reconcileStatuses()
        XCTAssertEqual(result.loaded, ["thread-1"])
        XCTAssertEqual(result.statuses["thread-1"]?.kind, .active)
        XCTAssertEqual(result.statuses["thread-1"]?.activeFlags, ["waitingOnApproval"])
        await client.disconnect()
    }

    func testNotificationDelivery() async throws {
        let transport = ScriptedTransport()
        let collector = EventCollector()
        let client = makeClient(transport: transport, collector: collector)
        try await client.connect()
        transport.push("{\"method\":\"thread/status/changed\",\"params\":{\"threadId\":\"a\",\"status\":{\"type\":\"active\"}}}")
        try? await Task.sleep(for: .milliseconds(30))
        let eventCount = await collector.events.count
        XCTAssertEqual(eventCount, 1)
        await client.disconnect()
    }

    func testAgentMessageDeltaDecoding() throws {
        let message = try AppServerMessageCodec.decode("""
        {"method":"item/agentMessage/delta","params":{"threadId":"thread-a","turnId":"turn-a","itemId":"item-a","delta":"Hello"}}
        """)
        guard case .notification(let method, let params) = message else {
            return XCTFail("Expected notification")
        }
        XCTAssertEqual(
            AppServerMessageCodec.event(method: method, params: params),
            .agentMessageDelta(threadId: "thread-a", turnId: "turn-a", itemId: "item-a", delta: "Hello")
        )
    }

    func testCompletedAgentMessageIsAuthoritative() throws {
        let event = AppServerMessageCodec.event(
            method: "item/completed",
            params: .object([
                "threadId": .string("thread-a"),
                "turnId": .string("turn-a"),
                "item": .object([
                    "type": .string("agentMessage"),
                    "id": .string("item-a"),
                    "text": .string("Final answer"),
                    "phase": .string("final_answer")
                ])
            ])
        )
        XCTAssertEqual(
            event,
            .agentMessageCompleted(
                threadId: "thread-a",
                turnId: "turn-a",
                itemId: "item-a",
                text: "Final answer",
                phase: "final_answer"
            )
        )
    }

    func testUnrelatedNotificationsAreIgnoredWithoutProtocolFailure() {
        XCTAssertEqual(
            AppServerMessageCodec.event(method: "item/started", params: .object([:])),
            .ignored(method: "item/started")
        )
    }

    func testCockpitStartsThreadAndTurnWithWorkspacePolicy() async throws {
        let transport = ScriptedTransport()
        let client = makeClient(transport: transport, collector: EventCollector())
        try await client.connect()
        let threadID = try await client.startThread(cwd: "/tmp/project")
        let turnID = try await client.startTurn(threadId: threadID, text: "Inspect the project", cwd: "/tmp/project")

        XCTAssertEqual(threadID, "cockpit-thread")
        XCTAssertEqual(turnID, "cockpit-turn")
        let sent = transport.sent.joined(separator: "\n")
        XCTAssertTrue(sent.contains("\"method\":\"thread/start\""))
        XCTAssertTrue(sent.contains("\"approvalPolicy\":\"unlessTrusted\""))
        XCTAssertTrue(sent.contains("\"sandbox\":\"workspace-write\""))
        XCTAssertTrue(sent.contains("\"writableRoots\":[\"/tmp/project\"]"))
        XCTAssertTrue(sent.contains("Inspect the project"))
        await client.disconnect()
    }

    func testApprovalRequestReceivesDecisionResponse() async throws {
        let transport = ScriptedTransport()
        let collector = EventCollector()
        let client = AppServerClient(
            endpoint: "unix:///tmp/fake.sock",
            socketPath: "/tmp/fake.sock",
            timeout: .seconds(1),
            transportFactory: { _ in transport },
            eventHandler: { event in await collector.append(event) },
            serverRequestHandler: { request in
                request.method == "item/commandExecution/requestApproval" ? .string("accept") : nil
            },
            disconnectHandler: { _ in await collector.disconnected() }
        )
        try await client.connect()
        transport.push("""
        {"id":91,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread-a","turnId":"turn-a","itemId":"item-a","command":"swift test"}}
        """)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(transport.sent.contains(where: { $0.contains("\"id\":91") && $0.contains("\"result\":\"accept\"") }))
        await client.disconnect()
    }

    func testMalformedPayloadThenValidNotification() async throws {
        let transport = ScriptedTransport()
        let collector = EventCollector()
        let client = makeClient(transport: transport, collector: collector)
        try await client.connect()
        transport.push("{")
        transport.push("{\"method\":\"thread/closed\",\"params\":{\"threadId\":\"a\"}}")
        try? await Task.sleep(for: .milliseconds(40))
        let eventCount = await collector.events.count
        XCTAssertGreaterThanOrEqual(eventCount, 2)
        await client.disconnect()
    }

    func testDisconnectIsReported() async throws {
        let transport = ScriptedTransport()
        let collector = EventCollector()
        let client = makeClient(transport: transport, collector: collector)
        try await client.connect()
        transport.close()
        try? await Task.sleep(for: .milliseconds(30))
        let disconnects = await collector.disconnects
        XCTAssertEqual(disconnects, 1)
    }

    func testMultipleSimulatedClients() async throws {
        let firstTransport = ScriptedTransport()
        let secondTransport = ScriptedTransport()
        let first = makeClient(transport: firstTransport, collector: EventCollector())
        let second = makeClient(transport: secondTransport, collector: EventCollector())
        try await first.connect()
        try await second.connect()
        let firstConnected = await first.isConnected
        let secondConnected = await second.isConnected
        XCTAssertTrue(firstConnected)
        XCTAssertTrue(secondConnected)
        await first.disconnect()
        await second.disconnect()
    }

    func testAppServerCrashState() async {
        let supervisor = MockProcessSupervisor()
        await supervisor.crash()
        let states = await supervisor.states
        XCTAssertEqual(states, [.running, .reconnecting])
    }

    func testAppServerRestartState() async {
        let supervisor = MockProcessSupervisor()
        await supervisor.restart()
        let states = await supervisor.states
        XCTAssertEqual(states, [.starting, .running])
    }

    func testStaleSocketMayBeRemoved() {
        XCTAssertEqual(
            SocketPathManager.existingSocketDecision(isSocket: true, ownerMatches: true, acceptsConnection: false),
            .removeStale
        )
    }

    func testActiveOrForeignSocketIsNotRemoved() {
        XCTAssertEqual(
            SocketPathManager.existingSocketDecision(isSocket: true, ownerMatches: true, acceptsConnection: true),
            .refuseActive
        )
        XCTAssertEqual(
            SocketPathManager.existingSocketDecision(isSocket: true, ownerMatches: false, acceptsConnection: false),
            .refuseUnsafe
        )
    }

    func testIncompatibleCodexHelp() {
        XCTAssertFalse(CodexBinaryLocator.isCompatible(appServerHelp: "codex app-server"))
        XCTAssertTrue(CodexBinaryLocator.isCompatible(appServerHelp: "--listen unix://"))
        XCTAssertFalse(CodexBinaryLocator.isCompatible(mainHelp: "codex", appServerHelp: "--listen unix://"))
        XCTAssertTrue(CodexBinaryLocator.isCompatible(mainHelp: "--remote", appServerHelp: "--listen unix://"))
    }

    func testCodexBinaryAbsent() async {
        let locator = MockBinaryLocator(result: .failure(CodexAwakeError.codexNotFound))
        do {
            _ = try await locator.locate()
            XCTFail("Expected missing binary")
        } catch {
            XCTAssertEqual(error as? CodexAwakeError, .codexNotFound)
        }
    }

    func testBundledCodexCandidatesIncludeInstalledChatGPTRuntime() {
        let candidates = CodexBinaryLocator.bundledCodexCandidates(
            homeDirectory: URL(fileURLWithPath: "/Users/tester")
        )
        XCTAssertTrue(candidates.contains("/Applications/ChatGPT.app/Contents/Resources/codex"))
        XCTAssertTrue(candidates.contains("/Users/tester/Applications/ChatGPT.app/Contents/Resources/codex"))
    }

    func testCommandEscapesShellArguments() {
        let command = CodexCommandBuilder.command(binaryPath: "/tmp/codex tool", endpoint: "unix:///tmp/a'b.sock")
        XCTAssertEqual(command, "'/tmp/codex tool' --remote 'unix:///tmp/a'\\''b.sock'")
    }

    func testThreadStatusParsing() {
        let status = ThreadRuntimeStatus.parse(.object([
            "type": .string("active"),
            "activeFlags": .array([.string("waitingOnApproval")])
        ]))
        XCTAssertTrue(status.isActive)
        XCTAssertEqual(status.activeFlags, ["waitingOnApproval"])
    }

    private func makeClient(transport: ScriptedTransport, collector: EventCollector) -> AppServerClient {
        AppServerClient(
            endpoint: "unix:///tmp/fake.sock",
            socketPath: "/tmp/fake.sock",
            timeout: .seconds(1),
            transportFactory: { _ in transport },
            eventHandler: { event in await collector.append(event) },
            disconnectHandler: { _ in await collector.disconnected() }
        )
    }
}
