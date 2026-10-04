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

    func testProtectedSingleWordChangesNeverBecomeAutomaticOrReviewAliases() {
        for (before, after) in [
            ("문자열 \"앞 OpennAI 뒤\" 유지", "문자열 \"앞 OpenAI 뒤\" 유지"),
            ("문자열 '앞 OpennAI 뒤' 유지", "문자열 '앞 OpenAI 뒤' 유지"),
            ("문자열 “앞 OpennAI 뒤” 유지", "문자열 “앞 OpenAI 뒤” 유지"),
            ("문자열 ‘앞 OpennAI 뒤’ 유지", "문자열 ‘앞 OpenAI 뒤’ 유지"),
            ("문자열 'I'm using OpennAI' 유지", "문자열 'I'm using OpenAI' 유지"),
            ("문자열 ‘I’m using OpennAI’ 유지", "문자열 ‘I’m using OpenAI’ 유지"),
            ("문자열 'John's favorite OpennAI' 유지", "문자열 'John's favorite OpenAI' 유지"),
            ("`앞 OpennAI 뒤` 유지", "`앞 OpenAI 뒤` 유지"),
            ("```swift\nlet name = OpennAI\n```", "```swift\nlet name = OpenAI\n```"),
            ("const OpennAI_client = 1", "const OpenAI_client = 1"),
            ("const client_OpennAI_suffix = 1", "const client_OpenAI_suffix = 1"),
            ("https://OpennAI.example/path", "https://OpenAI.example/path"),
            ("https://www.OpennAI.example/path", "https://www.OpenAI.example/path"),
            ("https://example.test/docs/file.OpennAI.json", "https://example.test/docs/file.OpenAI.json"),
            ("HTTPS://www.OpennAI.example/path", "HTTPS://www.OpenAI.example/path"),
            ("www.OpennAI.example/path", "www.OpenAI.example/path"),
            ("https://example.test/docs/John's.OpennAI.json", "https://example.test/docs/John's.OpenAI.json")
        ] {
            XCTAssertNil(CorrectionLearner.suggestion(original: before, edited: after), before)
            XCTAssertNil(CorrectionLearner.proposedCorrection(original: before, edited: after), before)
            XCTAssertNil(CorrectionLearner.reviewProposal(original: before, edited: after), before)
        }
    }

    func testContractionsAndPossessivesDoNotHideNameReviewProposals() throws {
        for prefix in ["I'm using", "I’m using", "John's favorite", "John’s favorite", "James' favorite", "James’ favorite"] {
            let single = try XCTUnwrap(CorrectionLearner.reviewProposal(
                original: "\(prefix) 클로드", edited: "\(prefix) Claude"), prefix)
            XCTAssertEqual([single.spoken, single.written], ["클로드", "Claude"])
            let phrase = try XCTUnwrap(CorrectionLearner.reviewProposal(
                original: "\(prefix) 오픈 라우터", edited: "\(prefix) OpenRouter"), prefix)
            XCTAssertEqual([phrase.spoken, phrase.written], ["오픈 라우터", "OpenRouter"])
            XCTAssertFalse(phrase.learned)
        }
    }

    func testContractionsPossessivesAndClosedQuotesKeepNormalAutomaticLearning() throws {
        for prefix in ["I'm using", "I’m using", "John's favorite", "John’s favorite", "James' favorite", "James’ favorite",
                       "'I'm using a tool' then", "‘I’m using a tool’ then", "'James' then", "\"John's tool\" then"] {
            let entry = try XCTUnwrap(CorrectionLearner.suggestion(
                original: "\(prefix) OpennAI", edited: "\(prefix) OpenAI"), prefix)
            XCTAssertEqual([entry.spoken, entry.written], ["OpennAI", "OpenAI"])
            XCTAssertTrue(entry.learned)
        }
    }

    func testUnclosedQuotedSpansStayProtected() {
        for prefix in ["\"I'm using", "'I'm using", "“I’m using", "‘I’m using", "`let client ="] {
            let before = "\(prefix) OpennAI", after = "\(prefix) OpenAI"
            XCTAssertNil(CorrectionLearner.suggestion(original: before, edited: after), prefix)
            XCTAssertNil(CorrectionLearner.reviewProposal(original: before, edited: after), prefix)
        }
    }

    func testNestedSmartQuotesAndQuotedCodeStayProtected() {
        for before in [
            "“He said “Hello” to OpennAI today”",
            "‘He said ‘Hello’ to OpennAI today’",
            "“He said ‘I’m ready’ to OpennAI today”",
            "‘He said “Hello” to OpennAI today’",
            "“Code `”` then OpennAI today”",
            "‘Code `’` then OpennAI today’",
            #""Code `"` then OpennAI today""#,
            "“Code ```\nlet text = ”\n``` then OpennAI today”",
            "```swift\nlet text = `x`\nlet client = OpennAI\n```"
        ] {
            let after = before.replacingOccurrences(of: "OpennAI", with: "OpenAI")
            XCTAssertNil(CorrectionLearner.suggestion(original: before, edited: after), before)
            XCTAssertNil(CorrectionLearner.proposedCorrection(original: before, edited: after), before)
            XCTAssertNil(CorrectionLearner.reviewProposal(original: before, edited: after), before)
        }
    }

    func testClosedNestedQuotesAndCodeKeepFollowingAutomaticLearning() throws {
        for prefix in [
            "“He said “Hello” today” then",
            "‘He said ‘Hello’ today’ then",
            "“He said ‘I’m ready’ today” then",
            "‘He said “Hello” today’ then",
            "`“quoted” ‘text’` then",
            "`“unclosed and 'unclosed` then",
            "“Code `”` today” then",
            #""Code `"` today" then"#,
            "```swift\nlet text = `x`\nlet quote = “\n```\nUse"
        ] {
            let entry = try XCTUnwrap(CorrectionLearner.suggestion(
                original: "\(prefix) OpennAI", edited: "\(prefix) OpenAI"), prefix)
            XCTAssertEqual([entry.spoken, entry.written], ["OpennAI", "OpenAI"])
            XCTAssertTrue(entry.learned)
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
