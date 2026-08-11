import Foundation

public actor PowerProtectionManager: PowerAssertionControlling {
    private let idle: any PowerAssertionControlling
    private let closedLid: ClosedLidLeaseManager
    private var held = false
    private var closedLidRequested: Bool

    public init(
        idle: any PowerAssertionControlling = PowerAssertionManager(),
        closedLid: ClosedLidLeaseManager = ClosedLidLeaseManager(),
        closedLidRequested: Bool = false
    ) {
        self.idle = idle
        self.closedLid = closedLid
        self.closedLidRequested = closedLidRequested
    }

    public func acquire() async throws {
        try await idle.acquire()
        held = true
        if closedLidRequested {
            try? await closedLid.setRequested(true, protectionIsActive: true)
        } else {
            await closedLid.setProtectionActive(true)
        }
    }

    public func release() async {
        held = false
        await closedLid.setProtectionActive(false)
        await idle.release()
    }

    public func assertionIsHeld() async -> Bool {
        await idle.assertionIsHeld()
    }

    public func setClosedLidRequested(_ enabled: Bool) async throws {
        closedLidRequested = enabled
        try await closedLid.setRequested(enabled, protectionIsActive: held)
    }

    public func refreshClosedLidStatus() async -> ClosedLidProtectionSnapshot {
        var snapshot = await closedLid.refresh()
        snapshot.requested = closedLidRequested
        return snapshot
    }

    public func closedLidSnapshot() async -> ClosedLidProtectionSnapshot {
        var snapshot = await closedLid.snapshot()
        snapshot.requested = closedLidRequested
        return snapshot
    }
}
