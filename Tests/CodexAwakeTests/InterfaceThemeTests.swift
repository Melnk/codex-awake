import CodexAwakeCore
import SwiftUI
import XCTest

@testable import CodexAwakeApp

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
}
