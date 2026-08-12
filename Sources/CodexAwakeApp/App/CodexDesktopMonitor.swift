import AppKit
import CodexAwakeCore
import Foundation

@MainActor
final class CodexDesktopMonitor {
    struct Snapshot: Equatable {
        var isRunning = false
        var activeSessionIDs: Set<String> = []
    }

    typealias SnapshotHandler = @MainActor (Snapshot) -> Void

    private let workspace: NSWorkspace
    private let scanner: any CodexDesktopSessionScanning
    private let sessionsRoot: URL
    private let scanInterval: Duration
    private var snapshot = Snapshot()
    private var launchDate: Date?
    private var observerTokens: [NSObjectProtocol] = []
    private var activityTask: Task<Void, Never>?
    private var snapshotHandler: SnapshotHandler?

    init(
        workspace: NSWorkspace = .shared,
        scanner: any CodexDesktopSessionScanning = CodexDesktopRolloutScanner(),
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
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
            activeSessionIDs: running ? snapshot.activeSessionIDs : []
        )
    }

    private func refreshActivity() async {
        guard snapshot.isRunning else { return }

        let scanner = scanner
        let sessionsRoot = sessionsRoot
        let launchDate = launchDate
        let sessions = await Task.detached(priority: .utility) {
            scanner.activeSessions(in: sessionsRoot, desktopLaunchDate: launchDate)
        }.value
        guard !Task.isCancelled else { return }
        updateSnapshot(
            isRunning: true,
            activeSessionIDs: Set(sessions.map(\.id))
        )
    }

    private func updateSnapshot(isRunning: Bool, activeSessionIDs: Set<String>) {
        let updated = Snapshot(isRunning: isRunning, activeSessionIDs: activeSessionIDs)
        guard updated != snapshot else { return }
        snapshot = updated
        snapshotHandler?(updated)
    }
}
