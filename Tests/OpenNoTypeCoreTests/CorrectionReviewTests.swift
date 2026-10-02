import XCTest
@testable import OpenNoTypeCore

final class CorrectionReviewTests: XCTestCase {
    func testMultiwordKoreanNameCreatesExplicitReviewProposalOnly() throws {
        let before = "오픈 라우터에서 연결해 주세요."
        let after = "OpenRouter에서 연결해 주세요."
        let proposed = try XCTUnwrap(CorrectionLearner.reviewProposal(original: before, edited: after))
        XCTAssertEqual(proposed.spoken, "오픈 라우터")
        XCTAssertEqual(proposed.written, "OpenRouter")
        XCTAssertFalse(proposed.learned)
        XCTAssertNil(CorrectionLearner.proposedCorrection(original: before, edited: after))
        XCTAssertNil(CorrectionLearner.suggestion(original: before, edited: after))
        XCTAssertNotNil(CorrectionLearner.reviewCandidate(original: before, edited: after))
    }

    func testPhraseKeepsUnchangedPrefixSuffixAndSeparatesParticle() throws {
        let proposed = try XCTUnwrap(CorrectionLearner.reviewProposal(
            original: "오늘은 원 패스워드로 키를 확인해요", edited: "오늘은 1Password로 키를 확인해요"))
        XCTAssertEqual([proposed.spoken, proposed.written], ["원 패스워드", "1Password"])
    }

    func testSharedVersionStaysOutsidePhraseAlias() throws {
        let proposed = try XCTUnwrap(CorrectionLearner.reviewProposal(
            original: "비주얼 코드2026에서 작업해요", edited: "VisualCode2026에서 작업해요"))
        XCTAssertEqual([proposed.spoken, proposed.written], ["비주얼 코드", "VisualCode"])
    }

    func testReverseScriptPhraseCanBeReviewedWithoutAutomaticLearning() throws {
        let before = "OpenRouter에서 확인해요", after = "오픈 라우터에서 확인해요"
        let proposed = try XCTUnwrap(CorrectionLearner.reviewProposal(original: before, edited: after))
        XCTAssertEqual([proposed.spoken, proposed.written], ["OpenRouter", "오픈 라우터"])
        XCTAssertNil(CorrectionLearner.suggestion(original: before, edited: after))
    }

    func testExistingSingleTokenProposalRemainsAvailable() throws {
        let before = "여기 웨더가 좋네", after = "여기 weather가 좋네"
        let proposed = try XCTUnwrap(CorrectionLearner.reviewProposal(original: before, edited: after))
        XCTAssertEqual([proposed.spoken, proposed.written], ["웨더", "weather"])
        XCTAssertFalse(proposed.learned)
    }

    func testSeparateSentenceAndPunctuationEditsDoNotBecomeAlias() {
        let before = "오픈 라우터에서 오늘 확인해요."
        for after in ["OpenRouter에서 내일 확인해요.", "OpenRouter에서 오늘 확인해요!", "OpenRouter에서 오늘 확인했어요."] {
            XCTAssertNil(CorrectionLearner.reviewProposal(original: before, edited: after), after)
        }
    }

    func testQuotedNamesIdentifiersAndURLsAreNotReviewAliases() {
        for (before, after) in [
            ("문자열 '오픈 라우터' 유지", "문자열 'OpenRouter' 유지"),
            ("문자열 \"앞 오픈 라우터 뒤\" 유지", "문자열 \"앞 OpenRouter 뒤\" 유지"),
            ("문자열 '앞 오픈 라우터 뒤' 유지", "문자열 '앞 OpenRouter 뒤' 유지"),
            ("문자열 “앞 오픈 라우터 뒤” 유지", "문자열 “앞 OpenRouter 뒤” 유지"),
            ("`오픈 라우터` 유지", "`OpenRouter` 유지"),
            ("변수 open_router 유지", "변수 OpenRouter 유지"),
            ("https://오픈라우터.example", "https://OpenRouter.example")
        ] {
            XCTAssertNil(CorrectionLearner.reviewProposal(original: before, edited: after), before)
        }
    }

    func testSensitiveValuesAndLowercaseLexicalPhrasesRemainManual() {
        for (before, after) in [
            ("내일 회의해요", "Today 회의해요"),
            ("오전 일곱 시에", "PM 일곱 시에"),
            ("이것은 가능", "이것은 Impossible"),
            ("오늘 내일 확인", "Today 확인"),
            ("그 프로젝트 취소", "그 cancel"),
            ("비주얼 코드2026 확인", "VisualCode2027 확인")
        ] {
            XCTAssertNil(CorrectionLearner.reviewProposal(original: before, edited: after), before)
        }
    }

    func testEmptyOverlongAndSeparatedEditsRemainManual() {
        XCTAssertNil(CorrectionLearner.reviewProposal(original: "", edited: "OpenRouter"))
        XCTAssertNil(CorrectionLearner.reviewProposal(original: "오픈 라우터", edited: ""))
        XCTAssertNil(CorrectionLearner.reviewProposal(original: "동일", edited: "동일"))
        XCTAssertNil(CorrectionLearner.reviewProposal(original: String(repeating: "가", count: 2_001), edited: "Name"))
        XCTAssertNil(CorrectionLearner.reviewProposal(original: "오픈 라우터 그리고 그록", edited: "OpenRouter 그리고 Groq"))
        XCTAssertNil(CorrectionLearner.reviewProposal(original: "일 이 삼 사 오", edited: "UnknownName"))
    }
}
