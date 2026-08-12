import CodexAwakeCore
import Foundation
import OSLog

final class LeaseStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.melnikoleg.CodexAwake.closed-lid-state")
    private let logger = Logger(subsystem: ClosedLidHelperConstants.label, category: "LeaseStore")
    private let pmset: PMSetController
    private let validator: LeaseRequestValidator
    private let fileManager: FileManager
    private let stateDirectory: URL
    private lazy var stateURL = stateDirectory.appendingPathComponent("closed-lid-lease.json")
    private var state: PersistedLeaseState?
    private var timer: DispatchSourceTimer?

    init(
        pmset: PMSetController = PMSetController(),
        validator: LeaseRequestValidator = LeaseRequestValidator(),
        fileManager: FileManager = .default,
        stateDirectory: URL = URL(
            fileURLWithPath: "/var/db/com.melnikoleg.CodexAwake",
            isDirectory: true
        )
    ) {
        self.pmset = pmset
        self.validator = validator
        self.fileManager = fileManager
        self.stateDirectory = stateDirectory
        queue.sync {
            do {
                try loadAndRecover()
                startTimer()
            } catch {
                logger.error("Startup recovery failed")
                emergencyRestoreAfterCorruption()
            }
        }
    }

    func status(reply: @escaping (Bool, TimeInterval, String?) -> Void) {
        queue.async {
            do {
                try self.pruneExpiredLeases()
                self.reply(nil, to: reply)
            } catch {
                self.reply(error, to: reply)
            }
        }
    }

    func acquire(
        token: String, duration: TimeInterval, reply: @escaping (Bool, TimeInterval, String?) -> Void
    ) {
        queue.async {
            do {
                try self.update(token: token, duration: duration, requiresExistingLease: false)
                self.reply(nil, to: reply)
            } catch {
                self.reply(error, to: reply)
            }
        }
    }

    func renew(
        token: String, duration: TimeInterval, reply: @escaping (Bool, TimeInterval, String?) -> Void
    ) {
        queue.async {
            do {
                try self.update(token: token, duration: duration, requiresExistingLease: true)
                self.reply(nil, to: reply)
            } catch {
                self.reply(error, to: reply)
            }
        }
    }

    func release(token: String, reply: @escaping (Bool, TimeInterval, String?) -> Void) {
        queue.async {
            do {
                try self.validator.validate(token: token)
                self.state?.leases.removeValue(forKey: token)
                try self.persistOrRestore()
                self.reply(nil, to: reply)
            } catch {
                self.reply(error, to: reply)
            }
        }
    }

    func shutdownAndRestore() {
        queue.sync {
            timer?.cancel()
            timer = nil
            do {
                try restoreAndClear()
            } catch {
                logger.error("Shutdown recovery failed")
            }
        }
    }

    static func recoverPersistedState() throws {
        let store = LeaseStore()
        store.shutdownAndRestore()
    }

    private func update(token: String, duration: TimeInterval, requiresExistingLease: Bool) throws {
        try validator.validate(token: token, duration: duration)
        try pruneExpiredLeases()
        if requiresExistingLease, state?.leases[token] == nil {
            throw ClosedLidDaemonError.commandFailed("lease does not exist; acquire it again")
        }

        if state == nil {
            let original = try pmset.captureDisableSleepSettings()
            state = PersistedLeaseState(originalSettings: original, leases: [:])
            try persist()
            try pmset.enableDisableSleep()
        }

        if state?.leases[token] == nil, (state?.leases.count ?? 0) >= 32 {
            throw ClosedLidDaemonError.invalidLease
        }

        let boundedDuration = min(max(duration, 15), ClosedLidHelperConstants.leaseDuration)
        state?.leases[token] = Date().addingTimeInterval(boundedDuration)
        try persist()
    }

    private func loadAndRecover() throws {
        guard fileManager.fileExists(atPath: stateURL.path) else { return }
        let data = try Data(contentsOf: stateURL)
        state = try JSONDecoder().decode(PersistedLeaseState.self, from: data)
        try pruneExpiredLeases()
        if state != nil {
            try pmset.enableDisableSleep()
        }
    }

    private func pruneExpiredLeases() throws {
        guard var current = state else { return }
        let now = Date()
        current.leases = current.leases.filter { $0.value > now }
        state = current
        try persistOrRestore()
    }

    private func persistOrRestore() throws {
        if state?.leases.isEmpty != false {
            try restoreAndClear()
        } else {
            try persist()
        }
    }

    private func persist() throws {
        guard let state else { return }
        try fileManager.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    private func restoreAndClear() throws {
        guard let state else { return }
        try pmset.restore(state.originalSettings)
        do {
            try fileManager.removeItem(at: stateURL)
        } catch CocoaError.fileNoSuchFile {
            // The desired state is already reached.
        }
        self.state = nil
        logger.notice("Restored the original disablesleep setting")
    }

    private func emergencyRestoreAfterCorruption() {
        do {
            try pmset.restore(["all": 0])
            do {
                try fileManager.removeItem(at: stateURL)
            } catch CocoaError.fileNoSuchFile {
                // Nothing remains to remove.
            }
            state = nil
            logger.error("Corrupt helper state removed; normal sleep restored")
        } catch {
            logger.fault("Emergency sleep restoration failed")
        }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            do {
                try self.pruneExpiredLeases()
            } catch {
                self.logger.error("Lease expiry recovery failed")
            }
        }
        timer.resume()
        self.timer = timer
    }

    private func reply(_ error: Error?, to reply: (Bool, TimeInterval, String?) -> Void) {
        let latestExpiry = state?.leases.values.max()?.timeIntervalSince1970 ?? 0
        let safeError = error.map { String($0.localizedDescription.prefix(300)) }
        reply(state?.leases.isEmpty == false, latestExpiry, safeError)
    }
}
