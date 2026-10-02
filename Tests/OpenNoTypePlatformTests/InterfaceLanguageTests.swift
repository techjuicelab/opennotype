import XCTest
import OpenNoTypeCore
@testable import OpenNoType

final class InterfaceLanguageTests: XCTestCase {
    func testFreshInstallDefaultsToEnglishAndDoesNotWritePreferences() throws {
        let name = "OpenNoType.InterfaceLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(Preferences.load(from: defaults).interfaceLanguage, .english)
        XCTAssertNil(defaults.data(forKey: "preferences.v1"))
    }

    func testLegacyPreferencesKeepKoreanAndExistingProviderChoices() throws {
        let data = Data(#"{"provider":"groq","textProvider":"openRouter","targetLanguage":"Korean","retentionDays":7}"#.utf8)
        let value = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(value.interfaceLanguage, .korean)
        XCTAssertEqual(value.provider, .groq)
        XCTAssertEqual(value.effectiveTextProvider, .openRouter)
        XCTAssertEqual(value.targetLanguage, "Korean")
        XCTAssertEqual(value.retentionDays, 7)
    }

    func testExplicitLanguagesPersistWithoutChangingTranslationOrModels() throws {
        let name = "OpenNoType.InterfaceLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for language in AppLanguage.allCases {
            var value = Preferences()
            value.interfaceLanguage = language
            value.targetLanguage = "Japanese"
            value.textProvider = .openRouter
            value.textModels[AIProvider.openRouter.rawValue] = "custom/model"
            value.save(to: defaults)
            let restored = Preferences.load(from: defaults)
            XCTAssertEqual(restored.interfaceLanguage, language)
            XCTAssertEqual(restored.targetLanguage, "Japanese")
            XCTAssertEqual(restored.textModel, "custom/model")
        }
    }

    func testUnknownLanguageFallsBackWithoutDiscardingOtherFields() throws {
        let value = try JSONDecoder().decode(Preferences.self, from: Data(#"{"interfaceLanguage":"future","retentionDays":90}"#.utf8))
        XCTAssertEqual(value.interfaceLanguage, .english)
        XCTAssertEqual(value.retentionDays, 90)
    }

    @MainActor func testModelInitializesAndChangesLanguageWithoutChangingProcessingSettings() {
        let previous = AppLocalization.shared.language
        defer { AppLocalization.shared.language = previous }
        var preferences = Preferences()
        preferences.interfaceLanguage = .english
        preferences.useLocalTranscription = true
        var runtime = AppRuntime()
        runtime.readKey = { _ in nil }
        runtime.accessibilityPermitted = { false }
        runtime.secureInputActive = { false }
        runtime.microphonePermission = { .denied }
        runtime.hotkeyConflictWarnings = { _ in [] }
        let model = AppModel(runtime: runtime, startServices: false, preferences: preferences)
        XCTAssertEqual(AppLocalization.shared.language, .english)
        XCTAssertEqual(model.status, "Ready when you are")
        let target = model.preferences.targetLanguage
        model.preferences.interfaceLanguage = .korean
        XCTAssertEqual(model.status, "말할 준비가 되었어요")
        XCTAssertEqual(AppPage.settings.title, "설정")
        XCTAssertEqual(model.preferences.targetLanguage, target)
        model.preferences.interfaceLanguage = .english
        XCTAssertEqual(AppPage.settings.title, "Settings")
    }
}
