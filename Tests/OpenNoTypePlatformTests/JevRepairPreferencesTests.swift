import Foundation
import XCTest
import OpenNoTypeCore
@testable import OpenNoType

final class JevRepairPreferencesTests: KoreanPresentationTestCase {
    func testFreshSettingsRequireExplicitRepairAndLearningSelection() {
        let settings = Preferences()
        XCTAssertEqual(settings.decisionReviewMode, .off)
        XCTAssertFalse(settings.jevFeedbackLearningEnabled)
    }

    func testLegacyModesKeepTheirRawValuesWithoutOptingIntoRepairOrLearning() throws {
        for mode in [DecisionReviewMode.off, .observe, .protect] {
            let data = try JSONSerialization.data(withJSONObject: [
                "decisionReviewMode": mode.rawValue,
                "decisionProvider": "typesafe",
                "provider": "groq",
                "textProvider": "openRouter",
                "textModels": ["openRouter": "chosen-model"]
            ])
            let settings = try JSONDecoder().decode(Preferences.self, from: data)
            XCTAssertEqual(settings.decisionReviewMode, mode)
            XCTAssertFalse(settings.jevFeedbackLearningEnabled)
            XCTAssertEqual(settings.provider, .groq)
            XCTAssertEqual(settings.textProvider, .openRouter)
            XCTAssertEqual(settings.textModels["openRouter"], "chosen-model")
        }
    }

    func testExplicitRepairAndLearningRoundTripSeparatelyFromHistory() throws {
        var settings = Preferences()
        settings.decisionReviewMode = .repair
        settings.jevFeedbackLearningEnabled = true
        settings.historyEnabled = false
        settings.automaticLearningEnabled = false
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.decisionReviewMode, .repair)
        XCTAssertTrue(restored.jevFeedbackLearningEnabled)
        XCTAssertFalse(restored.historyEnabled)
        XCTAssertFalse(restored.automaticLearningEnabled)
    }

    func testMalformedLearningFieldDoesNotDiscardOtherSettings() throws {
        let settings = try JSONDecoder().decode(Preferences.self, from: Data(#"{"decisionReviewMode":"repair","decisionProvider":"typesafe","jevFeedbackLearningEnabled":"true","historyEnabled":false,"retentionDays":90}"#.utf8))
        XCTAssertEqual(settings.decisionReviewMode, .repair)
        XCTAssertFalse(settings.jevFeedbackLearningEnabled)
        XCTAssertFalse(settings.historyEnabled)
        XCTAssertEqual(settings.retentionDays, 90)
    }

    func testUnknownProviderRevokesRepairAndFeedbackLearning() throws {
        let settings = try JSONDecoder().decode(Preferences.self, from: Data(#"{"decisionReviewMode":"repair","decisionProvider":"unknown-service","jevFeedbackLearningEnabled":true,"jevNameCatalog":["Keep Local Name"]}"#.utf8))
        XCTAssertEqual(settings.decisionReviewMode, .off)
        XCTAssertFalse(settings.jevFeedbackLearningEnabled)
        XCTAssertEqual(settings.jevNameCatalog, ["Keep Local Name"])
    }

    func testModeLabelsDistinguishRepairFromHoldOnlyProtection() {
        XCTAssertEqual(DecisionReviewMode.repair.rawValue, "repair")
        XCTAssertEqual(DecisionReviewMode.observe.rawValue, "observe")
        XCTAssertEqual(DecisionReviewMode.protect.rawValue, "protect")
        XCTAssertEqual(DecisionReviewMode.repair.title, "입력 전 교정")
        XCTAssertEqual(DecisionReviewMode.protect.title, "입력 전 보호")
        XCTAssertEqual(DecisionReviewMode.observe.title, "입력 후 검토·학습")
    }

    func testDescriptionsMakeLateLearningAndFailedRepairHoldVisibleInBothLanguages() {
        for language in [AppLanguage.korean, .english] {
            AppLocalization.shared.language = language
            let observe = JevRepairPresentation.modeDetail(.observe)
            let repair = JevRepairPresentation.modeDetail(.repair)
            if language == .korean {
                XCTAssertTrue(observe.contains("이미 입력한 글은 바꾸지"))
                XCTAssertTrue(observe.contains("아래 학습을 켜면"))
                XCTAssertTrue(repair.contains("키 누락·실패·시간 초과"))
                XCTAssertTrue(repair.contains("자동 입력을 보류"))
            } else {
                XCTAssertEqual(DecisionReviewMode.repair.title, "Repair before typing")
                XCTAssertEqual(DecisionReviewMode.observe.title, "Review & learn after typing")
                XCTAssertTrue(observe.contains("already entered is never changed"))
                XCTAssertTrue(observe.contains("With learning enabled"))
                XCTAssertTrue(repair.contains("Missing keys, failures, timeouts"))
                XCTAssertTrue(repair.contains("hold automatic input"))
            }
        }
    }
}
