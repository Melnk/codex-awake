import Foundation
import OSLog

public actor AppServerSupervisor {
    public typealias StateHandler = @Sendable (AppServerState, Int32?) async -> Void

    private let socketManager: SocketPathManager
    private let stateHandler: StateHandler
    private let logger = Logger(subsystem: "com.melnikoleg.CodexAwake", category: "Supervisor")
    private var process: Process?
    private var binaryPath: String?
    private var runtimeValue: SocketPathManager.Runtime?
    private var requestedStop = false
    private var restartAttempt = 0
    private var generation = 0
    private(set) public var state: AppServerState = .stopped
    private(set) public var pid: Int32?

    public init(socketManager: SocketPathManager = .init(), stateHandler: @escaping StateHandler) {
        self.socketManager = socketManager
        self.stateHandler = stateHandler
    }

    public func start(binaryPath: String, runtime: SocketPathManager.Runtime) async throws {
        guard process == nil else { return }
        let recovering = state == .reconnecting
        if !recovering { restartAttempt = 0 }
        self.binaryPath = binaryPath
        self.runtimeValue = runtime
        requestedStop = false
        generation += 1
        try socketManager.prepare(runtime)
        await transition(to: .starting, pid: nil)

        let child = Process()
        let output = Pipe()
        let errors = Pipe()
        child.executableURL = URL(fileURLWithPath: binaryPath)
        child.arguments = ["app-server", "--listen", runtime.endpoint]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        child.standardError = errors
        output.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }

        let launchedGeneration = generation
        child.terminationHandler = { [weak self] child in
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            Task { await self?.processEnded(child, generation: launchedGeneration) }
        }
        do {
            try child.run()
        } catch {
            try? socketManager.cleanupOwnedSocket(runtime)
            await transition(to: .failed, pid: nil)
            throw CodexAwakeError.serverStartFailed(SafeDisplay.sanitizedError(error))
        }
        process = child
        pid = child.processIdentifier
        logger.notice("Started owned Codex App Server process \(child.processIdentifier)")
        await transition(to: .running, pid: child.processIdentifier)
    }

    public func stop() async {
        requestedStop = true
        generation += 1
        guard let child = process else {
            if let runtimeValue { try? socketManager.cleanupOwnedRuntime(runtimeValue) }
            await transition(to: .stopped, pid: nil)
            return
        }
        await transition(to: .stopping, pid: child.processIdentifier)
        if child.isRunning { child.terminate() }
        for _ in 0..<20 where child.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if child.isRunning {
            child.interrupt()
            for _ in 0..<10 where child.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        if !child.isRunning, process === child {
            process = nil
            pid = nil
            if let runtimeValue { try? socketManager.cleanupOwnedRuntime(runtimeValue) }
            await transition(to: .stopped, pid: nil)
        }
    }

    public func restart() async throws {
        guard let binaryPath, let runtimeValue else { return }
        await stop()
        for _ in 0..<30 where process != nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try await start(binaryPath: binaryPath, runtime: runtimeValue)
    }

    private func processEnded(_ child: Process, generation endedGeneration: Int) async {
        guard process === child else { return }
        let wasRequested = requestedStop || endedGeneration != generation
        process = nil
        pid = nil
        if let runtimeValue { try? socketManager.cleanupOwnedRuntime(runtimeValue) }
        if wasRequested {
            await transition(to: .stopped, pid: nil)
            return
        }

        logger.error("Owned Codex App Server exited unexpectedly with status \(child.terminationStatus)")
        await transition(to: .reconnecting, pid: nil)
        restartAttempt += 1
        let delay = min(pow(2.0, Double(restartAttempt - 1)), 30.0)
        try? await Task.sleep(for: .seconds(delay))
        guard !requestedStop,
            let binaryPath,
            let runtimeValue
        else { return }
        do {
            try await start(binaryPath: binaryPath, runtime: runtimeValue)
        } catch {
            await transition(to: .failed, pid: nil)
        }
    }

    private func transition(to state: AppServerState, pid: Int32?) async {
        self.state = state
        self.pid = pid
        await stateHandler(state, pid)
    }
}
