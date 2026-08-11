import Foundation
import OSLog

public actor AwakeCoordinator {
    private let power: any PowerAssertionControlling
    private let sleeper: any AsyncSleeping
    private let idleDebounce: Duration
    private let reconnectGrace: Duration
    private let logger = Logger(subsystem: "com.melnikoleg.CodexAwake", category: "Coordinator")

    private var autoKeepAwake: Bool
    private var keepAwakeForCodexDesktop: Bool
    private var codexDesktopRunning = false
    private var codexDesktopActiveCount = 0
    private var latestSnapshot = ActivitySnapshot()
    private var pendingRelease: Task<Void, Never>?

    public init(
        power: any PowerAssertionControlling,
        sleeper: any AsyncSleeping = SystemSleeper(),
        autoKeepAwake: Bool = true,
        keepAwakeForCodexDesktop: Bool = true,
        idleDebounce: Duration = .seconds(1),
        reconnectGrace: Duration = .seconds(30)
    ) {
        self.power = power
        self.sleeper = sleeper
        self.autoKeepAwake = autoKeepAwake
        self.keepAwakeForCodexDesktop = keepAwakeForCodexDesktop
        self.idleDebounce = idleDebounce
        self.reconnectGrace = reconnectGrace
    }

    public func update(_ snapshot: ActivitySnapshot) async {
        latestSnapshot = snapshot
        await evaluate()
    }

    public func setCodexDesktopRunning(_ running: Bool) async {
        codexDesktopRunning = running
        await evaluate()
    }

    public func setCodexDesktopActiveCount(_ count: Int) async {
        codexDesktopActiveCount = max(0, count)
        await evaluate()
    }

    public func setKeepAwakeForCodexDesktop(_ enabled: Bool) async {
        keepAwakeForCodexDesktop = enabled
        await evaluate()
    }

    private func evaluate() async {
        pendingRelease?.cancel()
        pendingRelease = nil

        guard autoKeepAwake else {
            await power.release()
            return
        }

        if codexDesktopActiveCount > 0 || (keepAwakeForCodexDesktop && codexDesktopRunning) {
            await acquireAssertion()
            return
        }

        if latestSnapshot.certainty == .unknownReconnecting {
            if latestSnapshot.activeCount > 0 {
                do {
                    try await power.acquire()
                } catch {
                    logger.error("Power assertion acquisition failed: \(SafeDisplay.sanitizedError(error), privacy: .public)")
                }
            }
            scheduleRelease(after: reconnectGrace)
            return
        }

        if latestSnapshot.activeCount > 0 {
            await acquireAssertion()
            return
        }

        scheduleRelease(after: idleDebounce)
    }

    public func setAutoKeepAwake(_ enabled: Bool) async {
        autoKeepAwake = enabled
        if enabled {
            await evaluate()
        } else {
            pendingRelease?.cancel()
            pendingRelease = nil
            await power.release()
        }
    }

    public func serverConfirmedStopped() async {
        pendingRelease?.cancel()
        pendingRelease = nil
        latestSnapshot = ActivitySnapshot()
        if autoKeepAwake,
           codexDesktopActiveCount > 0 || (keepAwakeForCodexDesktop && codexDesktopRunning) {
            await acquireAssertion()
        } else {
            await power.release()
        }
    }

    public func shutdown() async {
        pendingRelease?.cancel()
        pendingRelease = nil
        await power.release()
    }

    public func assertionIsHeld() async -> Bool {
        await power.assertionIsHeld()
    }

    private func acquireAssertion() async {
        do {
            try await power.acquire()
        } catch {
            logger.error("Power assertion acquisition failed: \(SafeDisplay.sanitizedError(error), privacy: .public)")
        }
    }

    private func scheduleRelease(after delay: Duration) {
        pendingRelease = Task { [sleeper, power] in
            do {
                try await sleeper.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await power.release()
            } catch {
                // Cancellation is the expected path when activity resumes.
            }
        }
    }
}
