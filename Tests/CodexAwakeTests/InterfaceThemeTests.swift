import CodexAwakeCore
import SwiftUI
import XCTest

@testable import CodexAwakeApp

import Combine

final class InterfaceThemeTests: XCTestCase {
    func testДоступныСистемнаяСветлаяИТёмнаяТемы() {
        // Arrange / Act
        let themes = InterfaceTheme.allCases

        // Assert
        XCTAssertEqual(themes, [.system, .light, .dark])
        XCTAssertNil(InterfaceTheme.system.colorScheme)
        XCTAssertNotNil(InterfaceTheme.light.colorScheme)
        XCTAssertNotNil(InterfaceTheme.dark.colorScheme)
    }

    func testНазванияТемЛокализованы() {
        // Arrange / Act / Assert
        XCTAssertEqual(InterfaceTheme.system.title(in: .english), "System")
        XCTAssertEqual(InterfaceTheme.system.title(in: .russian), "Системная")
        XCTAssertEqual(InterfaceTheme.light.title(in: .russian), "Светлая")
        XCTAssertEqual(InterfaceTheme.dark.title(in: .russian), "Тёмная")
    }
}

@MainActor
final class OnboardingRenderingTests: XCTestCase {
    func testОнбордингРендеритсяНаШирокомИКомпактномОкне() throws {
        // Arrange
        let suiteName = "CodexAwakeOnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(preferences: UserDefaultsAppPreferences(defaults: defaults))
        let sizes = [CGSize(width: 1_080, height: 720), CGSize(width: 660, height: 540)]

        // Act / Assert
        for size in sizes {
            let content = OnboardingView()
                .environmentObject(model)
                .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(size)
            let image = try XCTUnwrap(renderer.nsImage)

            XCTAssertEqual(image.size.width, size.width, accuracy: 1)
            XCTAssertEqual(image.size.height, size.height, accuracy: 1)
        }
    }

    func testCockpitРендеритсяВШирокойИАдаптивнойКомпоновке() throws {
        // Arrange
        let suiteName = "CodexAwakeCockpitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsAppPreferences(defaults: defaults)
        preferences.setCompletedOnboardingVersion(AppBuildInfo.onboardingVersion)
        let model = AppModel(preferences: preferences)
        let sizes = [CGSize(width: 1_080, height: 720), CGSize(width: 660, height: 540)]

        // Act / Assert
        for size in sizes {
            let content = CockpitView()
                .environmentObject(model)
                .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(size)
            let image = try XCTUnwrap(renderer.nsImage)

            XCTAssertEqual(image.size.width, size.width, accuracy: 1)
            XCTAssertEqual(image.size.height, size.height, accuracy: 1)
        }
    }
}

@MainActor
final class OnboardingStateTests: XCTestCase {
    func testВложенныеХранилищаНеПерерисовываютВесьCockpit() throws {
        // Arrange
        let suiteName = "CodexAwakeChatIsolationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(preferences: UserDefaultsAppPreferences(defaults: defaults))
        var modelUpdateCount = 0
        let observation = model.objectWillChange.sink { modelUpdateCount += 1 }

        // Act
        model.chat.createConversation(workspacePath: "/tmp")
        model.chat.conversations[0].threadId = "thread-a"
        model.chat.updateAgentMessage(threadId: "thread-a", itemId: "answer-a", delta: "Live response")
        var diagnostics = DiagnosticsSnapshot()
        diagnostics.appVersion = "performance-check"
        model.diagnostics.snapshot = diagnostics

        // Assert
        XCTAssertEqual(modelUpdateCount, 0)
        withExtendedLifetime(observation) {}
    }

    func testОнбордингПоказываетсяОдинРазДляТекущейВерсии() throws {
        // Arrange
        let suiteName = "CodexAwakeOnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsAppPreferences(defaults: defaults)
        let firstModel = AppModel(preferences: preferences)

        // Act
        XCTAssertFalse(firstModel.firstRunAcknowledged)
        firstModel.acknowledgeFirstRun()
        let relaunchedModel = AppModel(preferences: preferences)
        relaunchedModel.showOnboarding()

        // Assert
        XCTAssertEqual(preferences.completedOnboardingVersion, AppBuildInfo.onboardingVersion)
        XCTAssertFalse(relaunchedModel.firstRunAcknowledged)
        relaunchedModel.acknowledgeFirstRun()
        XCTAssertTrue(relaunchedModel.firstRunAcknowledged)
    }

    func testСтарыйПрофильЗакрытойКрышкиМигрируетНаНадёжноеПрисутствиеCodex() throws {
        // Arrange
        let suiteName = "CodexAwakeClosedLidMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsAppPreferences(defaults: defaults)
        preferences.setProtectionProfileID(.closedLid)
        preferences.setAutomationRules(
            ProtectionAutomationRules(
                trigger: .activeTasks,
                requiresExternalPower: true,
                automaticallyStopsAfterTasks: true
            )
        )
        preferences.setAutomationSchemaVersion(1)

        // Act
        let model = AppModel(preferences: preferences)

        // Assert
        XCTAssertFalse(model.automationRules.requiresExternalPower)
        XCTAssertEqual(model.automationRules.trigger, .codexRunning)
        XCTAssertFalse(model.automationRules.automaticallyStopsAfterTasks)
        XCTAssertFalse(preferences.automationRules.requiresExternalPower)
        XCTAssertEqual(preferences.automationRules.trigger, .codexRunning)
        XCTAssertFalse(preferences.automationRules.automaticallyStopsAfterTasks)
        XCTAssertEqual(preferences.automationSchemaVersion, 4)
    }

    func testСтарыйНочнойПрофильМигрируетНаНадёжноеПрисутствиеCodex() throws {
        // Arrange
        let suiteName = "CodexAwakeNightMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsAppPreferences(defaults: defaults)
        preferences.setProtectionProfileID(.nightTask)
        preferences.setAutomationRules(
            ProtectionAutomationRules(
                trigger: .activeTasks,
                requiresExternalPower: true,
                automaticallyStopsAfterTasks: true
            )
        )
        preferences.setAutomationSchemaVersion(3)

        // Act
        let model = AppModel(preferences: preferences)

        // Assert
        XCTAssertEqual(model.automationRules.trigger, .codexRunning)
        XCTAssertFalse(model.automationRules.automaticallyStopsAfterTasks)
        XCTAssertTrue(model.automationRules.requiresExternalPower)
        XCTAssertEqual(preferences.automationSchemaVersion, 4)
    }

    func testURLАвтоматизацииПрименяетПрофиль() throws {
        // Arrange
        let suiteName = "CodexAwakeAutomationURLTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(preferences: UserDefaultsAppPreferences(defaults: defaults))
        let url = try XCTUnwrap(URL(string: "codexawake://profile/night-task"))

        // Act
        model.handleAutomationURL(url)

        // Assert
        XCTAssertEqual(model.selectedProtectionProfile, .nightTask)
        XCTAssertTrue(model.automationRules.requiresExternalPower)
        XCTAssertTrue(model.automationRules.schedule.isEnabled)
    }
}
