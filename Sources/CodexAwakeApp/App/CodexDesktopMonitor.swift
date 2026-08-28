import AppKit
import CodexAwakeCore
import Foundation

@MainActor
final class CodexDesktopMonitor {
    struct Snapshot: Equatable {
        var isRunning = false
        var activeSessions: [CodexDesktopSessionState] = []

        var activeSessionIDs: Set<String> { Set(activeSessions.map(\.id)) }
    }

    typealias SnapshotHandler = @MainActor (Snapshot) -> Void

    private let workspace: NSWorkspace
    private let scanner: any CodexDesktopSessionScanning
    private let sessionsRoot: URL?
    private let scanInterval: Duration
    private var snapshot = Snapshot()
    private var launchDate: Date?
    private var observerTokens: [NSObjectProtocol] = []
    private var activityTask: Task<Void, Never>?
    private var snapshotHandler: SnapshotHandler?

    init(
        workspace: NSWorkspace = .shared,
        scanner: any CodexDesktopSessionScanning = CodexDesktopRolloutScanner(),
        sessionsRoot: URL? = nil,
        scanInterval: Duration = .seconds(1)
    ) {
        self.workspace = workspace
        self.scanner = scanner
        self.sessionsRoot = sessionsRoot
        self.scanInterval = scanInterval
    }

    func start(onChange: @escaping SnapshotHandler) {
        snapshotHandler = onChange
        guard observerTokens.isEmpty else {
            refreshPresence()
            return
        }

        let center = workspace.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshPresence() }
            }
            observerTokens.append(token)
        }

        refreshPresence()
        guard sessionsRoot != nil else { return }
        activityTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refreshActivity()
                do {
                    try await Task.sleep(for: scanInterval)
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        let center = workspace.notificationCenter
        for token in observerTokens {
            center.removeObserver(token)
        }
        observerTokens.removeAll()
        activityTask?.cancel()
        activityTask = nil
        snapshotHandler = nil
    }

    private func refreshPresence() {
        let supportedBundleIDs: Set<String> = ["com.openai.codex", "com.openai.chat"]
        let applications = workspace.runningApplications.filter { application in
            application.bundleIdentifier.map(supportedBundleIDs.contains) ?? false
        }
        let running = !applications.isEmpty
        launchDate = applications.compactMap(\.launchDate).max()
        updateSnapshot(
            isRunning: running,
            activeSessions: running ? snapshot.activeSessions : []
        )
    }

    private func refreshActivity() async {
        guard snapshot.isRunning, let sessionsRoot else { return }

        let scanner = scanner
        let launchDate = launchDate
        let sessions = await Task.detached(priority: .utility) {
            scanner.activeSessions(in: sessionsRoot, desktopLaunchDate: launchDate)
        }.value
        guard !Task.isCancelled else { return }
        updateSnapshot(
            isRunning: true,
            activeSessions: sessions
        )
    }

    private func updateSnapshot(isRunning: Bool, activeSessions: [CodexDesktopSessionState]) {
        let updated = Snapshot(isRunning: isRunning, activeSessions: activeSessions)
        guard updated != snapshot else { return }
        snapshot = updated
        snapshotHandler?(updated)
    }
}
