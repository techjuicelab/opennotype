import Foundation
import XCTest
import OpenNoTypeCore
@testable import OpenNoType

final class TranslationRefinementPreferencesTests: XCTestCase {
    func testFreshAndLegacyPreferencesDoNotAddTranslationRequests() throws {
        XCTAssertFalse(Preferences().translationRefinementEnabled)
        for mode in DecisionReviewMode.allCases {
            let data = try JSONSerialization.data(withJSONObject: [
                "decisionReviewMode": mode.rawValue,
                "translationProtectionEnabled": true,
                "decisionProvider": "typesafe",
                "provider": "groq",
                "textProvider": "openRouter",
                "textModels": ["openRouter": "chosen-text-model"],
                "dictationOutputLanguage": "japanese"
            ])
            let settings = try JSONDecoder().decode(Preferences.self, from: data)
            XCTAssertFalse(settings.translationRefinementEnabled)
            XCTAssertTrue(settings.translationProtectionEnabled)
            XCTAssertEqual(settings.decisionReviewMode, mode)
            XCTAssertEqual(settings.decisionProvider, .typeSafe)
            XCTAssertEqual(settings.provider, .groq)
            XCTAssertEqual(settings.textProvider, .openRouter)
            XCTAssertEqual(settings.textModel, "chosen-text-model")
            XCTAssertEqual(settings.dictationOutputLanguage, .japanese)
            XCTAssertFalse(settings.recoveryState.requiresRecovery)
        }
    }

    func testRefinementOptInRoundTripsIndependentlyOfJevAndModelSelection() throws {
        for refinement in [false, true] {
            for protection in [false, true] {
                for mode in DecisionReviewMode.allCases {
                    var settings = Preferences()
                    settings.translationRefinementEnabled = refinement
                    settings.translationProtectionEnabled = protection
                    settings.decisionReviewMode = mode
                    settings.provider = .groq
                    settings.textProvider = .openRouter
                    settings.textModels["openRouter"] = "chosen-text-model"
                    settings.improvementModels["openRouter"] = "separate-alternative-model"
                    settings.decisionProvider = .typeSafe
                    settings.dictationOutputLanguage = .japanese
                    settings.historyEnabled = false

                    let encoded = try JSONEncoder().encode(settings)
                    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
                    XCTAssertEqual(object["translationRefinementEnabled"] as? Bool, refinement)
                    let restored = try JSONDecoder().decode(Preferences.self, from: encoded)
                    XCTAssertEqual(restored.translationRefinementEnabled, refinement)
                    XCTAssertEqual(restored.translationProtectionEnabled, protection)
                    XCTAssertEqual(restored.decisionReviewMode, mode)
                    XCTAssertEqual(restored.decisionProvider, .typeSafe)
                    XCTAssertEqual(restored.provider, .groq)
                    XCTAssertEqual(restored.textProvider, .openRouter)
                    XCTAssertEqual(restored.textModels, settings.textModels)
                    XCTAssertEqual(restored.improvementModels, settings.improvementModels)
                    XCTAssertEqual(restored.dictationOutputLanguage, .japanese)
                    XCTAssertFalse(restored.historyEnabled)
                }
            }
        }
    }

    func testMalformedOptInIsDisabledWithoutDiscardingOtherSettings() throws {
        for malformed: Any in ["true", 1, NSNull()] {
            let data = try JSONSerialization.data(withJSONObject: [
                "translationRefinementEnabled": malformed,
                "translationProtectionEnabled": true,
                "decisionReviewMode": "protect",
                "decisionProvider": "typesafe",
                "historyEnabled": false,
                "retentionDays": 90
            ])
            let settings = try JSONDecoder().decode(Preferences.self, from: data)
            XCTAssertFalse(settings.translationRefinementEnabled)
            XCTAssertEqual(settings.recoveryState, .partiallyRecovered(["translationRefinementEnabled"]))
            XCTAssertTrue(settings.translationProtectionEnabled)
            XCTAssertEqual(settings.decisionReviewMode, .protect)
            XCTAssertEqual(settings.decisionProvider, .typeSafe)
            XCTAssertFalse(settings.historyEnabled)
            XCTAssertEqual(settings.retentionDays, 90)
        }
    }

    func testCorruptedOptInCannotOverwriteStoredSettingsUntilExplicitRecovery() throws {
        let name = "OpenNoTypeRefinementPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let original = Data(#"{"translationRefinementEnabled":"true","provider":"groq","textProvider":"openRouter","historyEnabled":false}"#.utf8)
        defaults.set(original, forKey: "preferences.v1")
        var settings = Preferences.load(from: defaults)
        settings.appearance = "dark"
        XCTAssertFalse(settings.translationRefinementEnabled)
        XCTAssertFalse(settings.save(to: defaults))
        XCTAssertEqual(defaults.data(forKey: "preferences.v1"), original)
        let accepted = try XCTUnwrap(settings.acceptRecovery(to: defaults))
        XCTAssertFalse(accepted.translationRefinementEnabled)
        XCTAssertEqual(accepted.provider, .groq)
        XCTAssertEqual(accepted.textProvider, .openRouter)
        XCTAssertFalse(accepted.historyEnabled)
        XCTAssertEqual(accepted.appearance, "dark")
        XCTAssertEqual(defaults.data(forKey: Preferences.recoveryOriginalKey), original)
    }
}
