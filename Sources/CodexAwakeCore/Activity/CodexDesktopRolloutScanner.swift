import Foundation

public struct CodexDesktopSessionState: Equatable, Sendable, Identifiable {
    public let id: String
    public let modifiedAt: Date
    public let workspacePath: String?
    public let startedAt: Date?

    public init(
        id: String,
        modifiedAt: Date,
        workspacePath: String? = nil,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.modifiedAt = modifiedAt
        self.workspacePath = workspacePath
        self.startedAt = startedAt
    }
}

public protocol CodexDesktopSessionScanning: Sendable {
    func activeSessions(
        in sessionsRoot: URL,
        desktopLaunchDate: Date?
    ) -> [CodexDesktopSessionState]
}

/// Reads only rollout identity metadata and task lifecycle markers. Prompt and response
/// fields are never decoded, returned, or logged.
public struct CodexDesktopRolloutScanner: CodexDesktopSessionScanning, @unchecked Sendable {
    private enum LifecycleMarker {
        case started
        case completed
    }

    private let fileManager: FileManager
    private let chunkSize = 64 * 1024
    private let startedPattern = Data(#""type":"task_started""#.utf8)
    private let completedPattern = Data(#""type":"task_complete""#.utf8)

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func activeSessions(
        in sessionsRoot: URL,
        desktopLaunchDate: Date? = nil
    ) -> [CodexDesktopSessionState] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard
            let enumerator = fileManager.enumerator(
                at: sessionsRoot,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var active: [CodexDesktopSessionState] = []
        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true,
                let modifiedAt = values.contentModificationDate
            else { continue }

            // A lifecycle marker left by a previous crashed app launch is not live work.
            if let desktopLaunchDate, modifiedAt < desktopLaunchDate.addingTimeInterval(-2) {
                continue
            }
            guard let metadata = desktopSessionMetadata(in: file),
                lastLifecycleMarker(in: file) == .started
            else { continue }
            active.append(
                .init(
                    id: metadata.id,
                    modifiedAt: modifiedAt,
                    workspacePath: metadata.workspacePath,
                    startedAt: metadata.startedAt
                ))
        }

        return active.sorted {
            if $0.modifiedAt == $1.modifiedAt { return $0.id < $1.id }
            return $0.modifiedAt > $1.modifiedAt
        }
    }

    private struct SessionMetadata {
        let id: String
        let workspacePath: String?
        let startedAt: Date?
    }

    private func desktopSessionMetadata(in file: URL) -> SessionMetadata? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: chunkSize),
            let newline = prefix.firstIndex(of: 0x0A)
        else { return nil }
        let firstLine = prefix.prefix(upTo: newline)
        guard let object = try? JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
            object["type"] as? String == "session_meta",
            let payload = object["payload"] as? [String: Any],
            payload["source"] as? String == "vscode",
            payload["originator"] as? String == "Codex Desktop",
            let id = payload["id"] as? String,
            !id.isEmpty
        else { return nil }
        let timestamp = object["timestamp"] as? String
        return SessionMetadata(
            id: id,
            workspacePath: payload["cwd"] as? String,
            startedAt: timestamp.flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }

    private func lastLifecycleMarker(in file: URL) -> LifecycleMarker? {
        guard let handle = try? FileHandle(forReadingFrom: file),
            let end = try? handle.seekToEnd()
        else { return nil }
        defer { try? handle.close() }

        let overlapCount = max(startedPattern.count, completedPattern.count) - 1
        var cursor = end
        var laterPrefix = Data()

        while cursor > 0 {
            let readCount = Int(min(UInt64(chunkSize), cursor))
            let start = cursor - UInt64(readCount)
            do {
                try handle.seek(toOffset: start)
                guard let chunk = try handle.read(upToCount: readCount) else { return nil }
                var searchable = chunk
                searchable.append(laterPrefix)

                let started = searchable.range(of: startedPattern, options: .backwards)
                let completed = searchable.range(of: completedPattern, options: .backwards)
                switch (started, completed) {
                case (.some(let startedRange), .some(let completedRange)):
                    return startedRange.lowerBound > completedRange.lowerBound ? .started : .completed
                case (.some, .none):
                    return .started
                case (.none, .some):
                    return .completed
                case (.none, .none):
                    break
                }

                laterPrefix = Data(chunk.prefix(overlapCount))
                cursor = start
            } catch {
                return nil
            }
        }
        return nil
    }
}
