import Foundation

public protocol AsyncSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct SystemSleeper: AsyncSleeping {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

public enum SafeDisplay {
    public static func abbreviated(_ identifier: String) -> String {
        guard identifier.count > 12 else { return identifier }
        return "\(identifier.prefix(8))…\(identifier.suffix(4))"
    }

    public static func sanitizedError(_ error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return String(sanitizedText(raw).replacingOccurrences(of: "\n", with: " ").prefix(300))
    }

    public static func sanitizedText(_ raw: String) -> String {
        var value = raw.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
        let patterns = [
            #"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}"#,
            #"\bsk-[A-Za-z0-9_-]{8,}"#,
            #"(?i)\b(api[_-]?key|access[_-]?token|refresh[_-]?token|password)\s*[:=]\s*[^\s,;]+"#,
        ]
        for pattern in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: "[REDACTED]",
                options: .regularExpression
            )
        }
        return value
    }
}
