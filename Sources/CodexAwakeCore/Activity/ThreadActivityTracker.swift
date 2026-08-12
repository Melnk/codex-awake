import Foundation

public actor ThreadActivityTracker {
    private var activeThreadIds: Set<String> = []
    private var activeTurnKeys: Set<TurnKey> = []
    private var statuses: [String: ThreadRuntimeStatus] = [:]
    private var loadedThreadIds: Set<String> = []
    private var certainty: ActivityCertainty = .known

    public init() {}

    @discardableResult
    public func apply(_ event: AppServerEvent) -> ActivitySnapshot {
        switch event {
        case .threadStarted(let threadId, _):
            loadedThreadIds.insert(threadId)

        case .turnStarted(let key):
            activeTurnKeys.insert(key)
            activeThreadIds.insert(key.threadId)
            statuses[key.threadId] = .init(kind: .active)
            loadedThreadIds.insert(key.threadId)

        case .turnCompleted(let key, _):
            activeTurnKeys.remove(key)
            if !activeTurnKeys.contains(where: { $0.threadId == key.threadId }) {
                activeThreadIds.remove(key.threadId)
                statuses[key.threadId] = .init(kind: .idle)
            }

        case .threadStatusChanged(let threadId, let status):
            statuses[threadId] = status
            if status.kind == .notLoaded {
                loadedThreadIds.remove(threadId)
            } else {
                loadedThreadIds.insert(threadId)
            }
            if status.isActive {
                activeThreadIds.insert(threadId)
            } else {
                activeThreadIds.remove(threadId)
                activeTurnKeys = activeTurnKeys.filter { $0.threadId != threadId }
            }

        case .threadClosed(let threadId):
            activeThreadIds.remove(threadId)
            activeTurnKeys = activeTurnKeys.filter { $0.threadId != threadId }
            statuses[threadId] = .init(kind: .notLoaded)
            loadedThreadIds.remove(threadId)

        case .itemStarted, .itemCompleted, .agentMessageDelta, .agentMessageCompleted,
            .runtimeError, .ignored:
            return snapshot()

        case .unknown:
            certainty = .unknownReconnecting
            return snapshot()
        }
        certainty = .known
        return snapshot()
    }

    @discardableResult
    public func reconcile(
        loadedThreadIds reconciledLoadedIds: Set<String>,
        statuses reconciledStatuses: [String: ThreadRuntimeStatus]
    ) -> ActivitySnapshot {
        loadedThreadIds = reconciledLoadedIds
        statuses.merge(reconciledStatuses) { _, new in new }
        activeThreadIds = Set(
            reconciledStatuses.compactMap { id, status in
                status.isActive ? id : nil
            })
        activeTurnKeys = activeTurnKeys.filter { activeThreadIds.contains($0.threadId) }
        certainty = .known
        return snapshot()
    }

    @discardableResult
    public func markConnectionUnknown() -> ActivitySnapshot {
        certainty = .unknownReconnecting
        return snapshot()
    }

    @discardableResult
    public func confirmServerStopped() -> ActivitySnapshot {
        activeThreadIds.removeAll()
        activeTurnKeys.removeAll()
        statuses.removeAll()
        loadedThreadIds.removeAll()
        certainty = .known
        return snapshot()
    }

    public func currentSnapshot() -> ActivitySnapshot {
        snapshot()
    }

    private func snapshot() -> ActivitySnapshot {
        ActivitySnapshot(
            activeThreadIds: activeThreadIds,
            activeTurnKeys: activeTurnKeys,
            loadedThreadCount: loadedThreadIds.count,
            certainty: certainty
        )
    }
}
