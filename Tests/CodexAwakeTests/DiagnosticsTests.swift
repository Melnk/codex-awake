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
}
