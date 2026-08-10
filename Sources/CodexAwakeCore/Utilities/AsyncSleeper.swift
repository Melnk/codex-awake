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
        let singleLine = raw.replacingOccurrences(of: "\n", with: " ")
        return String(singleLine.prefix(300))
    }
}
