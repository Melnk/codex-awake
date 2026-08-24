import CodexAwakeCore
import Foundation
import ServiceManagement
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

    func testHelperReconnectUsesBoundedBackoff() async {
        let helper = MockClosedLidHelper(failure: TestClosedLidError.unavailable)
        let clock = LockedTestClock(now: Date(timeIntervalSince1970: 1_000))
        let manager = ClosedLidLeaseManager(
            helper: helper,
            token: "test-token",
            now: { clock.value }
        )
        do {
            try await manager.setRequested(true, protectionIsActive: true)
        } catch {
            // The first failure schedules the automatic retry.
        }

        _ = await manager.refresh()
        let attemptsBeforeDeadline = await helper.acquireCount
        clock.advance(by: 2)
        _ = await manager.refresh()
        let attemptsAfterDeadline = await helper.acquireCount

        XCTAssertEqual(attemptsBeforeDeadline, 1)
        XCTAssertEqual(attemptsAfterDeadline, 2)
    }

    func testClosedLidClientAuthorizationAcceptsExactCodeHash() throws {
        let hash = String(repeating: "a", count: 40)

        let requirement = try ClosedLidClientAuthorization.codeSigningRequirement(
            arguments: ["helper", "--client-cdhash", hash]
        )

        XCTAssertEqual(requirement, "cdhash H\"\(hash)\"")
    }

    func testClosedLidClientAuthorizationUsesStableTeamRequirement() throws {
        let requirement = try ClosedLidClientAuthorization.codeSigningRequirement(
            arguments: ["helper", "--client-team-id", "AB12CD34EF"]
        )

        XCTAssertTrue(requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.contains(#"identifier "com.melnikoleg.CodexAwake""#))
        XCTAssertTrue(requirement.contains(#"certificate leaf[subject.OU] = "AB12CD34EF""#))
    }

    func testClosedLidClientAuthorizationRejectsUnsafeIdentity() {
        XCTAssertThrowsError(
            try ClosedLidClientAuthorization.codeSigningRequirement(
                arguments: ["helper", "--client-team-id", "bad requirement"]
            )
        )
    }

    func testBundledHelperResolvesContainingApplication() throws {
        let application = try ClosedLidClientAuthorization.containingApplicationURL(
            forBundledHelperAt:
                "/Applications/CodexAwake.app/Contents/Library/PrivilegedHelperTools/com.melnikoleg.CodexAwake.ClosedLidService"
        )

        XCTAssertEqual(application.path, "/Applications/CodexAwake.app")
    }

    func testBundledHelperRejectsUnexpectedLocation() {
        XCTAssertThrowsError(
            try ClosedLidClientAuthorization.containingApplicationURL(
                forBundledHelperAt: "/private/tmp/com.melnikoleg.CodexAwake.ClosedLidService"
            )
        )
    }

    func testBuiltBundledHelperDerivesAuthorizedAppRequirementWhenAvailable() throws {
        let helperPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(
                "dist/CodexAwake.app/Contents/Library/PrivilegedHelperTools/"
                    + ClosedLidHelperConstants.label
            ).path
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            throw XCTSkip("Release app bundle is built after the unit-test phase in a clean checkout")
        }

        let requirement = try ClosedLidClientAuthorization.codeSigningRequirement(
            arguments: [helperPath]
        )

        XCTAssertTrue(requirement.hasPrefix("cdhash H\"") || requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.contains("com.melnikoleg.CodexAwake") || requirement.contains("cdhash"))
    }

    func testClosedLidConnectionStateIsUserFacingAndDeterministic() {
        var snapshot = ClosedLidProtectionSnapshot()
        XCTAssertEqual(snapshot.connectionState, .setupRequired)

        snapshot.helperInstalled = true
        XCTAssertEqual(snapshot.connectionState, .reconnecting)

        snapshot.helperReachable = true
        XCTAssertEqual(snapshot.connectionState, .ready)

        snapshot.requested = true
        XCTAssertEqual(snapshot.connectionState, .armed)

        snapshot.leaseActive = true
        XCTAssertEqual(snapshot.connectionState, .active)
    }

    func testMissingRegistrationRecordIsSetupRequiredWhenBundleContainsService() {
        let state = ClosedLidHelperServiceManager.state(
            for: .notFound,
            bundledServiceIsPresent: true
        )

        XCTAssertEqual(state, .notRegistered)
    }

    func testMissingBundleFilesRemainUnavailable() {
        let state = ClosedLidHelperServiceManager.state(
            for: .notFound,
            bundledServiceIsPresent: false
        )

        XCTAssertEqual(state, .unavailable)
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

private final class LockedTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now: Date

    init(now: Date) {
        self.now = now
    }

    var value: Date {
        lock.withLock { now }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            now = now.addingTimeInterval(interval)
        }
    }
}
