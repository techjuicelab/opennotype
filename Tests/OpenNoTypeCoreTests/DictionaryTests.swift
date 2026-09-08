import XCTest
@testable import OpenNoTypeCore

final class DictionaryTests: XCTestCase {
    func testSingleDistinctiveNameSpellingIsLearned() {
        let result = CorrectionLearner.suggestion(original: "Use OpennAI for this.", edited: "Use OpenAI for this.")
        XCTAssertEqual(result?.spoken, "OpennAI")
        XCTAssertEqual(result?.written, "OpenAI")
        XCTAssertEqual(result?.learned, true)
    }

    func testCaseCorrectionPreservesOriginalScripts() {
        let result = CorrectionLearner.suggestion(original: "openai API를 사용해요.", edited: "OpenAI API를 사용해요.")
        XCTAssertEqual(result?.spoken, "openai")
        XCTAssertEqual(result?.written, "OpenAI")
    }

    func testCrossScriptCorrectionLearnsStemWithoutKoreanParticle() {
        let result = CorrectionLearner.suggestion(original: "여기 웨더가 좋네", edited: "여기 weather가 좋네")
        XCTAssertEqual(result?.spoken, "웨더")
        XCTAssertEqual(result?.written, "weather")
        let another = CorrectionLearner.suggestion(original: "클로드에게 물어봐", edited: "Claude에게 물어봐")
        XCTAssertEqual(another?.spoken, "클로드")
        XCTAssertEqual(another?.written, "Claude")
        XCTAssertNil(CorrectionLearner.suggestion(original: "오늘 가자", edited: "tomorrow 가자"))
    }

    func testUncertainSameScriptMeaningChangesRequireReview() {
        XCTAssertNil(CorrectionLearner.suggestion(original: "이 문제를 봐", edited: "이 문장을 봐"))
        XCTAssertNil(CorrectionLearner.suggestion(original: "좋겠습니다", edited: "싫겠습니다"))
        XCTAssertNil(CorrectionLearner.suggestion(original: "weather", edited: "whether"))
    }

    func testNumbersNegationAndCertaintyNeverBecomeAutomaticDictionary() {
        for pair in [("7시에 보자", "3시에 보자"), ("오전에 보자", "오후에 보자"), ("I can go", "I can't go"), ("이것은 가능", "이것은 불가"), ("아마 갈게", "확실히 갈게"), ("I will go", "I will not go")] {
            XCTAssertNil(CorrectionLearner.suggestion(original: pair.0, edited: pair.1), "\(pair)")
        }
    }

    func testSentenceRewriteAndMultipleWordsRequireReview() {
        let before = "내일 오전에 회의해요."
        let after = "내일은 쉬고 금요일에 회의합시다."
        XCTAssertNil(CorrectionLearner.suggestion(original: before, edited: after))
        let candidate = CorrectionLearner.reviewCandidate(original: before, edited: after)
        XCTAssertEqual(candidate?.originalText, before)
        XCTAssertEqual(candidate?.editedText, after)
        XCTAssertNil(CorrectionLearner.suggestion(original: "Use OpennAI with Github", edited: "Use OpenAI with GitHub"))
    }

    func testPunctuationOrUnrelatedEditsAreNotLearned() {
        XCTAssertNil(CorrectionLearner.suggestion(original: "OpenAI", edited: "OpenAI!"))
        XCTAssertNil(CorrectionLearner.suggestion(original: "OpenAI", edited: "Anthropic"))
        XCTAssertNil(CorrectionLearner.suggestion(original: "cat", edited: "car"))
        XCTAssertNil(CorrectionLearner.suggestion(original: "동일한 문장", edited: "동일한 문장"))
        XCTAssertNil(CorrectionLearner.reviewCandidate(original: "", edited: "새로 쓴 문장"))
        XCTAssertNil(CorrectionLearner.reviewCandidate(original: "OpennAI", edited: "OpenAI"))
    }
}
