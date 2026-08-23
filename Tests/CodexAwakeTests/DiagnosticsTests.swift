import CodexAwakeCore
import XCTest

@MainActor
final class DiagnosticsTests: XCTestCase {
    func testOperationalJournalIsBoundedAndSanitized() {
        let store = DiagnosticsStore(eventLimit: 2)

        store.append(.init(level: .info, english: "first", russian: "первое"))
        store.append(.init(level: .warning, english: "second\nline", russian: "второе\nстрока"))
        store.append(.init(level: .success, english: "third", russian: "третье"))

        XCTAssertEqual(store.events.count, 2)
        XCTAssertEqual(store.events[0].english, "third")
        XCTAssertEqual(store.events[1].english, "second line")
        XCTAssertTrue(store.sanitizedText.contains("Recent operational events"))
        XCTAssertFalse(store.sanitizedText.contains("first"))
    }

    func testDiagnosticRedactorRemovesHomePathAndCredentialShapes() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let raw = "\(home)/project Authorization: Bearer secret-token-123 api_key=private-value sk-testsecret123"

        let sanitized = SafeDisplay.sanitizedText(raw)

        XCTAssertFalse(sanitized.contains(home))
        XCTAssertFalse(sanitized.contains("secret-token-123"))
        XCTAssertFalse(sanitized.contains("private-value"))
        XCTAssertFalse(sanitized.contains("sk-testsecret123"))
        XCTAssertTrue(sanitized.contains("[REDACTED]"))
    }
}
