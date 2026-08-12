@testable import CodexAwakeCore
import XCTest

final class ActivityAndPowerTests: XCTestCase {
    private func snapshot(_ ids: Set<String>, certainty: ActivityCertainty = .known) -> ActivitySnapshot {
        ActivitySnapshot(activeThreadIds: ids, certainty: certainty)
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(20))
    }

    func testProductionAssertionPreventsIdleDisplaySleep() {
        XCTAssertEqual(PowerAssertionManager.assertionTypeName, "PreventUserIdleDisplaySleep")
    }

    func testZeroActiveThreadsAssertionOff() async {
        let power = MockPowerAssertionController()
        let sleeper = ManualSleeper()
        let coordinator = AwakeCoordinator(power: power, sleeper: sleeper)
        await coordinator.update(snapshot([]))
        let held = await power.assertionIsHeld()
        XCTAssertFalse(held)
    }

    func testFirstActiveThreadAssertionOn() async {
        let power = MockPowerAssertionController()
        let coordinator = AwakeCoordinator(power: power)
        await coordinator.update(snapshot(["a"]))
        let held = await power.assertionIsHeld()
        let acquisitions = await power.acquireCount
        XCTAssertTrue(held)
        XCTAssertEqual(acquisitions, 1)
    }

    func testSecondActiveThreadDoesNotAcquireAgain() async {
        let power = MockPowerAssertionController()
        let coordinator = AwakeCoordinator(power: power)
        await coordinator.update(snapshot(["a"]))
        await coordinator.update(snapshot(["a", "b"]))
        let acquisitions = await power.acquireCount
        XCTAssertEqual(acquisitions, 1)
    }

    func testTenActiveThreadsStillOneAssertion() async {
        let power = MockPowerAssertionController()
        let coordinator = AwakeCoordinator(power: power)
        for count in 1...10 {
            await coordinator.update(snapshot(Set((1...count).map { "t\($0)" })))
        }
        let acquisitions = await power.acquireCount
        let held = await power.assertionIsHeld()
        XCTAssertEqual(acquisitions, 1)
        XCTAssertTrue(held)
    }

    func testNineOfTenCompleteAssertionRemains() async {
        let power = MockPowerAssertionController()
        let coordinator = AwakeCoordinator(power: power)
        await coordinator.update(snapshot(Set((1...10).map { "t\($0)" })))
        await coordinator.update(snapshot(["t10"]))
        let held = await power.assertionIsHeld()
        XCTAssertTrue(held)
    }

    func testLastCompletesAssertionReleasesAfterDebounce() async {
        let power = MockPowerAssertionController()
        let sleeper = ManualSleeper()
        let coordinator = AwakeCoordinator(power: power, sleeper: sleeper)
        await coordinator.update(snapshot(["a"]))
        await coordinator.update(snapshot([]))
        await settle()
        let heldBefore = await power.assertionIsHeld()
        XCTAssertTrue(heldBefore)
        await sleeper.fireAll()
        await settle()
        let heldAfter = await power.assertionIsHeld()
        XCTAssertFalse(heldAfter)
    }

    func testDuplicateActiveEventIsIdempotent() async {
        let tracker = ThreadActivityTracker()
        let event = AppServerEvent.threadStatusChanged(threadId: "a", status: .init(kind: .active))
        _ = await tracker.apply(event)
        let result = await tracker.apply(event)
        XCTAssertEqual(result.activeCount, 1)
    }

    func testStreamingChatEventDoesNotChangeActivityCertainty() async {
        let tracker = ThreadActivityTracker()
        _ = await tracker.apply(.threadStatusChanged(threadId: "a", status: .init(kind: .active)))
        let result = await tracker.apply(
            .agentMessageDelta(
                threadId: "a",
                turnId: "1",
                itemId: "message-1",
                delta: "Working"
            ))
        XCTAssertEqual(result.activeThreadIds, ["a"])
        XCTAssertEqual(result.certainty, .known)
    }

    func testDuplicateIdleAndCompletedAreSafe() async {
        let tracker = ThreadActivityTracker()
        let key = TurnKey(threadId: "a", turnId: "1")
        _ = await tracker.apply(.turnCompleted(key, status: "completed"))
        let result = await tracker.apply(.turnCompleted(key, status: "completed"))
        XCTAssertEqual(result.activeCount, 0)
    }

    func testOutOfOrderEventsConverge() async {
        let tracker = ThreadActivityTracker()
        let key = TurnKey(threadId: "a", turnId: "1")
        _ = await tracker.apply(.turnCompleted(key, status: "completed"))
        let result = await tracker.apply(.threadStatusChanged(threadId: "a", status: .init(kind: .active)))
        XCTAssertEqual(result.activeThreadIds, ["a"])
    }

    func testTurnCompletedStatusCompleted() async { await assertCompletion(status: "completed") }
    func testTurnCompletedStatusFailed() async { await assertCompletion(status: "failed") }
    func testTurnCompletedStatusInterrupted() async { await assertCompletion(status: "interrupted") }

    func testWaitingOnApprovalRemainsActive() async {
        let tracker = ThreadActivityTracker()
        let result = await tracker.apply(
            .threadStatusChanged(
                threadId: "a",
                status: .init(kind: .active, activeFlags: ["waitingOnApproval"])
            ))
        XCTAssertEqual(result.activeCount, 1)
    }

    func testSystemErrorBecomesInactive() async {
        let tracker = ThreadActivityTracker()
        _ = await tracker.apply(.threadStatusChanged(threadId: "a", status: .init(kind: .active)))
        let result = await tracker.apply(.threadStatusChanged(threadId: "a", status: .init(kind: .systemError)))
        XCTAssertEqual(result.activeCount, 0)
    }

    func testReconnectWithActiveThread() async {
        let tracker = ThreadActivityTracker()
        _ = await tracker.markConnectionUnknown()
        let result = await tracker.reconcile(loadedThreadIds: ["a"], statuses: ["a": .init(kind: .active)])
        XCTAssertEqual(result.activeThreadIds, ["a"])
        XCTAssertEqual(result.certainty, .known)
    }

    func testLaunchWithAlreadyActiveThread() async {
        let tracker = ThreadActivityTracker()
        let result = await tracker.reconcile(loadedThreadIds: ["a"], statuses: ["a": .init(kind: .active)])
        XCTAssertEqual(result.activeCount, 1)
    }

    func testMissedEventFixedByReconciliation() async {
        let tracker = ThreadActivityTracker()
        _ = await tracker.apply(.threadStatusChanged(threadId: "stale", status: .init(kind: .active)))
        let result = await tracker.reconcile(loadedThreadIds: ["real"], statuses: ["real": .init(kind: .idle)])
        XCTAssertEqual(result.activeCount, 0)
    }

    func testReconnectGracePeriodRetainsThenReleases() async {
        let power = MockPowerAssertionController()
        let sleeper = ManualSleeper()
        let coordinator = AwakeCoordinator(power: power, sleeper: sleeper)
        await coordinator.update(snapshot(["a"]))
        await coordinator.update(snapshot(["a"], certainty: .unknownReconnecting))
        let heldInitially = await power.assertionIsHeld()
        XCTAssertTrue(heldInitially)
        await coordinator.update(snapshot([], certainty: .unknownReconnecting))
        await settle()
        let heldDuringGrace = await power.assertionIsHeld()
        XCTAssertTrue(heldDuringGrace)
        await sleeper.fireAll()
        await settle()
        let heldAfterGrace = await power.assertionIsHeld()
        XCTAssertFalse(heldAfterGrace)
    }

    func testDoubleAcquirePrevented() async {
        let power = MockPowerAssertionController()
        try? await power.acquire()
        try? await power.acquire()
        let acquisitions = await power.acquireCount
        XCTAssertEqual(acquisitions, 1)
    }

    func testDoubleReleaseSafe() async {
        let power = MockPowerAssertionController()
        try? await power.acquire()
        await power.release()
        await power.release()
        let releases = await power.releaseCount
        XCTAssertEqual(releases, 1)
    }

    func testAutoKeepAwakeOff() async {
        let power = MockPowerAssertionController()
        let coordinator = AwakeCoordinator(power: power, autoKeepAwake: false)
        await coordinator.update(snapshot(["a"]))
        let held = await power.assertionIsHeld()
        XCTAssertFalse(held)
    }

    func testCodexDesktopPresenceAcquiresAssertionWithoutManagedTask() async {
        let power = MockPowerAssertionController()
        let coordinator = AwakeCoordinator(power: power)
        await coordinator.setCodexDesktopRunning(true)
        let held = await power.assertionIsHeld()
        XCTAssertTrue(held)
    }

    func testCodexDesktopExitReleasesAfterDebounce() async {
        let power = MockPowerAssertionController()
        let sleeper = ManualSleeper()
        let coordinator = AwakeCoordinator(power: power, sleeper: sleeper)
        await coordinator.setCodexDesktopRunning(true)
        await coordinator.setCodexDesktopRunning(false)
        await settle()
        let heldBeforeDebounce = await power.assertionIsHeld()
        XCTAssertTrue(heldBeforeDebounce)
        await sleeper.fireAll()
        await settle()
        let heldAfterDebounce = await power.assertionIsHeld()
        XCTAssertFalse(heldAfterDebounce)
    }

    func testCodexDesktopPresenceCanBeDisabled() async {
        let power = MockPowerAssertionController()
        let coordinator = AwakeCoordinator(power: power, keepAwakeForCodexDesktop: false)
        await coordinator.setCodexDesktopRunning(true)
        let held = await power.assertionIsHeld()
        XCTAssertFalse(held)
    }

    func testActiveDesktopSessionAcquiresWhenPresenceProtectionIsDisabled() async {
        let power = MockPowerAssertionController()
        let coordinator = AwakeCoordinator(power: power, keepAwakeForCodexDesktop: false)
        await coordinator.setCodexDesktopRunning(true)
        await coordinator.setCodexDesktopActiveCount(1)
        let held = await power.assertionIsHeld()
        XCTAssertTrue(held)
    }

    func testAutoKeepAwakeOffOverridesCodexDesktopPresence() async {
        let power = MockPowerAssertionController()
        let coordinator = AwakeCoordinator(power: power)
        await coordinator.setCodexDesktopRunning(true)
        await coordinator.setAutoKeepAwake(false)
        let held = await power.assertionIsHeld()
        XCTAssertFalse(held)
    }

    func testConfirmedServerStopKeepsAssertionForRunningCodexDesktop() async {
        let power = MockPowerAssertionController()
        let coordinator = AwakeCoordinator(power: power)
        await coordinator.setCodexDesktopRunning(true)
        await coordinator.serverConfirmedStopped()
        let held = await power.assertionIsHeld()
        XCTAssertTrue(held)
    }

    func testExitReleasesAssertion() async {
        let power = MockPowerAssertionController()
        let coordinator = AwakeCoordinator(power: power)
        await coordinator.update(snapshot(["a"]))
        await coordinator.shutdown()
        let held = await power.assertionIsHeld()
        XCTAssertFalse(held)
    }

    func testAtLeastTenConcurrentThreadsTracked() async {
        let tracker = ThreadActivityTracker()
        for number in 1...12 {
            _ = await tracker.apply(.threadStatusChanged(threadId: "t\(number)", status: .init(kind: .active)))
        }
        let result = await tracker.currentSnapshot()
        XCTAssertEqual(result.activeCount, 12)
    }

    private func assertCompletion(status: String) async {
        let tracker = ThreadActivityTracker()
        let key = TurnKey(threadId: "a", turnId: "1")
        _ = await tracker.apply(.turnStarted(key))
        let result = await tracker.apply(.turnCompleted(key, status: status))
        XCTAssertEqual(result.activeCount, 0)
        XCTAssertTrue(result.activeTurnKeys.isEmpty)
    }
}
