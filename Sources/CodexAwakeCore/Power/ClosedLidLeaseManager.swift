import Foundation
import OSLog

public enum ClosedLidConnectionState: String, Equatable, Sendable {
    case setupRequired
    case ready
    case armed
    case active
    case reconnecting
}

public struct ClosedLidProtectionSnapshot: Equatable, Sendable {
    public var requested = false
    public var helperInstalled = false
    public var helperReachable = false
    public var leaseActive = false
    public var leaseExpiresAt: Date?
    public var nextRetryAt: Date?
    public var lastError: String?

    public init() {}
}

public actor ClosedLidLeaseManager {
    private let helper: any ClosedLidHelperCommunicating
    private let sleeper: any AsyncSleeping
    private let fileManager: FileManager
    private let token: String
    private let leaseDuration: TimeInterval
    private let renewalInterval: Duration
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.melnikoleg.CodexAwake", category: "ClosedLidLease")

    private var requested = false
    private var desiredActive = false
    private var helperReachable = false
    private var leaseActive = false
    private var leaseExpiresAt: Date?
    private var lastError: String?
    private var retryAttempt = 0
    private var nextRetryAt: Date?
    private var renewalTask: Task<Void, Never>?

    public init(
        helper: any ClosedLidHelperCommunicating = ClosedLidHelperClient(),
        sleeper: any AsyncSleeping = SystemSleeper(),
        fileManager: FileManager = .default,
        token: String = UUID().uuidString,
        leaseDuration: TimeInterval = ClosedLidHelperConstants.leaseDuration,
        renewalInterval: Duration = ClosedLidHelperConstants.renewalInterval,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.helper = helper
        self.sleeper = sleeper
        self.fileManager = fileManager
        self.token = token
        self.leaseDuration = leaseDuration
        self.renewalInterval = renewalInterval
        self.now = now
    }

    public func setRequested(_ enabled: Bool, protectionIsActive: Bool) async throws {
        requested = enabled
        desiredActive = protectionIsActive
        if enabled, protectionIsActive {
            do {
                try await acquire()
            } catch {
                record(error)
                throw error
            }
        } else {
            await release()
        }
    }

    public func setProtectionActive(_ active: Bool) async {
        desiredActive = active
        if active, requested {
            do { try await acquire() } catch { record(error) }
        } else {
            await release()
        }
    }

    @discardableResult
    public func refresh(retryIfNeeded: Bool = true) async -> ClosedLidProtectionSnapshot {
        let mayContactHelper = !retryIfNeeded || nextRetryAt.map { now() >= $0 } ?? true
        if retryIfNeeded, requested, desiredActive, !leaseActive {
            if mayContactHelper {
                do { try await acquire() } catch { record(error) }
            }
        } else if helperInstalled, mayContactHelper {
            do {
                apply(try await helper.status())
                helperReachable = true
                clearFailure()
                if !desiredActive { leaseActive = false }
            } catch {
                helperReachable = false
                record(error)
            }
        }
        return snapshot()
    }

    public func snapshot() -> ClosedLidProtectionSnapshot {
        var value = ClosedLidProtectionSnapshot()
        value.requested = requested
        value.helperInstalled = helperInstalled
        value.helperReachable = helperReachable
        value.leaseActive = leaseActive
        value.leaseExpiresAt = leaseExpiresAt
        value.nextRetryAt = nextRetryAt
        value.lastError = lastError
        return value
    }

    private var helperInstalled: Bool {
        fileManager.isExecutableFile(atPath: ClosedLidHelperConstants.installedExecutablePath)
            && fileManager.fileExists(atPath: ClosedLidHelperConstants.installedPlistPath)
    }

    private func acquire() async throws {
        let status = try await helper.acquire(token: token, duration: leaseDuration)
        helperReachable = true
        clearFailure()
        apply(status)
        guard status.disablesSleep else {
            throw ClosedLidHelperClientError.rejected("helper did not enable the closed-lid lease")
        }
        startRenewalLoopIfNeeded()
        logger.notice("Closed-Lid lease acquired")
    }

    private func release() async {
        renewalTask?.cancel()
        renewalTask = nil
        guard leaseActive || helperReachable else {
            leaseActive = false
            leaseExpiresAt = nil
            return
        }
        do {
            let status = try await helper.release(token: token)
            helperReachable = true
            apply(status)
            leaseActive = false
            leaseExpiresAt = nil
            clearFailure()
            logger.notice("Closed-Lid lease released")
        } catch {
            helperReachable = false
            leaseActive = false
            leaseExpiresAt = nil
            record(error)
        }
    }

    private func startRenewalLoopIfNeeded() {
        guard renewalTask == nil else { return }
        renewalTask = Task { [weak self, sleeper, renewalInterval] in
            while !Task.isCancelled {
                do { try await sleeper.sleep(for: renewalInterval) } catch { return }
                guard !Task.isCancelled, let self else { return }
                await self.renew()
            }
        }
    }

    private func renew() async {
        guard requested, desiredActive else {
            await release()
            return
        }
        do {
            let status = try await helper.renew(token: token, duration: leaseDuration)
            helperReachable = true
            clearFailure()
            apply(status)
        } catch {
            helperReachable = false
            leaseActive = false
            leaseExpiresAt = nil
            record(error)
        }
    }

    private func apply(_ status: ClosedLidHelperStatus) {
        leaseActive = desiredActive && status.disablesSleep
        leaseExpiresAt = status.leaseExpiresAt
        if let error = status.error { lastError = String(error.prefix(300)) }
    }

    private func record(_ error: Error) {
        lastError = SafeDisplay.sanitizedError(error)
        retryAttempt = min(retryAttempt + 1, 5)
        let delay = min(pow(2.0, Double(retryAttempt - 1)), 30)
        nextRetryAt = now().addingTimeInterval(delay)
        logger.error("Closed-Lid helper error: \(self.lastError ?? "unknown", privacy: .public)")
    }

    private func clearFailure() {
        lastError = nil
        retryAttempt = 0
        nextRetryAt = nil
    }
}

extension ClosedLidProtectionSnapshot {
    public var connectionState: ClosedLidConnectionState {
        if !helperInstalled { return .setupRequired }
        if leaseActive { return .active }
        if helperReachable { return requested ? .armed : .ready }
        return .reconnecting
    }
}
