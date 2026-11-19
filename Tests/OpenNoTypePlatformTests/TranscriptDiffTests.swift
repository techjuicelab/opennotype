import XCTest
@testable import OpenNoType

final class TranscriptDiffTests: XCTestCase {
    func testIdenticalStringsReturnNil() {
        XCTAssertNil(TranscriptDiff.compare(original: "같은 문장입니다.", result: "같은 문장입니다."))
    }

    func testMarksRemovedFillersAndAddedCorrections() throws {
        let comparison = try XCTUnwrap(TranscriptDiff.compare(
            original: "음 내일 회의에 오픈 노타입 자료를 보내 주세요",
            result: "내일 회의에 OpenNoType 자료를 보내 주세요"
        ))
        let changedOriginal = comparison.original.filter(\.changed).map(\.text)
        let changedResult = comparison.result.filter(\.changed).map(\.text)
        XCTAssertEqual(changedOriginal, ["음", "오픈 노타입"])
        XCTAssertEqual(changedResult, ["OpenNoType"])
    }

    func testExceedingTokenBoundReturnsNilGracefully() {
        let longA = Array(repeating: "word", count: TranscriptDiff.maxTokenCount + 10).joined(separator: " ")
        let longB = longA + " extra"
        XCTAssertNil(TranscriptDiff.compare(original: longA, result: longB))
    }
}
