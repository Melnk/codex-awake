import Foundation

public struct ProtectionStatisticsSnapshot: Codable, Equatable, Sendable {
    public var protectedSeconds: TimeInterval
    public var sleepPreventionSessions: Int
    public var activeSince: Date?
    public var lastProtectedAt: Date?

    public init(
        protectedSeconds: TimeInterval = 0,
        sleepPreventionSessions: Int = 0,
        activeSince: Date? = nil,
        lastProtectedAt: Date? = nil
    ) {
        self.protectedSeconds = max(0, protectedSeconds)
        self.sleepPreventionSessions = max(0, sleepPreventionSessions)
        self.activeSince = activeSince
        self.lastProtectedAt = lastProtectedAt
    }

    public func current(at date: Date = Date()) -> Self {
        guard let activeSince else { return self }
        var value = self
        value.protectedSeconds += max(0, date.timeIntervalSince(activeSince))
        return value
    }
}

public actor ProtectionStatisticsStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private var snapshot = ProtectionStatisticsSnapshot()
    private var didLoad = false

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    public func load() async throws -> ProtectionStatisticsSnapshot {
        guard !didLoad else { return snapshot.current() }
        didLoad = true
        do {
            let data = try Data(contentsOf: fileURL)
            snapshot = try JSONDecoder().decode(ProtectionStatisticsSnapshot.self, from: data)
            // A power assertion does not survive process termination. Never count app downtime.
            snapshot.activeSince = nil
        } catch  where (error as? CocoaError)?.code == .fileReadNoSuchFile {
            snapshot = .init()
        }
        return snapshot
    }

    public func record(isActive: Bool, at date: Date = Date()) async throws -> ProtectionStatisticsSnapshot {
        _ = try await load()
        var changed = false
        if isActive, snapshot.activeSince == nil {
            snapshot.activeSince = date
            snapshot.lastProtectedAt = date
            snapshot.sleepPreventionSessions += 1
            changed = true
        } else if !isActive, let activeSince = snapshot.activeSince {
            snapshot.protectedSeconds += max(0, date.timeIntervalSince(activeSince))
            snapshot.activeSince = nil
            changed = true
        }
        if changed { try persist() }
        return snapshot.current(at: date)
    }

    public func current(at date: Date = Date()) async throws -> ProtectionStatisticsSnapshot {
        _ = try await load()
        return snapshot.current(at: date)
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let support =
            (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
        return
            support
            .appendingPathComponent("CodexAwake", isDirectory: true)
            .appendingPathComponent("protection-statistics.json")
    }
}
