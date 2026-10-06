import Foundation
import XCTest
import OpenNoTypeCore
@testable import OpenNoType

final class TranslationProtectionPreferencesTests: KoreanPresentationTestCase {
    func testFreshSettingsDoNotOptIntoTranslationReview() {
        XCTAssertFalse(Preferences().translationProtectionEnabled)
    }

    func testLegacyReviewModesDoNotOptIntoAdditionalTranslationTransmission() throws {
        for mode in DecisionReviewMode.allCases {
            let data = try JSONSerialization.data(withJSONObject: [
                "decisionReviewMode": mode.rawValue,
                "decisionProvider": "typesafe",
                "provider": "groq",
                "textProvider": "openRouter",
                "transcriptionModels": ["groq": "chosen-speech-model"],
                "textModels": ["openRouter": "chosen-text-model"],
                "dictationOutputLanguage": "japanese"
            ])
            let settings = try JSONDecoder().decode(Preferences.self, from: data)
            XCTAssertFalse(settings.translationProtectionEnabled)
            XCTAssertEqual(settings.decisionReviewMode, mode)
            XCTAssertEqual(settings.decisionProvider, .typeSafe)
            XCTAssertEqual(settings.provider, .groq)
            XCTAssertEqual(settings.textProvider, .openRouter)
            XCTAssertEqual(settings.transcriptionModels["groq"], "chosen-speech-model")
            XCTAssertEqual(settings.textModels["openRouter"], "chosen-text-model")
            XCTAssertEqual(settings.dictationOutputLanguage, .japanese)
            XCTAssertFalse(settings.recoveryState.requiresRecovery)
        }
    }

    func testExplicitTranslationOptInRoundTripsWithoutChangingModeOrConnections() throws {
        for mode in DecisionReviewMode.allCases {
            var settings = Preferences()
            settings.decisionReviewMode = mode
            settings.translationProtectionEnabled = true
            settings.decisionProvider = .typeSafe
            settings.provider = .groq
            settings.textProvider = .openRouter
            settings.transcriptionModels["groq"] = "chosen-speech-model"
            settings.textModels["openRouter"] = "chosen-text-model"
            settings.dictationOutputLanguage = .japanese
            settings.historyEnabled = false

            let encoded = try JSONEncoder().encode(settings)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertEqual(object["translationProtectionEnabled"] as? Bool, true)
            let restored = try JSONDecoder().decode(Preferences.self, from: encoded)
            XCTAssertTrue(restored.translationProtectionEnabled)
            XCTAssertEqual(restored.decisionReviewMode, mode, "Opting in must not select Protect automatically")
            XCTAssertEqual(restored.decisionProvider, .typeSafe)
            XCTAssertEqual(restored.provider, .groq)
            XCTAssertEqual(restored.textProvider, .openRouter)
            XCTAssertEqual(restored.transcriptionModels, settings.transcriptionModels)
            XCTAssertEqual(restored.textModels, settings.textModels)
            XCTAssertEqual(restored.dictationOutputLanguage, .japanese)
            XCTAssertFalse(restored.historyEnabled)
        }
    }

    func testMalformedOptInIsDisabledAndRequiresRecoveryWithoutDiscardingOtherSettings() throws {
        let malformedValues: [Any] = ["true", 1, NSNull()]
        for value in malformedValues {
            let data = try JSONSerialization.data(withJSONObject: [
                "translationProtectionEnabled": value,
                "decisionReviewMode": "protect",
                "decisionProvider": "typesafe",
                "historyEnabled": false,
                "retentionDays": 90
            ])
            let settings = try JSONDecoder().decode(Preferences.self, from: data)
            XCTAssertFalse(settings.translationProtectionEnabled)
            XCTAssertEqual(settings.recoveryState, .partiallyRecovered(["translationProtectionEnabled"]))
            XCTAssertEqual(settings.decisionReviewMode, .protect)
            XCTAssertEqual(settings.decisionProvider, .typeSafe)
            XCTAssertFalse(settings.historyEnabled)
            XCTAssertEqual(settings.retentionDays, 90)
        }
    }

    func testUnknownReviewDestinationRevokesTranslationOptIn() throws {
        let data = Data(#"{"translationProtectionEnabled":true,"decisionReviewMode":"protect","decisionProvider":"unknown-service","provider":"groq","textProvider":"openRouter","textModels":{"openRouter":"chosen-text-model"},"dictationOutputLanguage":"japanese","historyEnabled":false}"#.utf8)
        let settings = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertFalse(settings.translationProtectionEnabled)
        XCTAssertEqual(settings.decisionReviewMode, .off)
        XCTAssertEqual(settings.provider, .groq)
        XCTAssertEqual(settings.textProvider, .openRouter)
        XCTAssertEqual(settings.textModels["openRouter"], "chosen-text-model")
        XCTAssertEqual(settings.dictationOutputLanguage, .japanese)
        XCTAssertFalse(settings.historyEnabled)
        XCTAssertEqual(settings.recoveryState, .partiallyRecovered(["decisionProvider"]))
    }
}
