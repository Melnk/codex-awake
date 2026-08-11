import CodexAwakeCore
import Foundation
import XCTest

final class CodexDesktopRolloutScannerTests: XCTestCase {
    func testActiveDesktopRolloutIsDetected() throws {
        let fixture = try RolloutFixture(
            events: ["task_started"],
            source: "vscode",
            originator: "Codex Desktop"
        )
        defer { fixture.remove() }

        let result = CodexDesktopRolloutScanner().activeSessions(in: fixture.root)
        XCTAssertEqual(result.map(\.id), [fixture.sessionID])
    }

    func testCompletedDesktopRolloutIsInactive() throws {
        let fixture = try RolloutFixture(
            events: ["task_started", "task_complete"],
            source: "vscode",
            originator: "Codex Desktop"
        )
        defer { fixture.remove() }

        XCTAssertTrue(CodexDesktopRolloutScanner().activeSessions(in: fixture.root).isEmpty)
    }

    func testManagedAndSubagentRolloutsAreIgnored() throws {
        let fixture = try RolloutFixture(
            events: ["task_started"],
            source: "appServer",
            originator: "CodexAwake"
        )
        defer { fixture.remove() }

        XCTAssertTrue(CodexDesktopRolloutScanner().activeSessions(in: fixture.root).isEmpty)
    }

    func testMarkerTextInsideUserContentDoesNotCreateFalseActivity() throws {
        let fixture = try RolloutFixture(events: [], source: "vscode", originator: "Codex Desktop")
        defer { fixture.remove() }
        let userLine = #"{"timestamp":"2026-08-11T10:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"example: \"type\":\"task_started\""}}"#
        try FileHandle(forWritingTo: fixture.file).appendLine(userLine)

        XCTAssertTrue(CodexDesktopRolloutScanner().activeSessions(in: fixture.root).isEmpty)
    }

    func testLifecycleFromPreviousDesktopLaunchIsIgnored() throws {
        let fixture = try RolloutFixture(
            events: ["task_started"],
            source: "vscode",
            originator: "Codex Desktop"
        )
        defer { fixture.remove() }
        let oldDate = Date(timeIntervalSinceNow: -60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: fixture.file.path)

        let result = CodexDesktopRolloutScanner().activeSessions(
            in: fixture.root,
            desktopLaunchDate: Date()
        )
        XCTAssertTrue(result.isEmpty)
    }
}

private struct RolloutFixture {
    let root: URL
    let file: URL
    let sessionID = "019ff036-0203-7c80-bf6a-0b9ffe0bfcb2"

    init(events: [String], source: String, originator: String) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAwakeRolloutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        file = root.appendingPathComponent("rollout-\(sessionID).jsonl")

        var lines = [
            #"{"timestamp":"2026-08-11T10:00:00Z","type":"session_meta","payload":{"id":"\#(sessionID)","source":"\#(source)","originator":"\#(originator)"}}"#
        ]
        lines += events.enumerated().map { index, event in
            #"{"timestamp":"2026-08-11T10:00:0\#(index + 1)Z","type":"event_msg","payload":{"type":"\#(event)","turn_id":"turn-1"}}"#
        }
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private extension FileHandle {
    func appendLine(_ line: String) throws {
        try seekToEnd()
        try write(contentsOf: Data((line + "\n").utf8))
        try close()
    }
}
