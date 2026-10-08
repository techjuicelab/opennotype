import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

final class PromptCompositionReviewFormattingTests: XCTestCase {
    func testValuesBelowDeliveryThresholdsNeverDisplayTheThreshold() {
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(0.799), "79.9%")
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(0.8.nextDown), "79.9%")
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(0.599), "59.9%")
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(0.6.nextDown), "59.9%")
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(0.8), "80%")
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(0.6), "60%")
    }

    func testThresholdFormattingDoesNotChangeTheReviewDecision() {
        let belowProbability = assessment(probability: 0.799, confidence: 0.9)
        let belowConfidence = assessment(probability: 0.94, confidence: 0.599)
        let atThresholds = assessment(probability: 0.8, confidence: 0.6)

        XCTAssertTrue(belowProbability.isValid)
        XCTAssertFalse(belowProbability.accepted)
        XCTAssertTrue(belowConfidence.isValid)
        XCTAssertFalse(belowConfidence.accepted)
        XCTAssertTrue(atThresholds.accepted)
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(belowProbability.probabilities[.pass]!), "79.9%")
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(belowConfidence.confidence), "59.9%")
    }

    func testValidRangeAndInvalidNumbersRemainExplicit() {
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(0), "0%")
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(.leastNonzeroMagnitude), "0%")
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(0.0009), "0%")
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(0.001), "0.1%")
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(0.29), "29%")
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(0.94), "94%")
        XCTAssertEqual(PromptCompositionReviewFormatting.percentage(1), "100%")
        for invalid in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
            XCTAssertEqual(PromptCompositionReviewFormatting.percentage(invalid), "—")
        }
    }

    private func assessment(probability: Double, confidence: Double) -> PromptCompositionReviewAssessment {
        .init(choice: .pass, probabilities: [.pass: probability, .fail: (1 - probability) / 2,
            .uncertain: (1 - probability) / 2], confidence: confidence)
    }
}
