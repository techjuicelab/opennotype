import AppKit
import XCTest
import OpenNoTypeCore
@testable import OpenNoType

@MainActor
final class SettingsNavigationTests: XCTestCase {
    private func makeModel() -> AppModel {
        _ = NSApplication.shared
        var runtime = AppRuntime()
        runtime.readKey = { _ in XCTFail("Navigation must not read credentials"); return nil }
        runtime.readDecisionKey = { _ in XCTFail("Navigation must not read credentials"); return nil }
        runtime.accessibilityPermitted = { false }
        runtime.microphonePermission = { .notDetermined }
        runtime.hotkeyConflictWarnings = { _ in [] }
        return AppModel(runtime: runtime, startServices: false, preferences: Preferences(), useCachedKeys: true)
    }

    func testCategoryTabsFitTheDefaultSettingsPageInBothLanguages() {
        let previous = AppLocalization.shared.language
        defer { AppLocalization.shared.language = previous }
        // Segments share the width of the longest label; 24 pt covers each segment's padding.
        let available = 1_120 - AppLayout.sidebarWidth - 2 * AppLayout.pageInset
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        for language in [AppLanguage.english, .korean] {
            AppLocalization.shared.language = language
            let widest = SettingsSection.allCases.map { ($0.tabTitle as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            XCTAssertLessThanOrEqual(CGFloat(SettingsSection.allCases.count) * (widest + 24), available, "\(language)")
            XCTAssertTrue(SettingsSection.allCases.allSatisfy { !$0.tabTitle.isEmpty })
        }
    }

    func testPermissionEntryReplacesStaleToolAndOpensItsOwningCategory() {
        let model = makeModel()
        model.settingsSection = .advanced
        model.settingsDetail = .comparison
        model.page = .home
        var opens = 0
        model.showManager = { opens += 1 }

        model.openSettings(SettingsDetail.permissions)

        XCTAssertEqual(model.page, .settings)
        XCTAssertEqual(model.settingsSection, .general)
        XCTAssertEqual(model.settingsDetail, .permissions)
        XCTAssertEqual(opens, 1)
        XCTAssertFalse(model.inputTestArmed, "Opening a setup screen must not arm an insertion")
        XCTAssertEqual(model.phase, .idle)
    }

    func testConnectionAndReviewBehaviorHaveDifferentOwners() {
        let model = makeModel()
        model.openSettings(SettingsDetail.reviewConnection)
        XCTAssertEqual(model.settingsSection, .connection)
        XCTAssertEqual(model.settingsDetail, .reviewConnection)

        model.openSettings(SettingsDetail.jev)
        XCTAssertEqual(model.settingsSection, .dictation)
        XCTAssertEqual(model.settingsDetail, .jev)
        XCTAssertEqual(model.preferences.decisionReviewMode, Preferences().decisionReviewMode)
        XCTAssertEqual(model.preferences.decisionProvider, Preferences().decisionProvider)
    }

    func testCategoryEntryClearsPreviousDetailAndKeepsInputTestDisarmed() {
        let model = makeModel()
        model.openSettings(SettingsDetail.typingTest)
        XCTAssertEqual(model.settingsSection, .general)
        XCTAssertFalse(model.inputTestArmed)

        model.openSettings(SettingsSection.connection)

        XCTAssertNil(model.settingsDetail)
        XCTAssertEqual(model.settingsSection, .connection)
        XCTAssertEqual(model.page, .settings)
        XCTAssertFalse(model.inputTestArmed)
    }
}
