import Foundation

public struct OperationalEvent: Identifiable, Equatable, Sendable {
    public enum Level: String, Sendable {
        case info
        case success
        case warning
        case error
    }

    public let id: UUID
    public let timestamp: Date
    public let level: Level
    public let english: String
    public let russian: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: Level,
        english: String,
        russian: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.english = String(
            SafeDisplay.sanitizedText(english).replacingOccurrences(of: "\n", with: " ").prefix(300)
        )
        self.russian = String(
            SafeDisplay.sanitizedText(russian).replacingOccurrences(of: "\n", with: " ").prefix(300)
        )
    }
}
