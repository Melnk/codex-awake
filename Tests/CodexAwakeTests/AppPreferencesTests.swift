import Foundation
import XCTest

@testable import CodexAwakeCore

final class AppPreferencesTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "CodexAwakeTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = .standard
        suiteName = ""
        try super.tearDownWithError()
    }

    func testDefaultsProtectCodexWithoutRequiringPriorConfiguration() {
        // Arrange
        let preferences = UserDefaultsAppPreferences(defaults: defaults)

        // Act
        let autoKeepAwake = preferences.autoKeepAwake
        let keepAwakeForDesktop = preferences.keepAwakeForCodexDesktop

        // Assert
        XCTAssertTrue(autoKeepAwake)
        XCTAssertTrue(keepAwakeForDesktop)
        XCTAssertFalse(preferences.closedLidProtectionEnabled)
    }

    func testAllPreferencesRoundTripThroughInjectedStore() {
        // Arrange
        let preferences = UserDefaultsAppPreferences(defaults: defaults)

        // Act
        preferences.setAutoKeepAwake(false)
        preferences.setKeepAwakeForCodexDesktop(false)
        preferences.setClosedLidProtectionEnabled(true)
        preferences.setFirstRunAcknowledged(true)
        preferences.setInterfaceTheme("dark")
        preferences.setAppLanguage("russian")
        preferences.setWorkspacePath("/tmp/project")

        // Assert
        XCTAssertFalse(preferences.autoKeepAwake)
        XCTAssertFalse(preferences.keepAwakeForCodexDesktop)
        XCTAssertTrue(preferences.closedLidProtectionEnabled)
        XCTAssertTrue(preferences.firstRunAcknowledged)
        XCTAssertEqual(preferences.interfaceTheme, "dark")
        XCTAssertEqual(preferences.appLanguage, "russian")
        XCTAssertEqual(preferences.workspacePath, "/tmp/project")
    }

    func testRemovingWorkspaceDoesNotChangeOtherPreferences() {
        // Arrange
        let preferences = UserDefaultsAppPreferences(defaults: defaults)
        preferences.setWorkspacePath("/tmp/project")
        preferences.setInterfaceTheme("dark")

        // Act
        preferences.setWorkspacePath(nil)

        // Assert
        XCTAssertNil(preferences.workspacePath)
        XCTAssertEqual(preferences.interfaceTheme, "dark")
    }
}
