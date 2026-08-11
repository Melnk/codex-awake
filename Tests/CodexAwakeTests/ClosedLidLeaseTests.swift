import CodexAwakeCore
import Foundation
import XCTest

final class ClosedLidLeaseTests: XCTestCase {
    func testActiveProtectionAcquiresAndReleaseRestoresLease() async throws {
        let helper = MockClosedLidHelper()
        let manager = ClosedLidLeaseManager(helper: helper, token: "test-token")

        try await manager.setRequested(true, protectionIsActive: true)
        var snapshot = await manager.snapshot()
        XCTAssertTrue(snapshot.requested)
        XCTAssertTrue(snapshot.helperReachable)
        XCTAssertTrue(snapshot.leaseActive)
        let acquireCount = await helper.acquireCount
        XCTAssertEqual(acquireCount, 1)

        await manager.setProtectionActive(false)
        snapshot = await manager.snapshot()
        XCTAssertFalse(snapshot.leaseActive)
        let releaseCount = await helper.releaseCount
        XCTAssertEqual(releaseCount, 1)
    }

    func testDisabledClosedLidDoesNotContactHelper() async throws {
        let helper = MockClosedLidHelper()
        let manager = ClosedLidLeaseManager(helper: helper, token: "test-token")

        await manager.setProtectionActive(true)

        let acquireCount = await helper.acquireCount
        let snapshot = await manager.snapshot()
        XCTAssertEqual(acquireCount, 0)
        XCTAssertFalse(snapshot.leaseActive)
    }

    func testHelperFailureDoesNotLoseIdleAssertion() async throws {
        let idle = MockPowerAssertionController()
        let helper = MockClosedLidHelper(failure: TestClosedLidError.unavailable)
        let lease = ClosedLidLeaseManager(helper: helper, token: "test-token")
        let protection = PowerProtectionManager(
            idle: idle,
            closedLid: lease,
            closedLidRequested: true
        )

        try await protection.acquire()

        let idleHeld = await idle.assertionIsHeld()
        let snapshot = await protection.closedLidSnapshot()
        XCTAssertTrue(idleHeld)
        XCTAssertFalse(snapshot.leaseActive)
        XCTAssertNotNil(snapshot.lastError)
    }

    func testCommandUsesSudoWithSafelyQuotedPath() {
        let command = ClosedLidHelperCommandBuilder.commandContents(
            scriptPath: "/Applications/Codex Awake's.app/install.sh",
            title: "Install Closed-Lid"
        )

        XCTAssertTrue(command.contains("/usr/bin/sudo '/Applications/Codex Awake'\\''s.app/install.sh'"))
        XCTAssertFalse(command.contains("sudo sh -c"))
    }
}

private enum TestClosedLidError: Error {
    case unavailable
}

private actor MockClosedLidHelper: ClosedLidHelperCommunicating {
    private(set) var acquireCount = 0
    private(set) var renewCount = 0
    private(set) var releaseCount = 0
    private let failure: Error?

    init(failure: Error? = nil) {
        self.failure = failure
    }

    func status() throws -> ClosedLidHelperStatus {
        if let failure { throw failure }
        return .init(disablesSleep: acquireCount > releaseCount)
    }

    func acquire(token: String, duration: TimeInterval) throws -> ClosedLidHelperStatus {
        acquireCount += 1
        if let failure { throw failure }
        return .init(disablesSleep: true, leaseExpiresAt: Date().addingTimeInterval(duration))
    }

    func renew(token: String, duration: TimeInterval) throws -> ClosedLidHelperStatus {
        renewCount += 1
        if let failure { throw failure }
        return .init(disablesSleep: true, leaseExpiresAt: Date().addingTimeInterval(duration))
    }

    func release(token: String) throws -> ClosedLidHelperStatus {
        releaseCount += 1
        if let failure { throw failure }
        return .init(disablesSleep: false)
    }
}
