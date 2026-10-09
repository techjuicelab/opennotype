import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

final class PromptHistoryReviewSummaryTests: KoreanPresentationTestCase {
    func testLegacyPromptHistoryDoesNotAcquireAnAssumedReviewState() throws {
        let entry = HistoryEntry(mode: .prompt, originalText: "알림 기능의 도입은 미정입니다.",
            resultText: "알림 기능의 도입 여부는 아직 미정입니다.", provider: .openRouter)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        json.removeValue(forKey: "promptReviewSummary")
        let restored = try JSONDecoder().decode(HistoryEntry.self, from: JSONSerialization.data(withJSONObject: json))

        XCTAssertNil(restored.promptReviewSummary)
        XCTAssertEqual(restored.id, entry.id)
        XCTAssertEqual(restored.originalText, entry.originalText)
        XCTAssertEqual(restored.resultText, entry.resultText)
    }

    func testCapturedWarningSurvivesHistoryEncodingWithoutChangingTheTextOrLegacySettings() throws {
        for disposition in [PromptCompositionDeliveryDisposition.ready, .needsReview] {
            let summary = PromptCompositionReviewSummary(deliveryDisposition: disposition,
                warningIssues: disposition == .needsReview ? [.intent, .omissions] : [])
            let entry = HistoryEntry(mode: .prompt, originalText: "사용자가 말한 원문", resultText: "만든 프롬프트",
                provider: .openRouter, promptReviewSummary: summary)
            let restored = try JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(entry))

            XCTAssertEqual(restored.promptReviewSummary, summary)
            XCTAssertEqual(restored.originalText, entry.originalText)
            XCTAssertEqual(restored.resultText, entry.resultText)
            XCTAssertNil(restored.outputLanguage)
            XCTAssertNil(restored.writingProfile)
        }
        let ordinary = HistoryEntry(mode: .dictation, originalText: "일반 받아쓰기", resultText: "받아쓰기", provider: .groq)
        let restored = try JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(ordinary))
        XCTAssertNil(restored.promptReviewSummary)
    }

    func testOnlyCompletedDeliverableResultsEnableExplicitCopyWithoutChangingTheirReviewState() {
        var composition = PromptCompositionPresentation(transcript: "원문", output: "생성문", status: "pending")
        XCTAssertFalse(composition.canCopyOutput)
        composition.isProcessing = false
        XCTAssertFalse(composition.canCopyOutput, "A missing disposition is not assumed to be reviewed")
        composition.deliveryDisposition = .needsReview
        composition.warningIssues = [.omissions]
        XCTAssertTrue(composition.canCopyOutput)
        XCTAssertTrue(composition.needsReview)
        XCTAssertFalse(composition.held)
        XCTAssertEqual(composition.title, "만든 프롬프트")
        XCTAssertEqual(composition.deliveryDisposition, .needsReview)
        composition.deliveryDisposition = .blocked
        XCTAssertFalse(composition.canCopyOutput)
        composition.deliveryDisposition = .ready
        XCTAssertTrue(composition.canCopyOutput)
        composition.held = true
        XCTAssertFalse(composition.canCopyOutput)
    }
}
