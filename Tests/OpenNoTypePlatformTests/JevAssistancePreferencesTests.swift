import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

final class JevAssistancePreferencesTests: XCTestCase {
    func testFreshAndLegacySettingsDoNotOptIntoAdditionalRequests() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"provider":"groq","textProvider":"openRouter","decisionReviewMode":"protect","decisionProvider":"typesafe","historyEnabled":false}"#.utf8))
        for settings in [Preferences(), old] {
            XCTAssertFalse(settings.jevDetailedReviewEnabled)
            XCTAssertFalse(settings.jevEconomyEnabled)
            XCTAssertFalse(settings.jevAutomaticImprovementEnabled)
            XCTAssertFalse(settings.jevClarifyEditsEnabled)
            XCTAssertFalse(settings.jevReRecognitionEnabled)
            XCTAssertTrue(settings.jevNameCatalog.isEmpty)
        }
        XCTAssertEqual(old.provider, .groq)
        XCTAssertEqual(old.textProvider, .openRouter)
        XCTAssertEqual(old.decisionReviewMode, .protect)
        XCTAssertEqual(old.decisionProvider, .typeSafe)
        XCTAssertFalse(old.historyEnabled)
    }

    func testExplicitSettingsRoundTripWithoutChangingAutomaticReviewOrModels() throws {
        var original = Preferences()
        original.decisionReviewMode = .off
        original.textModels = ["openRouter": "chosen-model"]
        original.jevDetailedReviewEnabled = true
        original.jevEconomyEnabled = true
        original.jevAutomaticImprovementEnabled = true
        original.jevClarifyEditsEnabled = true
        original.jevReRecognitionEnabled = true
        original.jevNameCatalog = ["OpenRouter", "Project One"]
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(original))
        XCTAssertTrue(decoded.jevDetailedReviewEnabled)
        XCTAssertTrue(decoded.jevEconomyEnabled)
        XCTAssertTrue(decoded.jevAutomaticImprovementEnabled)
        XCTAssertTrue(decoded.jevClarifyEditsEnabled)
        XCTAssertTrue(decoded.jevReRecognitionEnabled)
        XCTAssertEqual(decoded.jevNameCatalog, original.jevNameCatalog)
        XCTAssertEqual(decoded.decisionReviewMode, .off)
        XCTAssertEqual(decoded.textModels, original.textModels)
    }

    func testMalformedFieldsDefaultIndividuallyWithoutLosingIndependentOptIns() throws {
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(#"{"jevDetailedReviewEnabled":"true","jevEconomyEnabled":1,"jevAutomaticImprovementEnabled":true,"jevClarifyEditsEnabled":null,"jevReRecognitionEnabled":true,"jevNameCatalog":["Valid",4],"retentionDays":90}"#.utf8))
        XCTAssertFalse(decoded.jevDetailedReviewEnabled)
        XCTAssertFalse(decoded.jevEconomyEnabled)
        XCTAssertTrue(decoded.jevAutomaticImprovementEnabled)
        XCTAssertFalse(decoded.jevClarifyEditsEnabled)
        XCTAssertTrue(decoded.jevReRecognitionEnabled)
        XCTAssertTrue(decoded.jevNameCatalog.isEmpty)
        XCTAssertEqual(decoded.retentionDays, 90)
    }

    func testUnknownDestinationRevokesAdditionalAutomaticTransmission() throws {
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(#"{"decisionProvider":"future-service","decisionReviewMode":"protect","jevDetailedReviewEnabled":true,"jevEconomyEnabled":true,"jevAutomaticImprovementEnabled":true,"jevClarifyEditsEnabled":true,"jevReRecognitionEnabled":true,"jevNameCatalog":["Keep Local Name"]}"#.utf8))
        XCTAssertEqual(decoded.decisionReviewMode, .off)
        XCTAssertFalse(decoded.jevDetailedReviewEnabled)
        XCTAssertFalse(decoded.jevEconomyEnabled)
        XCTAssertFalse(decoded.jevAutomaticImprovementEnabled)
        XCTAssertFalse(decoded.jevClarifyEditsEnabled)
        XCTAssertFalse(decoded.jevReRecognitionEnabled)
        XCTAssertEqual(decoded.jevNameCatalog, ["Keep Local Name"])
    }

    func testCatalogNormalizesDistinctNamesAndRejectsHiddenControlCharacters() throws {
        var settings = Preferences()
        settings.jevNameCatalog = [" OpenRouter ", "openrouter", "", "Cafe\u{301}", "Café", "Two Words", "한글 프로젝트", "C++", "bad\nname", "bad\tname", "A", "https://example.com", "<instruction>", String(repeating: "가", count: 101)]
        XCTAssertEqual(settings.jevNameCatalog, ["OpenRouter", "Café", "Two Words", "한글 프로젝트", "C++"])
        settings.jevNameCatalog.append(" Project Two ")
        XCTAssertEqual(settings.jevNameCatalog.last, "Project Two")
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.jevNameCatalog, settings.jevNameCatalog)
    }

    func testCatalogLimitCountsValidNamesAndAcceptsOneHundredCharacters() throws {
        let boundary = String(repeating: "가", count: 100)
        var settings = Preferences()
        settings.jevNameCatalog = ["", boundary] + (0..<80).map { "Project \($0)" }
        XCTAssertEqual(settings.jevNameCatalog.count, 64)
        XCTAssertEqual(settings.jevNameCatalog.first, boundary)
        XCTAssertEqual(settings.jevNameCatalog.last, "Project 62")
        let payload = try JSONSerialization.data(withJSONObject: ["jevNameCatalog": [" Name ", "name", "bad\nname"]])
        let decoded = try JSONDecoder().decode(Preferences.self, from: payload)
        XCTAssertEqual(decoded.jevNameCatalog, ["Name"])
    }
}

final class JevAssistancePresentationTests: KoreanPresentationTestCase {
    func testEditingAssessmentMakesUncertaintyVisibleWithoutAccuracyClaims() {
        XCTAssertTrue(JevAssistancePresentation.editAssessment(.ambiguous).contains("모호"))
        XCTAssertTrue(JevAssistancePresentation.editAssessment(.noApplicableEdit).contains("찾지 못했습니다"))
        XCTAssertTrue(JevAssistancePresentation.editAssessment(.clear).contains("확인"))
        for choice in DecisionEditChoice.allCases {
            XCTAssertFalse(JevAssistancePresentation.editAssessment(choice).contains("%"))
        }
    }

    func testTranscriptComparisonDoesNotDeclareAnAlternativeCorrect() {
        XCTAssertTrue(JevAssistancePresentation.transcriptAssessment(.meaningfulDifference).contains("실제 발화"))
        XCTAssertTrue(JevAssistancePresentation.transcriptAssessment(.uncertain).contains("직접 확인"))
        XCTAssertTrue(JevAssistancePresentation.transcriptAssessment(.equivalent).contains("보입니다"))
        for choice in DecisionTranscriptChoice.allCases {
            XCTAssertFalse(JevAssistancePresentation.transcriptAssessment(choice).contains("%"))
        }
    }
}
