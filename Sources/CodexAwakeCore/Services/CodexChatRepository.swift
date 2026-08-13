import Foundation

public protocol CodexChatPersisting: Sendable {
    func load() async throws -> CodexChatArchive
    func save(_ archive: CodexChatArchive) async throws
}

public actor FileCodexChatRepository: CodexChatPersisting {
    private let explicitFileURL: URL?
    private let fileManager: FileManager

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        explicitFileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> CodexChatArchive {
        let fileURL = try resolveFileURL(createDirectory: false)
        guard fileManager.fileExists(atPath: fileURL.path) else { return .init() }
        let data = try Data(contentsOf: fileURL)
        var archive = try JSONDecoder.codexChat.decode(CodexChatArchive.self, from: data)
        archive.conversations = archive.conversations.map(Self.restoredConversation)
        return archive
    }

    public func save(_ archive: CodexChatArchive) throws {
        let fileURL = try resolveFileURL(createDirectory: true)
        let bounded = Self.bounded(archive)
        let data = try JSONEncoder.codexChat.encode(bounded)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func resolveFileURL(createDirectory: Bool) throws -> URL {
        if let explicitFileURL { return explicitFileURL }
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createDirectory
        )
        let directory = support.appendingPathComponent("CodexAwake", isDirectory: true)
        if createDirectory {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        return directory.appendingPathComponent("chat-history.json")
    }

    private static func restoredConversation(_ conversation: CodexConversation) -> CodexConversation {
        var restored = conversation
        if restored.settings.permissionMode == .fullAccess {
            restored.settings.permissionMode = .workspaceWrite
        }
        restored.messages = restored.messages.map { message in
            var value = message
            value.isStreaming = false
            if value.delivery == .sending { value.delivery = .queued }
            if value.delivery == .queued,
                value.requestSettings?.permissionMode == .fullAccess
            {
                value.requestSettings?.permissionMode = .workspaceWrite
            }
            return value
        }
        restored.tools = restored.tools.map { tool in
            var value = tool
            if value.status == .running { value.status = .failed }
            return value
        }
        return restored
    }

    private static func bounded(_ archive: CodexChatArchive) -> CodexChatArchive {
        var value = archive
        value.conversations = Array(
            value.conversations
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(30)
                .map { conversation in
                    var boundedConversation = conversation
                    boundedConversation.messages = Array(conversation.messages.suffix(500))
                    boundedConversation.tools = Array(conversation.tools.suffix(200))
                    return boundedConversation
                }
        )
        return value
    }
}

private extension JSONEncoder {
    static var codexChat: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var codexChat: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
