import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

final class TranslationProtectionPolicyTests: XCTestCase {
    func testOnlyExplicitTranslationProtectionInProtectModeAddsReview() {
        for mode in [InputMode.dictation, .translation, .rewrite] {
            for enabled in [false, true] {
                for reviewMode in [DecisionReviewMode.off, .observe, .protect, .repair] {
                    XCTAssertEqual(TranslationProtectionPolicy.requiresReview(mode: mode, enabled: enabled, reviewMode: reviewMode),
                                   mode == .translation && enabled && reviewMode == .protect)
                }
            }
        }
    }

    func testOnlyCompleteFiniteLowRiskReviewAuthorizesTyping() {
        func review(_ risk: Double, details: [DecisionDetailAxis: Double] = [:]) -> DecisionResult {
            .init(meaningChanged: risk, contentAdded: 0, contentOmitted: 0, detailRisks: details)
        }
        XCTAssertEqual(TranslationProtectionPolicy.verdict(for: review(0.1), detailed: false), .accepted)
        XCTAssertEqual(TranslationProtectionPolicy.verdict(for: review(0.1001), detailed: false), .uncertain)
        XCTAssertEqual(TranslationProtectionPolicy.verdict(for: review(0.9), detailed: false), .meaningChanged)
        for invalid in [Double.nan, .infinity, -0.01, 1.01] {
            XCTAssertEqual(TranslationProtectionPolicy.verdict(for: review(invalid), detailed: false), .invalid)
        }
        XCTAssertEqual(TranslationProtectionPolicy.verdict(for: review(0), detailed: true), .invalid)
        var details = Dictionary(uniqueKeysWithValues: DecisionDetailAxis.allCases.map { ($0, 0.01) })
        XCTAssertEqual(TranslationProtectionPolicy.verdict(for: review(0, details: details), detailed: true), .accepted)
        details[.intent] = 0.4
        XCTAssertEqual(TranslationProtectionPolicy.verdict(for: review(0, details: details), detailed: true), .uncertain)
        XCTAssertEqual(TranslationProtectionPolicy.verdict(for: review(0, details: details), detailed: false), .invalid)
        var unexpectedTerms = review(0)
        unexpectedTerms.terms = [.init(id: "unexpected", choice: .keepOriginal,
            probabilities: [.keepOriginal: 1, .useCandidate: 0, .uncertain: 0], confidence: 1)]
        XCTAssertEqual(TranslationProtectionPolicy.verdict(for: unexpectedTerms, detailed: false), .invalid)
    }
}
