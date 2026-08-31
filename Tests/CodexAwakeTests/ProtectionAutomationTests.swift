import Foundation
import XCTest

@testable import CodexAwakeCore

final class ProtectionAutomationTests: XCTestCase {
    private let engine = ProtectionAutomationEngine()
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testCodexPresenceTriggerProtectsWithoutActiveTask() {
        // Arrange
        let rules = ProtectionAutomationRules(trigger: .codexRunning)
        let context = ProtectionAutomationContext(
            codexIsRunning: true,
            activeTaskCount: 0,
            activeTaskProjectPaths: [],
            isOnExternalPower: false
        )

        // Act
        let decision = engine.evaluate(rules: rules, context: context)

        // Assert
        XCTAssertTrue(decision.shouldProtect)
        XCTAssertTrue(decision.blockers.isEmpty)
    }

    func testAutoStopRequiresActiveTaskEvenWhileCodexRuns() {
        // Arrange
        let rules = ProtectionAutomationRules(
            trigger: .codexRunning,
            automaticallyStopsAfterTasks: true
        )
        let context = ProtectionAutomationContext(
            codexIsRunning: true,
            activeTaskCount: 0,
            activeTaskProjectPaths: [],
            isOnExternalPower: true
        )

        // Act
        let decision = engine.evaluate(rules: rules, context: context)

        // Assert
        XCTAssertFalse(decision.shouldProtect)
        XCTAssertEqual(decision.blockers, [.noActiveTasks])
    }

    func testExternalPowerRuleBlocksBatteryAndAllowsCharger() {
        // Arrange
        let rules = ProtectionAutomationRules(trigger: .activeTasks, requiresExternalPower: true)
        let battery = ProtectionAutomationContext(
            codexIsRunning: true,
            activeTaskCount: 1,
            activeTaskProjectPaths: ["/Projects/A"],
            isOnExternalPower: false
        )
        var charger = battery
        charger.isOnExternalPower = true

        // Act
        let batteryDecision = engine.evaluate(rules: rules, context: battery)
        let chargerDecision = engine.evaluate(rules: rules, context: charger)

        // Assert
        XCTAssertEqual(batteryDecision.blockers, [.externalPowerRequired])
        XCTAssertTrue(chargerDecision.shouldProtect)
    }

    func testOvernightScheduleUsesPreviousSelectedWeekdayAfterMidnight() throws {
        // Arrange
        let schedule = ProtectionSchedule(
            isEnabled: true,
            startMinute: 22 * 60,
            endMinute: 7 * 60,
            weekdays: [.monday]
        )
        let mondayLate = try date(year: 2026, month: 8, day: 17, hour: 23)
        let tuesdayEarly = try date(year: 2026, month: 8, day: 18, hour: 2)
        let tuesdayLate = try date(year: 2026, month: 8, day: 18, hour: 8)

        // Act / Assert
        XCTAssertTrue(schedule.contains(mondayLate, calendar: calendar))
        XCTAssertTrue(schedule.contains(tuesdayEarly, calendar: calendar))
        XCTAssertFalse(schedule.contains(tuesdayLate, calendar: calendar))
    }

    func testSelectedProjectMatchesExactFolderAndDescendantOnly() {
        // Arrange
        let rules = ProtectionAutomationRules(
            trigger: .activeTasks,
            selectedProjectPaths: ["/Projects/CodexAwake"]
        )

        // Act
        let descendant = engine.evaluate(
            rules: rules,
            context: .init(
                codexIsRunning: true,
                activeTaskCount: 1,
                activeTaskProjectPaths: ["/Projects/CodexAwake/Sources"],
                isOnExternalPower: true
            )
        )
        let similarPrefix = engine.evaluate(
            rules: rules,
            context: .init(
                codexIsRunning: true,
                activeTaskCount: 1,
                activeTaskProjectPaths: ["/Projects/CodexAwake-copy"],
                isOnExternalPower: true
            )
        )

        // Assert
        XCTAssertTrue(descendant.shouldProtect)
        XCTAssertEqual(similarPrefix.blockers, [.noSelectedProjectActive])
    }

    func testProfilesHaveDistinctSafePowerPolicies() {
        XCTAssertTrue(ProtectionProfile.preset(.work).power.preventDisplaySleep)
        XCTAssertFalse(ProtectionProfile.preset(.nightTask).power.preventDisplaySleep)
        XCTAssertTrue(ProtectionProfile.preset(.nightTask).rules.requiresExternalPower)
        XCTAssertEqual(ProtectionProfile.preset(.nightTask).rules.trigger, .codexRunning)
        XCTAssertFalse(ProtectionProfile.preset(.nightTask).rules.automaticallyStopsAfterTasks)
        XCTAssertFalse(ProtectionProfile.preset(.closedLid).rules.requiresExternalPower)
        XCTAssertEqual(ProtectionProfile.preset(.closedLid).rules.trigger, .codexRunning)
        XCTAssertFalse(ProtectionProfile.preset(.closedLid).rules.automaticallyStopsAfterTasks)
        XCTAssertTrue(ProtectionProfile.preset(.closedLid).closedLidEnabled)
        XCTAssertEqual(ProtectionProfile.preset(.presentation).rules.trigger, .codexRunning)
    }

    func testAutomationDemandOverridesLegacyPresenceAndStillHonorsMasterSwitch() async {
        // Arrange
        let power = MockPowerAssertionController()
        let coordinator = AwakeCoordinator(power: power)
        await coordinator.setCodexDesktopRunning(true)

        // Act
        await coordinator.setAutomationDemand(false)
        await coordinator.setAutoKeepAwake(false)
        await coordinator.setAutomationDemand(true)

        // Assert
        let held = await power.assertionIsHeld()
        XCTAssertFalse(held)
    }

    func testStatisticsCountTransitionsAndPersistWithoutCountingRestartDowntime() async throws {
        // Arrange
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAwakeAutomationTests-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("statistics.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProtectionStatisticsStore(fileURL: file)
        let start = Date(timeIntervalSince1970: 1_000)

        // Act
        _ = try await store.record(isActive: true, at: start)
        let active = try await store.record(isActive: true, at: start.addingTimeInterval(30))
        let ended = try await store.record(isActive: false, at: start.addingTimeInterval(90))
        let reloaded = try await ProtectionStatisticsStore(fileURL: file).load()

        // Assert
        XCTAssertEqual(active.sleepPreventionSessions, 1)
        XCTAssertEqual(active.protectedSeconds, 30, accuracy: 0.001)
        XCTAssertEqual(ended.protectedSeconds, 90, accuracy: 0.001)
        XCTAssertEqual(reloaded.protectedSeconds, 90, accuracy: 0.001)
        XCTAssertNil(reloaded.activeSince)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testCorruptStatisticsAreReportedInsteadOfSilentlyReset() async throws {
        // Arrange
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAwakeAutomationTests-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("statistics.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: file)
        let store = ProtectionStatisticsStore(fileURL: file)

        // Act / Assert
        do {
            _ = try await store.load()
            XCTFail("Corrupt statistics must produce a recoverable error")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }
}
