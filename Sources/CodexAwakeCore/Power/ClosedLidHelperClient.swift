import Foundation

public enum ClosedLidHelperClientError: LocalizedError, Sendable {
    case unavailable(String)
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message): "Closed-Lid helper unavailable: \(message)"
        case .rejected(let message): "Closed-Lid helper rejected the request: \(message)"
        }
    }
}

public actor ClosedLidHelperClient: ClosedLidHelperCommunicating {
    public init() {}

    public func status() async throws -> ClosedLidHelperStatus {
        try await request { proxy, reply in proxy.status(withReply: reply) }
    }

    public func acquire(token: String, duration: TimeInterval) async throws -> ClosedLidHelperStatus {
        try await request { proxy, reply in
            proxy.acquireLease(token: token, duration: duration, withReply: reply)
        }
    }

    public func renew(token: String, duration: TimeInterval) async throws -> ClosedLidHelperStatus {
        try await request { proxy, reply in
            proxy.renewLease(token: token, duration: duration, withReply: reply)
        }
    }

    public func release(token: String) async throws -> ClosedLidHelperStatus {
        try await request { proxy, reply in proxy.releaseLease(token: token, withReply: reply) }
    }

    private func request(
        _ body: @escaping (
            ClosedLidHelperXPCProtocol,
            @escaping (Bool, TimeInterval, String?) -> Void
        ) -> Void
    ) async throws -> ClosedLidHelperStatus {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(
                machServiceName: ClosedLidHelperConstants.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: ClosedLidHelperXPCProtocol.self)
            connection.setCodeSigningRequirement(#"identifier "com.melnikoleg.CodexAwake.ClosedLidHelper""#)

            let gate = XPCReplyGate(continuation: continuation, connection: connection)
            gate.scheduleTimeout()
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                gate.fail(.unavailable(SafeDisplay.sanitizedError(error)))
            }
            guard let helper = proxy as? ClosedLidHelperXPCProtocol else {
                gate.fail(.unavailable("invalid XPC proxy"))
                return
            }
            connection.invalidationHandler = {
                gate.fail(.unavailable("connection invalidated"))
            }
            connection.activate()
            body(helper) { enabled, expiresAt, error in
                if let error, !error.isEmpty {
                    gate.fail(.rejected(String(error.prefix(300))))
                } else {
                    gate.succeed(.init(
                        disablesSleep: enabled,
                        leaseExpiresAt: expiresAt > 0 ? Date(timeIntervalSince1970: expiresAt) : nil
                    ))
                }
            }
        }
    }
}

private final class XPCReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ClosedLidHelperStatus, Error>?
    private var connection: NSXPCConnection?
    private var timeoutTask: Task<Void, Never>?

    init(
        continuation: CheckedContinuation<ClosedLidHelperStatus, Error>,
        connection: NSXPCConnection
    ) {
        self.continuation = continuation
        self.connection = connection
    }

    func succeed(_ status: ClosedLidHelperStatus) {
        finish(.success(status))
    }

    func fail(_ error: ClosedLidHelperClientError) {
        finish(.failure(error))
    }

    func scheduleTimeout() {
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.fail(.unavailable("request timed out"))
        }
    }

    private func finish(_ result: Result<ClosedLidHelperStatus, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        timeoutTask?.cancel()
        connection?.invalidate()
        continuation.resume(with: result)
    }
}
