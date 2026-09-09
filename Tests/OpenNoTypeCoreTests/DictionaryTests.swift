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

    func testCrossScriptCorrectionProposesStemForExplicitReview() {
        let result = CorrectionLearner.proposedCorrection(original: "여기 웨더가 좋네", edited: "여기 weather가 좋네")
        XCTAssertEqual(result?.spoken, "웨더")
        XCTAssertEqual(result?.written, "weather")
        XCTAssertFalse(result?.learned ?? true)
        XCTAssertNil(CorrectionLearner.suggestion(original: "여기 웨더가 좋네", edited: "여기 weather가 좋네"))
        XCTAssertNotNil(CorrectionLearner.reviewCandidate(original: "여기 웨더가 좋네", edited: "여기 weather가 좋네"))
        let another = CorrectionLearner.proposedCorrection(original: "클로드에게 물어봐", edited: "Claude에게 물어봐")
        XCTAssertEqual(another?.spoken, "클로드")
        XCTAssertEqual(another?.written, "Claude")
        XCTAssertNil(CorrectionLearner.suggestion(original: "오늘 가자", edited: "tomorrow 가자"))
    }

    func testSharedDigitsAreExcludedFromExplicitReviewCandidates() throws {
        let phone = try XCTUnwrap(CorrectionLearner.proposedCorrection(original: "아이폰15 사용", edited: "iPhone15 사용"))
        XCTAssertEqual([phone.spoken, phone.written], ["아이폰", "iPhone"])
        let chat = try XCTUnwrap(CorrectionLearner.proposedCorrection(original: "챗지피티4로 해봐", edited: "ChatGPT4로 해봐"))
        XCTAssertEqual([chat.spoken, chat.written], ["챗지피티", "ChatGPT"])
        XCTAssertNil(CorrectionLearner.suggestion(original: "아이폰15 사용", edited: "아이폰16 사용"),
                     "A changed number is never a spelling correction")
        XCTAssertNil(CorrectionLearner.suggestion(original: "2026년 계획", edited: "2027년 계획"))
    }

    func testMeaningChangesAndSentenceCapitalsNeverLearnAutomatically() {
        for (before, after) in [("Cat is here.", "Car is here."), ("PLAN this.", "PLAY this."),
                                ("사과를 먹어요", "banana를 먹어요"), ("클로드에게 물어봐", "Google에게 물어봐")] {
            XCTAssertNil(CorrectionLearner.suggestion(original: before, edited: after), "\(before) → \(after)")
            XCTAssertNotNil(CorrectionLearner.reviewCandidate(original: before, edited: after))
        }
    }

    func testEmbeddedDigitNameCorrectionLearnsStemWithoutKoreanParticle() {
        let original = "GR5Q로 다시 진행해봤는데 잘 되는지 모르겠네요"
        let edited = "GROQ로 다시 진행해봤는데 잘 되는지 모르겠네요"
        let result = CorrectionLearner.suggestion(original: original, edited: edited)
        XCTAssertEqual(result?.spoken, "GR5Q")
        XCTAssertEqual(result?.written, "GROQ")
        XCTAssertEqual(result?.learned, true)
        XCTAssertNil(CorrectionLearner.reviewCandidate(original: original, edited: edited))

        let withoutParticle = CorrectionLearner.suggestion(original: "Use GR5Q again.", edited: "Use GROQ again.")
        XCTAssertEqual(withoutParticle?.spoken, "GR5Q")
        XCTAssertEqual(withoutParticle?.written, "GROQ")
    }

    func testLatinNameCorrectionSeparatesSharedParticleAndKeepsNameGuard() {
        let result = CorrectionLearner.suggestion(original: "OpennAI로 해요", edited: "OpenAI로 해요")
        XCTAssertEqual(result?.spoken, "OpennAI")
        XCTAssertEqual(result?.written, "OpenAI")
        XCTAssertNil(CorrectionLearner.suggestion(original: "weather로 해요", edited: "whether로 해요"))
    }

    func testNumericCorrectionsAndAmbiguousIdentifiersRequireReview() {
        let pairs = [
            ("7시에 보자", "3시에 보자"),
            ("비용은 5,000원", "비용은 6,000원"),
            ("2026-09-09에 만나요", "2026-09-10에 만나요"),
            ("GPT4로 진행", "GPT5로 진행"),
            ("GPT-4로 진행", "GPT-5로 진행"),
            ("GPT4로 진행", "GPTO로 진행"),
            ("v1.2로 진행", "v1.3로 진행"),
            ("R2D2로 진행", "R2DO로 진행"),
            ("GR55Q로 진행", "GROOQ로 진행"),
            ("GR5OQ로 진행", "GROQ로 진행"),
            ("5ROQ로 진행", "GROQ로 진행"),
            ("gr5q로 진행", "groq로 진행"),
            ("Gro5으로 진행", "Groq으로 진행"),
            ("A1로 진행", "AI로 진행"),
            ("TR5E", "TRUE"),
            ("N5VER", "NEVER")
        ]
        for (original, edited) in pairs {
            XCTAssertNil(CorrectionLearner.suggestion(original: original, edited: edited), "\(original) → \(edited)")
            XCTAssertNotNil(CorrectionLearner.reviewCandidate(original: original, edited: edited), "\(original) → \(edited)")
        }
    }

    func testDigitNameCorrectionRequiresExactlyOneChangeInOtherwiseIdenticalText() {
        for edited in [
            "GROQ로 다시 진행했는데 잘 되는지 모르겠네요",
            "GROQ로 다시 진행해봤는데 잘 되는지 모르겠네요!",
            "GROQ로 다시 진행해봤는데 잘 되는지 모르겠네요 2"
        ] {
            XCTAssertNil(CorrectionLearner.suggestion(original: "GR5Q로 다시 진행해봤는데 잘 되는지 모르겠네요", edited: edited))
        }
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
