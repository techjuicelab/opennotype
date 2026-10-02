import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

final class JevReviewPresentationTests: XCTestCase {
    func testTargetPreservesPurposeAndGenerationMetadata() {
        let target = JevReviewTarget(id: UUID(), kind: .recent, transcript: "Make it shorter", output: "Short result",
            purpose: .rewrite(originalText: "The original selected passage"), textProvider: .openRouter,
            textModel: "selected-model", writingProfile: .init())
        XCTAssertEqual(target.mode, .rewrite)
        XCTAssertEqual(target.comparisonSource, "The original selected passage")
        XCTAssertEqual(target.transcript, "Make it shorter")
        XCTAssertEqual(target.textProvider, .openRouter)
        XCTAssertEqual(target.textModel, "selected-model")
        let plain = JevReviewTarget(id: UUID(), kind: .history, transcript: "source", output: "result")
        XCTAssertEqual(plain.purpose, .dictation)
        XCTAssertEqual(plain.comparisonSource, "source")
        XCTAssertNil(plain.textModel)
    }

    func testUncertainChoiceNeverAuthorizesDictionarySave() {
        let value = proposal(choice: .uncertain, probabilities: [.useCandidate: 0.05, .keepOriginal: 0.05, .uncertain: 0.9], confidence: 0.99)
        XCTAssertEqual(value.evidence, .uncertain)
        XCTAssertFalse(value.canSave)
        XCTAssertFalse(proposal(choice: .keepOriginal).canSave)
    }

    func testCloseChoicesAndMissingEvidenceRemainAdvisory() {
        XCTAssertEqual(proposal(probabilities: [.useCandidate: 0.5, .keepOriginal: 0.49, .uncertain: 0.01], confidence: 0.95).evidence, .needsCloserReview)
        XCTAssertEqual(proposal(probabilities: [.useCandidate: 0.9, .keepOriginal: 0.05, .uncertain: 0.05], confidence: 0.3).evidence, .needsCloserReview)
        XCTAssertEqual(proposal().evidence, .needsCloserReview)
        XCTAssertEqual(proposal(probabilities: [.useCandidate: 0.9, .keepOriginal: 0.05, .uncertain: 0.05], confidence: .nan).evidence, .needsCloserReview)
        let preferred = proposal(probabilities: [.useCandidate: 0.9, .keepOriginal: 0.05, .uncertain: 0.05], confidence: 0.9)
        XCTAssertEqual(preferred.evidence, .candidatePreferred)
        XCTAssertTrue(preferred.canSave, "The model still requires the existing explicit save confirmation")
    }

    func testLocalComparisonFindsChangedNumberAndPreservesUnchangedWords() {
        let comparison = JevTextComparison(source: "회의는 오후 3시에 시작해요.", result: "회의는 오후 4시에 시작해요.")
        XCTAssertEqual(comparison.sourceOnly, ["3"])
        XCTAssertEqual(comparison.resultOnly, ["4"])
        XCTAssertEqual(comparison.sourceNumbers, ["3"])
        XCTAssertEqual(comparison.resultNumbers, ["4"])
        XCTAssertTrue(comparison.numbersDiffer)
        XCTAssertFalse(comparison.truncated)
    }

    func testLocalComparisonIsLiteralAndDoesNotNormalizeIdentifiersOrNames() {
        let comparison = JevTextComparison(source: "j_e_v와 제부", result: "JEV와 JEV")
        XCTAssertTrue(comparison.hasDifferences)
        XCTAssertTrue(comparison.sourceOnly.contains("j_e_v와"))
        XCTAssertTrue(comparison.sourceOnly.contains("제부"))
        XCTAssertFalse(comparison.numbersDiffer)
        let unchanged = JevTextComparison(source: "J E V 3", result: "J E V 3")
        XCTAssertFalse(unchanged.hasDifferences)
        XCTAssertFalse(unchanged.numbersDiffer)
    }

    func testComparisonLimitsTokenAndTextWorkAndReportsPartialDisplay() {
        let long = String(repeating: "word 1 ", count: 2_000)
        let comparison = JevTextComparison(source: long, result: "changed 2")
        XCTAssertTrue(comparison.truncated)
        XCTAssertLessThanOrEqual(comparison.sourceOnly.count, 16)
        XCTAssertLessThanOrEqual(comparison.sourceNumbers.count, 16)
        let empty = JevTextComparison(source: "", result: "")
        XCTAssertFalse(empty.hasDifferences)
        XCTAssertFalse(empty.truncated)
    }

    private func proposal(choice: DecisionTermChoice = .useCandidate,
                          probabilities: [DecisionTermChoice: Double] = [:], confidence: Double = 0) -> JevSpellingProposal {
        .init(id: UUID(), reviewID: UUID(), targetID: UUID(), original: "오픈 라우터", candidate: "OpenRouter", choice: choice,
              probabilities: probabilities, confidence: confidence)
    }
}
