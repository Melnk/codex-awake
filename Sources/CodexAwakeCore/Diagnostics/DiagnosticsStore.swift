import Combine
import Foundation

public struct DiagnosticsSnapshot: Equatable, Sendable {
    public var appVersion = AppBuildInfo.displayVersion
    public var macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
    public var architecture = "unknown"
    public var codexPath: String?
    public var codexVersion: String?
    public var codexDesktopRunning = false
    public var codexDesktopActiveSessionIDs: Set<String> = []
    public var keepAwakeForCodexDesktop = true
    public var closedLidProtection = ClosedLidProtectionSnapshot()
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
        let desktopSessions = codexDesktopActiveSessionIDs.sorted().map(SafeDisplay.abbreviated).joined(
            separator: ", ")
        let threads = activity.activeThreadIds.sorted().map(SafeDisplay.abbreviated).joined(
            separator: ", ")
        let turns = activity.activeTurnKeys.sorted {
            ($0.threadId, $0.turnId) < ($1.threadId, $1.turnId)
        }.map { "\(SafeDisplay.abbreviated($0.threadId))/\(SafeDisplay.abbreviated($0.turnId))" }
            .joined(separator: ", ")
        return """
            CodexAwake diagnostics
            App version: \(appVersion)
            macOS: \(macOSVersion)
            Architecture: \(architecture)
            Codex path: \(codexPath ?? "not found")
            Codex version: \(codexVersion ?? "unknown")
            Codex desktop app: \(codexDesktopRunning ? "running" : "not running")
            Active Codex desktop sessions: \(codexDesktopActiveSessionIDs.count)
            Active desktop session IDs: \(desktopSessions.isEmpty ? "none" : desktopSessions)
            Keep awake for Codex desktop: \(keepAwakeForCodexDesktop ? "enabled" : "disabled")
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
            Closed-Lid requested: \(closedLidProtection.requested ? "yes" : "no")
            Closed-Lid helper installed: \(closedLidProtection.helperInstalled ? "yes" : "no")
            Closed-Lid helper reachable: \(closedLidProtection.helperReachable ? "yes" : "no")
            Closed-Lid lease: \(closedLidProtection.leaseActive ? "active" : "inactive")
            Closed-Lid lease expires: \(closedLidProtection.leaseExpiresAt.map(formatter.string(from:)) ?? "none")
            Closed-Lid error: \(closedLidProtection.lastError ?? "none")
            Last App Server event: \(lastEventAt.map(formatter.string(from:)) ?? "none")
            Last reconciliation: \(lastReconciliationAt.map(formatter.string(from:)) ?? "none")
            Reconnects: \(reconnectCount)
            Last safe error: \(lastSafeError ?? "none")

            Scope: managed tasks use App Server events. Codex Desktop activity uses only local rollout identity and task_started/task_complete markers; prompt and response text is never read. Independent CLI, cloud, other-user, and remote-host sessions are not tracked.
            Closed lid: when the optional privileged helper is installed, explicitly enabled, and its short lease is active, CodexAwake temporarily disables lid-triggered sleep. The helper restores the original power setting when the final lease ends or expires.
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
