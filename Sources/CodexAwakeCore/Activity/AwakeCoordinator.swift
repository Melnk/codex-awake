import Foundation
import OSLog

public actor AwakeCoordinator {
    private let power: any PowerAssertionControlling
    private let sleeper: any AsyncSleeping
    private let idleDebounce: Duration
    private let reconnectGrace: Duration
    private let logger = Logger(subsystem: "com.melnikoleg.CodexAwake", category: "Coordinator")

    private var autoKeepAwake: Bool
    private var latestSnapshot = ActivitySnapshot()
    private var pendingRelease: Task<Void, Never>?

    public init(
        power: any PowerAssertionControlling,
        sleeper: any AsyncSleeping = SystemSleeper(),
        autoKeepAwake: Bool = true,
        idleDebounce: Duration = .seconds(1),
        reconnectGrace: Duration = .seconds(30)
    ) {
        self.power = power
        self.sleeper = sleeper
        self.autoKeepAwake = autoKeepAwake
        self.idleDebounce = idleDebounce
        self.reconnectGrace = reconnectGrace
    }

    public func update(_ snapshot: ActivitySnapshot) async {
        latestSnapshot = snapshot
        pendingRelease?.cancel()
        pendingRelease = nil

        guard autoKeepAwake else {
            await power.release()
            return
        }

        if snapshot.certainty == .unknownReconnecting {
            if snapshot.activeCount > 0 {
                do {
                    try await power.acquire()
                } catch {
                    logger.error("Power assertion acquisition failed: \(SafeDisplay.sanitizedError(error), privacy: .public)")
                }
            }
            scheduleRelease(after: reconnectGrace)
            return
        }

        if snapshot.activeCount > 0 {
            do {
                try await power.acquire()
            } catch {
                logger.error("Power assertion acquisition failed: \(SafeDisplay.sanitizedError(error), privacy: .public)")
            }
            return
        }

        scheduleRelease(after: idleDebounce)
    }

    public func setAutoKeepAwake(_ enabled: Bool) async {
        autoKeepAwake = enabled
        if enabled {
            await update(latestSnapshot)
        } else {
            pendingRelease?.cancel()
            pendingRelease = nil
            await power.release()
        }
    }

    public func serverConfirmedStopped() async {
        pendingRelease?.cancel()
        pendingRelease = nil
        await power.release()
    }

    public func shutdown() async {
        pendingRelease?.cancel()
        pendingRelease = nil
        await power.release()
    }

    public func assertionIsHeld() async -> Bool {
        await power.assertionIsHeld()
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
