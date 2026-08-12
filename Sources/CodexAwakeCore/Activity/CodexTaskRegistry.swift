import Foundation

/// Stores task metadata and lifecycle state only. Chat previews, prompts, responses,
/// command text, and file contents are deliberately outside this type.
public actor CodexTaskRegistry {
    private let historyLimit: Int
    private var records: [String: CodexTaskRecord] = [:]

    public init(historyLimit: Int = 20) {
        self.historyLimit = max(1, historyLimit)
    }

    @discardableResult
    public func reconcileManaged(
        _ summaries: [CodexThreadSummary],
        now: Date = Date()
    ) -> CodexTaskSnapshot {
        for summary in summaries {
            let key = identity(source: .managed, threadId: summary.id)
            let existing = records[key]
            let workspacePath = summary.workspacePath ?? existing?.workspacePath
            let projectName = Self.projectName(
                workspacePath: workspacePath,
                fallback: existing?.projectName ?? "Managed Codex"
            )
            records[key] = CodexTaskRecord(
                threadId: summary.id,
                source: .managed,
                projectName: projectName,
                workspacePath: workspacePath,
                startedAt: summary.createdAt ?? existing?.startedAt ?? now,
                updatedAt: summary.updatedAt ?? now,
                status: Self.taskStatus(from: summary.status, previous: existing?.status)
            )
        }
        trimHistory()
        return snapshot()
    }

    @discardableResult
    public func reconcileManagedStatuses(
        _ statuses: [String: ThreadRuntimeStatus],
        now: Date = Date()
    ) -> CodexTaskSnapshot {
        for (threadId, status) in statuses {
            updateManaged(threadId: threadId, now: now) { record in
                record.status = Self.taskStatus(from: status, previous: record.status)
            }
        }
        trimHistory()
        return snapshot()
    }

    @discardableResult
    public func apply(_ event: AppServerEvent, now: Date = Date()) -> CodexTaskSnapshot {
        switch event {
        case .threadStarted(let threadId, let workspacePath):
            updateManaged(threadId: threadId, now: now) {
                $0.workspacePath = workspacePath ?? $0.workspacePath
                $0.projectName = Self.projectName(
                    workspacePath: $0.workspacePath,
                    fallback: $0.projectName
                )
                $0.status = .waiting
            }

        case .turnStarted(let key):
            updateManaged(threadId: key.threadId, now: now) {
                if !$0.status.isActive { $0.startedAt = now }
                $0.status = .thinking
            }

        case .turnCompleted(let key, let status):
            updateManaged(threadId: key.threadId, now: now) {
                $0.status = status == "failed" ? .error : .completed
            }

        case .threadStatusChanged(let threadId, let status):
            updateManaged(threadId: threadId, now: now) {
                $0.status = Self.taskStatus(from: status, previous: $0.status)
            }

        case .threadClosed(let threadId):
            updateManaged(threadId: threadId, now: now) { $0.status = .completed }

        case .itemStarted(let threadId, _, let kind):
            updateManaged(threadId: threadId, now: now) {
                $0.status = kind.isToolActivity ? .runningTool : .thinking
            }

        case .itemCompleted(let threadId, _, let kind):
            guard kind.isToolActivity else { break }
            updateManaged(threadId: threadId, now: now) { $0.status = .thinking }

        case .runtimeError(let threadId?, _):
            updateManaged(threadId: threadId, now: now) { $0.status = .error }

        case .agentMessageDelta, .agentMessageCompleted, .runtimeError,
            .ignored, .unknown:
            break
        }
        trimHistory()
        return snapshot()
    }

    @discardableResult
    public func markWaitingForApproval(threadId: String, now: Date = Date()) -> CodexTaskSnapshot {
        updateManaged(threadId: threadId, now: now) { $0.status = .waitingForApproval }
        return snapshot()
    }

    @discardableResult
    public func markApprovalResolved(threadId: String, now: Date = Date()) -> CodexTaskSnapshot {
        updateManaged(threadId: threadId, now: now) { $0.status = .thinking }
        return snapshot()
    }

    @discardableResult
    public func reconcileDesktop(
        _ sessions: [CodexDesktopSessionState],
        now: Date = Date()
    ) -> CodexTaskSnapshot {
        let activeKeys = Set(sessions.map { identity(source: .desktop, threadId: $0.id) })

        for session in sessions {
            let key = identity(source: .desktop, threadId: session.id)
            let existing = records[key]
            let workspacePath = session.workspacePath ?? existing?.workspacePath
            records[key] = CodexTaskRecord(
                threadId: session.id,
                source: .desktop,
                projectName: Self.projectName(
                    workspacePath: workspacePath,
                    fallback: existing?.projectName ?? "Codex Desktop"
                ),
                workspacePath: workspacePath,
                startedAt: session.startedAt ?? existing?.startedAt ?? session.modifiedAt,
                updatedAt: session.modifiedAt,
                status: .thinking
            )
        }

        for (key, var record) in records
        where record.source == .desktop && record.status.isActive && !activeKeys.contains(key) {
            record.status = .completed
            record.updatedAt = now
            records[key] = record
        }
        trimHistory()
        return snapshot()
    }

    public func currentSnapshot() -> CodexTaskSnapshot {
        snapshot()
    }

    @discardableResult
    public func markManagedServerStopped(failed: Bool, now: Date = Date()) -> CodexTaskSnapshot {
        for (key, var record) in records where record.source == .managed && record.status.isActive {
            record.status = failed ? .error : .completed
            record.updatedAt = now
            records[key] = record
        }
        trimHistory()
        return snapshot()
    }

    private func updateManaged(
        threadId: String,
        now: Date,
        mutation: (inout CodexTaskRecord) -> Void
    ) {
        let key = identity(source: .managed, threadId: threadId)
        var record =
            records[key]
            ?? CodexTaskRecord(
                threadId: threadId,
                source: .managed,
                projectName: "Managed Codex",
                startedAt: now,
                updatedAt: now,
                status: .waiting
            )
        mutation(&record)
        record.updatedAt = now
        records[key] = record
    }

    private func snapshot() -> CodexTaskSnapshot {
        let active = records.values
            .filter { $0.status.isActive }
            .sorted(by: Self.newestFirst)
        let recent = records.values
            .filter { !$0.status.isActive }
            .sorted(by: Self.newestFirst)
            .prefix(historyLimit)
        return CodexTaskSnapshot(active: active, recent: Array(recent))
    }

    private func trimHistory() {
        let terminal = records.values
            .filter { !$0.status.isActive }
            .sorted(by: Self.newestFirst)
        guard terminal.count > historyLimit else { return }
        for record in terminal.dropFirst(historyLimit) {
            records.removeValue(forKey: record.id)
        }
    }

    private func identity(source: CodexTaskSource, threadId: String) -> String {
        "\(source.rawValue):\(threadId)"
    }

    private static func newestFirst(_ lhs: CodexTaskRecord, _ rhs: CodexTaskRecord) -> Bool {
        if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func taskStatus(
        from status: ThreadRuntimeStatus,
        previous: CodexTaskStatus?
    ) -> CodexTaskStatus {
        switch status.kind {
        case .active:
            if status.activeFlags.contains("waitingOnApproval") { return .waitingForApproval }
            if status.activeFlags.contains("waitingOnUserInput") { return .waiting }
            return previous == .runningTool ? .runningTool : .thinking
        case .idle, .notLoaded:
            return .completed
        case .systemError:
            return .error
        case .unknown:
            return previous ?? .waiting
        }
    }

    private static func projectName(
        workspacePath: String?,
        fallback: String
    ) -> String {
        if let workspacePath, !workspacePath.isEmpty {
            let name = URL(fileURLWithPath: workspacePath).lastPathComponent
            if !name.isEmpty { return name }
        }
        return fallback
    }
}
