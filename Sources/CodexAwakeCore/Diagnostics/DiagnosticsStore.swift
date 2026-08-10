import Combine
import Foundation

public struct DiagnosticsSnapshot: Equatable, Sendable {
    public var appVersion = "1.0.0 (1)"
    public var macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
    public var architecture = "unknown"
    public var codexPath: String?
    public var codexVersion: String?
    public var transport = "Unix domain socket (WebSocket upgrade)"
    public var endpoint: String?
    public var appServerState: AppServerState = .stopped
    public var serverPID: Int32?
    public var startedAt = Date()
    public var activity = ActivitySnapshot()
    public var assertionHeld = false
    public var lastEventAt: Date?
    public var lastReconciliationAt: Date?
    public var reconnectCount = 0
    public var lastSafeError: String?

    public init() {}

    public var sanitizedText: String {
        let formatter = ISO8601DateFormatter()
        let threads = activity.activeThreadIds.sorted().map(SafeDisplay.abbreviated).joined(separator: ", ")
        let turns = activity.activeTurnKeys.sorted {
            ($0.threadId, $0.turnId) < ($1.threadId, $1.turnId)
        }.map { "\(SafeDisplay.abbreviated($0.threadId))/\(SafeDisplay.abbreviated($0.turnId))" }.joined(separator: ", ")
        return """
        CodexAwake diagnostics
        App version: \(appVersion)
        macOS: \(macOSVersion)
        Architecture: \(architecture)
        Codex path: \(codexPath ?? "not found")
        Codex version: \(codexVersion ?? "unknown")
        Transport: \(transport)
        Endpoint: \(endpoint ?? "unavailable")
        App Server: \(appServerState.rawValue)
        Server PID: \(serverPID.map(String.init) ?? "none")
        Started: \(formatter.string(from: startedAt))
        Loaded threads: \(activity.loadedThreadCount)
        Active threads: \(activity.activeCount)
        Active thread IDs: \(threads.isEmpty ? "none" : threads)
        Active turn IDs: \(turns.isEmpty ? "none" : turns)
        Activity certainty: \(activity.certainty.rawValue)
        Power assertion: \(assertionHeld ? "held" : "released")
        Last App Server event: \(lastEventAt.map(formatter.string(from:)) ?? "none")
        Last reconciliation: \(lastReconciliationAt.map(formatter.string(from:)) ?? "none")
        Reconnects: \(reconnectCount)
        Last safe error: \(lastSafeError ?? "none")

        Scope: only Codex CLI/TUI sessions connected with --remote to the App Server managed by CodexAwake are tracked. Independent CLI, desktop, cloud, other-user, and remote-host sessions are not tracked.
        Closed lid: CodexAwake prevents idle system sleep; it does not bypass macOS lid-close sleep policy.
        """
    }
}

@MainActor
public final class DiagnosticsStore: ObservableObject {
    @Published public var snapshot: DiagnosticsSnapshot

    public init(snapshot: DiagnosticsSnapshot = .init()) {
        self.snapshot = snapshot
    }
}
