import CodexAwakeCore
import Darwin
import Foundation
import OSLog

private struct PersistedLeaseState: Codable {
    var originalSettings: [String: Int]
    var leases: [String: Date]
}

private enum ClosedLidDaemonError: LocalizedError {
    case notRoot
    case invalidClientHash
    case invalidLease
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRoot: "Closed-Lid helper must run as root"
        case .invalidClientHash: "Missing or invalid authorized client CDHash"
        case .invalidLease: "Invalid Closed-Lid lease request"
        case .commandFailed(let message): message
        }
    }
}

private final class PMSetController {
    private let executable = URL(fileURLWithPath: "/usr/bin/pmset")

    func captureDisableSleepSettings() throws -> [String: Int] {
        let output = try run(["-g", "custom"])
        var result: [String: Int] = [:]
        var profile = "all"

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            switch line {
            case "Battery Power:": profile = "battery"
            case "AC Power:": profile = "charger"
            case "UPS Power:": profile = "ups"
            default:
                let fields = line.split(whereSeparator: \.isWhitespace)
                if fields.count == 2, fields[0] == "disablesleep", let value = Int(fields[1]) {
                    result[profile] = value == 0 ? 0 : 1
                }
            }
        }
        return result.isEmpty ? ["all": 0] : result
    }

    func enableDisableSleep() throws {
        _ = try run(["-a", "disablesleep", "1"])
    }

    func restore(_ settings: [String: Int]) throws {
        _ = try run(["-a", "disablesleep", "0"])
        let flags = ["battery": "-b", "charger": "-c", "ups": "-u"]
        for (profile, value) in settings where value != 0 {
            if profile == "all" {
                _ = try run(["-a", "disablesleep", "1"])
            } else if let flag = flags[profile] {
                _ = try run([flag, "disablesleep", "1"])
            }
        }
    }

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr, encoding: .utf8) ?? "pmset failed"
            throw ClosedLidDaemonError.commandFailed(String(message.prefix(300)))
        }
        return String(data: stdout, encoding: .utf8) ?? ""
    }
}

private final class LeaseStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.melnikoleg.CodexAwake.closed-lid-state")
    private let logger = Logger(subsystem: ClosedLidHelperConstants.label, category: "LeaseStore")
    private let pmset = PMSetController()
    private let stateDirectory = URL(fileURLWithPath: "/var/db/com.melnikoleg.CodexAwake", isDirectory: true)
    private lazy var stateURL = stateDirectory.appendingPathComponent("closed-lid-lease.json")
    private var state: PersistedLeaseState?
    private var timer: DispatchSourceTimer?

    init() {
        queue.sync {
            do {
                try loadAndRecover()
                startTimer()
            } catch {
                logger.error("Startup recovery failed: \(error.localizedDescription, privacy: .public)")
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

    func acquire(token: String, duration: TimeInterval, reply: @escaping (Bool, TimeInterval, String?) -> Void) {
        queue.async {
            do {
                try self.update(token: token, duration: duration, requiresExistingLease: false)
                self.reply(nil, to: reply)
            } catch {
                self.reply(error, to: reply)
            }
        }
    }

    func renew(token: String, duration: TimeInterval, reply: @escaping (Bool, TimeInterval, String?) -> Void) {
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
                try self.validate(token: token, duration: nil)
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
            do { try restoreAndClear() } catch {
                logger.error("Shutdown recovery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func recoverPersistedState() throws {
        let store = LeaseStore()
        store.shutdownAndRestore()
    }

    private func update(token: String, duration: TimeInterval, requiresExistingLease: Bool) throws {
        try validate(token: token, duration: duration)
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
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return }
        let data = try Data(contentsOf: stateURL)
        state = try JSONDecoder().decode(PersistedLeaseState.self, from: data)
        try pruneExpiredLeases()
        if state != nil { try pmset.enableDisableSleep() }
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
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    private func restoreAndClear() throws {
        guard let state else { return }
        try pmset.restore(state.originalSettings)
        try? FileManager.default.removeItem(at: stateURL)
        self.state = nil
        logger.notice("Restored the original disablesleep setting")
    }

    private func emergencyRestoreAfterCorruption() {
        do {
            try pmset.restore(["all": 0])
            try? FileManager.default.removeItem(at: stateURL)
            state = nil
            logger.error("Corrupt helper state removed; normal sleep restored")
        } catch {
            logger.fault("Emergency sleep restoration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func validate(token: String, duration: TimeInterval?) throws {
        guard !token.isEmpty, token.utf8.count <= 128 else {
            throw ClosedLidDaemonError.invalidLease
        }
        if let duration, (!duration.isFinite || duration <= 0) {
            throw ClosedLidDaemonError.invalidLease
        }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            do { try self.pruneExpiredLeases() } catch {
                self.logger.error("Lease expiry recovery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        timer.resume()
        self.timer = timer
    }

    private func reply(_ error: Error?, to reply: (Bool, TimeInterval, String?) -> Void) {
        let latestExpiry = state?.leases.values.max()?.timeIntervalSince1970 ?? 0
        reply(state?.leases.isEmpty == false, latestExpiry, error.map { String($0.localizedDescription.prefix(300)) })
    }
}

private final class HelperService: NSObject, ClosedLidHelperXPCProtocol {
    private let store: LeaseStore

    init(store: LeaseStore) {
        self.store = store
    }

    func status(withReply reply: @escaping (Bool, TimeInterval, String?) -> Void) {
        store.status(reply: reply)
    }

    func acquireLease(
        token: String,
        duration: TimeInterval,
        withReply reply: @escaping (Bool, TimeInterval, String?) -> Void
    ) {
        store.acquire(token: token, duration: duration, reply: reply)
    }

    func renewLease(
        token: String,
        duration: TimeInterval,
        withReply reply: @escaping (Bool, TimeInterval, String?) -> Void
    ) {
        store.renew(token: token, duration: duration, reply: reply)
    }

    func releaseLease(token: String, withReply reply: @escaping (Bool, TimeInterval, String?) -> Void) {
        store.release(token: token, reply: reply)
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: HelperService

    init(service: HelperService) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ClosedLidHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.activate()
        return true
    }
}

private func validatedClientHash(arguments: [String]) throws -> String {
    guard arguments.count == 3, arguments[1] == "--client-cdhash" else {
        throw ClosedLidDaemonError.invalidClientHash
    }
    let value = arguments[2].lowercased()
    let valid = value.count == 40 && value.allSatisfy { $0.isHexDigit }
    guard valid else { throw ClosedLidDaemonError.invalidClientHash }
    return value
}

guard geteuid() == 0 else {
    FileHandle.standardError.write(Data("Closed-Lid helper must run as root\n".utf8))
    exit(EXIT_FAILURE)
}

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--recover" {
    do {
        try LeaseStore.recoverPersistedState()
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(Data("Recovery failed: \(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

do {
    let clientHash = try validatedClientHash(arguments: CommandLine.arguments)
    let store = LeaseStore()
    let service = HelperService(store: store)
    let delegate = ListenerDelegate(service: service)
    let listener = NSXPCListener(machServiceName: ClosedLidHelperConstants.machServiceName)
    listener.setConnectionCodeSigningRequirement("cdhash H\"\(clientHash)\"")
    listener.delegate = delegate

    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termination.setEventHandler {
        store.shutdownAndRestore()
        exit(EXIT_SUCCESS)
    }
    termination.resume()

    listener.activate()
    RunLoop.current.run()
} catch {
    FileHandle.standardError.write(Data("Closed-Lid helper failed: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
