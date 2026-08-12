import CodexAwakeCore
import Foundation
import XCTest

final class CodexTaskRegistryTests: XCTestCase {
    func testManagedTaskMovesThroughThinkingToolsApprovalAndCompletion() async {
        let registry = CodexTaskRegistry()
        let start = Date(timeIntervalSince1970: 100)
        let key = TurnKey(threadId: "thread-a", turnId: "turn-a")

        _ = await registry.apply(.turnStarted(key), now: start)
        var snapshot = await registry.apply(
            .itemStarted(threadId: "thread-a", itemId: "item-a", kind: .commandExecution),
            now: start.addingTimeInterval(2)
        )
        XCTAssertEqual(snapshot.active.first?.status, .runningTool)

        snapshot = await registry.markWaitingForApproval(
            threadId: "thread-a",
            now: start.addingTimeInterval(3)
        )
        XCTAssertEqual(snapshot.active.first?.status, .waitingForApproval)

        snapshot = await registry.apply(
            .turnCompleted(key, status: "completed"),
            now: start.addingTimeInterval(8)
        )
        XCTAssertTrue(snapshot.active.isEmpty)
        XCTAssertEqual(snapshot.recent.first?.status, .completed)
    }

    func testThreadSummaryUsesProjectMetadataAndRuntimeStatus() async {
        let registry = CodexTaskRegistry()
        let created = Date(timeIntervalSince1970: 200)
        let snapshot = await registry.reconcileManaged([
            CodexThreadSummary(
                id: "thread-a",
                workspacePath: "/Users/test/CodexAwake",
                createdAt: created,
                updatedAt: created.addingTimeInterval(5),
                status: .init(kind: .active, activeFlags: ["waitingOnApproval"])
            )
        ])

        XCTAssertEqual(snapshot.active.first?.projectName, "CodexAwake")
        XCTAssertEqual(snapshot.active.first?.workspacePath, "/Users/test/CodexAwake")
        XCTAssertEqual(snapshot.active.first?.status, .waitingForApproval)
        XCTAssertEqual(snapshot.active.first?.startedAt, created)
    }

    func testWaitingOnUserInputMapsToWaiting() async {
        let registry = CodexTaskRegistry()
        let snapshot = await registry.reconcileManaged([
            CodexThreadSummary(
                id: "thread-input",
                workspacePath: "/Users/test/CodexAwake",
                status: .init(kind: .active, activeFlags: ["waitingOnUserInput"])
            )
        ])

        XCTAssertEqual(snapshot.active.first?.status, .waiting)
    }

    func testDesktopTaskRetainsMetadataInRecentHistory() async {
        let registry = CodexTaskRegistry()
        let start = Date(timeIntervalSince1970: 300)
        let session = CodexDesktopSessionState(
            id: "desktop-a",
            modifiedAt: start.addingTimeInterval(10),
            workspacePath: "/Users/test/DesktopProject",
            startedAt: start
        )

        var snapshot = await registry.reconcileDesktop([session], now: start.addingTimeInterval(10))
        XCTAssertEqual(snapshot.active.first?.projectName, "DesktopProject")

        snapshot = await registry.reconcileDesktop([], now: start.addingTimeInterval(20))
        XCTAssertEqual(snapshot.recent.first?.status, .completed)
        XCTAssertEqual(snapshot.recent.first?.startedAt, start)
    }
}
