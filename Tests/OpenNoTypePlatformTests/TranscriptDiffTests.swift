import SwiftUI
import XCTest
@testable import OpenNoType

final class TranscriptDiffTests: XCTestCase {
    func testIdenticalStringsReturnNil() {
        XCTAssertNil(TranscriptDiff.compare(original: "같은 문장입니다.", result: "같은 문장입니다."))
    }

    func testMarksRemovedFillersAndAddedCorrections() throws {
        let original = "음 내일 회의에 오픈 노타입 자료를 보내 주세요"
        let result = "내일 회의에 OpenNoType 자료를 보내 주세요"
        let comparison = try XCTUnwrap(TranscriptDiff.compare(original: original, result: result))
        let changedOriginal = comparison.original.filter(\.changed).map(\.text)
        let changedResult = comparison.result.filter(\.changed).map(\.text)
        XCTAssertEqual(changedOriginal, ["음", "오픈 노타입"])
        XCTAssertEqual(changedResult, ["OpenNoType"])
        XCTAssertEqual(comparison.original.map(\.text).joined(), original)
        XCTAssertEqual(comparison.result.map(\.text).joined(), result)
    }

    func testJapaneseTextDiffsAtCharacterGranularityWithoutInsertingSpaces() throws {
        let original = "明日の会議でオープンノタイプの資料を送ってください"
        let result = "明日の会議でOpenNoTypeの資料を送ってください。"
        let comparison = try XCTUnwrap(TranscriptDiff.compare(original: original, result: result))

        XCTAssertEqual(comparison.original.filter(\.changed).map(\.text), ["オープンノタイプ"])
        XCTAssertEqual(comparison.result.filter(\.changed).map(\.text), ["OpenNoType", "。"])
        XCTAssertEqual(comparison.original.map(\.text).joined(), original)
        XCTAssertEqual(comparison.result.map(\.text).joined(), result)

        let rendered = TranscriptDiff.attributed(
            comparison.result,
            highlightBackground: .green,
            highlightForeground: .primary
        )
        XCTAssertEqual(String(rendered.characters), result)
    }

    func testChineseTextDiffsAtCharacterGranularityWithoutMarkingWholeSentence() throws {
        let original = "明天上午的会议请准备一下报告"
        let result = "明天上午的会议请准备这份报告。"
        let comparison = try XCTUnwrap(TranscriptDiff.compare(original: original, result: result))

        XCTAssertEqual(comparison.original.filter(\.changed).map(\.text), ["一下"])
        XCTAssertEqual(comparison.result.filter(\.changed).map(\.text), ["这份", "。"])
        XCTAssertEqual(comparison.original.map(\.text).joined(), original)
        XCTAssertEqual(comparison.result.map(\.text).joined(), result)
    }

    func testNewlinesArePreservedInSegmentsAndAttributedOutput() throws {
        let original = "첫 줄입니다\n음 둘째 줄입니다\n셋째 줄입니다"
        let result = "첫 줄입니다\n둘째 줄입니다\n셋째 줄입니다."
        let comparison = try XCTUnwrap(TranscriptDiff.compare(original: original, result: result))

        XCTAssertEqual(comparison.original.filter(\.changed).map(\.text), ["음", "줄입니다"])
        XCTAssertEqual(comparison.result.filter(\.changed).map(\.text), ["줄입니다."])
        XCTAssertEqual(comparison.original.map(\.text).joined(), original)
        XCTAssertEqual(comparison.result.map(\.text).joined(), result)

        let renderedOriginal = TranscriptDiff.attributed(
            comparison.original,
            highlightBackground: .orange,
            highlightForeground: .primary,
            strikethrough: true
        )
        let renderedResult = TranscriptDiff.attributed(
            comparison.result,
            highlightBackground: .green,
            highlightForeground: .primary
        )
        XCTAssertEqual(String(renderedOriginal.characters), original)
        XCTAssertEqual(String(renderedResult.characters), result)
    }

    func testExceedingTokenBoundReturnsNilGracefully() {
        let longA = Array(repeating: "word", count: TranscriptDiff.maxTokenCount + 10).joined(separator: " ")
        let longB = longA + " extra"
        XCTAssertNil(TranscriptDiff.compare(original: longA, result: longB))
    }
}
