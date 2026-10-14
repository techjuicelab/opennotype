import XCTest
@testable import OpenNoTypeCore

final class SpeechComparisonScoringTests: XCTestCase {
    func testWhitespaceDoesNotChangeKoreanOrMixedIdentifierScore() throws {
        let score = try SpeechComparisonScoring.score(reference: "한글 API 3개\nOpenNoType",
                                                     recognized: "한 글\tAPI3개 OpenNoType")
        XCTAssertEqual(score.edits, 0)
        XCTAssertEqual(score.characterErrorRate, 0)
    }

    func testSubstitutionDeletionAndInsertionUseReferenceLength() throws {
        let substitution = try SpeechComparisonScoring.score(reference: "abc", recognized: "adc")
        XCTAssertEqual(substitution.edits, 1)
        XCTAssertEqual(try XCTUnwrap(substitution.characterErrorRate), 1.0 / 3, accuracy: 0.00001)
        XCTAssertEqual(try SpeechComparisonScoring.score(reference: "abcd", recognized: "acd").edits, 1)
        XCTAssertEqual(try SpeechComparisonScoring.score(reference: "abc", recognized: "abxc").edits, 1)
    }

    func testUnicodeScalarsRatherThanUTF16UnitsOrGraphemeClustersAreCounted() throws {
        let korean = try SpeechComparisonScoring.score(reference: "한국", recognized: "한글")
        XCTAssertEqual(korean.referenceScalars, 2)
        XCTAssertEqual(korean.edits, 1)
        let emoji = try SpeechComparisonScoring.score(reference: "😀", recognized: "😀")
        XCTAssertEqual(emoji.referenceScalars, 1)
        XCTAssertEqual(emoji.edits, 0)
        let joinedEmoji = try SpeechComparisonScoring.score(reference: "👩‍💻", recognized: "👩‍💻")
        XCTAssertEqual(joinedEmoji.referenceScalars, 3)
        XCTAssertEqual(joinedEmoji.edits, 0)
    }

    func testCanonicalCompositionHandlesHangulAndCombiningMarks() throws {
        let combining = try SpeechComparisonScoring.score(reference: "e \u{301}", recognized: "é")
        XCTAssertEqual(combining.referenceScalars, 1)
        XCTAssertEqual(combining.edits, 0)
        let hangul = try SpeechComparisonScoring.score(reference: "\u{1112}\u{1161}\u{11AB}", recognized: "한")
        XCTAssertEqual(hangul.referenceScalars, 1)
        XCTAssertEqual(hangul.edits, 0)
    }

    func testPunctuationCaseAndNumericChangesRemainVisible() throws {
        XCTAssertEqual(try SpeechComparisonScoring.score(reference: "API", recognized: "api").edits, 3)
        XCTAssertEqual(try SpeechComparisonScoring.score(reference: "3개.", recognized: "5개").edits, 2)
    }

    func testEmptyReferenceHasNoScoreAndInsertionsCanExceedOneHundredPercent() throws {
        XCTAssertNil(try SpeechComparisonScoring.score(reference: " \n", recognized: "내용").characterErrorRate)
        XCTAssertNil(try SpeechComparisonScoring.score(reference: "", recognized: "").characterErrorRate)
        XCTAssertEqual(try SpeechComparisonScoring.score(reference: "a", recognized: "aaaa").characterErrorRate, 3)
        XCTAssertEqual(try SpeechComparisonScoring.score(reference: "한글", recognized: "").characterErrorRate, 1)
    }

    func testOversizedInputFailsBeforeQuadraticWork() {
        XCTAssertThrowsError(try SpeechComparisonScoring.score(reference: String(repeating: "a", count: 8_001), recognized: "a"))
        XCTAssertThrowsError(try SpeechComparisonScoring.score(reference: "a", recognized: String(repeating: "a", count: 8_001)))
    }

    func testNumericFragmentsKeepVersionDateAndDecimalSpellingForManualReview() {
        XCTAssertEqual(SpeechComparisonScoring.numericFragments(in: "v1.2.3은 2026-10-15 오후 3:20, 1,500.5원, 세 개"),
                       ["1.2.3", "2026-10-15", "3:20", "1,500.5"])
    }
}
