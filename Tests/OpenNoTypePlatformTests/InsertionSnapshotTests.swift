import AppKit
import XCTest
@testable import OpenNoType

final class InsertionSnapshotTests: XCTestCase {
    func testSelectedReplacementUsesUTF16OffsetsAcrossEmoji() throws {
        let prefix = "앞🙂👨‍👩‍👧‍👦 "
        let original = prefix + "선택한 말" + " 뒤 문장"
        let range = CFRange(location: (prefix as NSString).length, length: ("선택한 말" as NSString).length)
        let snapshot = try XCTUnwrap(InsertionSnapshot(original: original, range: range))
        XCTAssertEqual(snapshot.expectedValue(inserting: "OpenNoType"), prefix + "OpenNoType 뒤 문장")
    }

    func testInsertAtBeginningAndEndRetainsEveryOriginalCharacter() throws {
        let original = "🙂 원문"
        let first = try XCTUnwrap(InsertionSnapshot(original: original, range: CFRange(location: 0, length: 0)))
        let last = try XCTUnwrap(InsertionSnapshot(original: original, range: CFRange(location: (original as NSString).length, length: 0)))
        XCTAssertEqual(first.expectedValue(inserting: "앞 "), "앞 🙂 원문")
        XCTAssertEqual(last.expectedValue(inserting: " 뒤"), "🙂 원문 뒤")
    }

    func testUnreadableNegativeOverflowAndSplitSurrogateRangesAreRejected() {
        XCTAssertNil(InsertionSnapshot(original: nil, range: CFRange(location: 0, length: 0)))
        XCTAssertNil(InsertionSnapshot(original: "원문", range: nil))
        for range in [CFRange(location: -1, length: 0), CFRange(location: 0, length: -1),
                      CFRange(location: 3, length: 0), CFRange(location: 1, length: Int.max),
                      CFRange(location: Int.max, length: Int.max), CFRange(location: 1, length: 1),
                      CFRange(location: 0, length: 1)] {
            XCTAssertNil(InsertionSnapshot(original: "🙂", range: range), "Invalid UTF-16 range: \(range)")
        }
    }

    func testInitiallyEmptyFieldStillLearnsValidatedSingleWordCorrection() throws {
        let snapshot = try XCTUnwrap(InsertionSnapshot(original: "", range: CFRange(location: 0, length: 0)))
        let corrected = "OpenNoType"
        XCTAssertEqual(snapshot.editedText(inserting: "오픈노타입", current: corrected,
                                          selection: CFRange(location: (corrected as NSString).length, length: 0)), corrected)
        XCTAssertNil(snapshot.editedText(inserting: "오픈노타입", current: "새로 쓴 다른 문장",
                                        selection: CFRange(location: 10, length: 0)),
                     "An empty field must not become a broad review candidate for unrelated later text")
    }

    func testAppendAndChangedAnchorsEndObservation() throws {
        let empty = try XCTUnwrap(InsertionSnapshot(original: "", range: CFRange(location: 0, length: 0)))
        XCTAssertFalse(empty.observationIsBounded(inserting: "안녕하세요.", current: "안녕하세요. 후속 문장",
                                                  selection: CFRange(location: 12, length: 0)))
        let anchored = try XCTUnwrap(InsertionSnapshot(original: "앞  뒤", range: CFRange(location: 2, length: 0)))
        XCTAssertFalse(anchored.observationIsBounded(inserting: "오픈노타입", current: "다른앞 OpenNoType 뒤",
                                                     selection: CFRange(location: 12, length: 0)))
        XCTAssertFalse(anchored.observationIsBounded(inserting: "오픈노타입", current: "앞 OpenNoType 다른뒤",
                                                     selection: CFRange(location: 10, length: 0)))
    }

    func testCaretAndSelectionCannotLeaveInsertedSpan() throws {
        let snapshot = try XCTUnwrap(InsertionSnapshot(original: "앞  뒤", range: CFRange(location: 2, length: 0)))
        XCTAssertEqual(snapshot.editedText(inserting: "오픈노타입", current: "앞 OpenNoType 뒤",
                                          selection: CFRange(location: 12, length: 0)), "OpenNoType")
        for selection in [CFRange(location: 0, length: 0), CFRange(location: 13, length: 0),
                          CFRange(location: 2, length: 11), CFRange(location: 2, length: Int.max)] {
            XCTAssertFalse(snapshot.observationIsBounded(inserting: "오픈노타입", current: "앞 OpenNoType 뒤", selection: selection))
        }
    }

    func testUnchangedTextIsNotACorrectionAndOversizedInputStopsObservation() throws {
        let snapshot = try XCTUnwrap(InsertionSnapshot(original: "", range: CFRange(location: 0, length: 0)))
        XCTAssertNil(snapshot.editedText(inserting: "API", current: "API", selection: CFRange(location: 3, length: 0)))
        XCTAssertFalse(snapshot.observationIsBounded(inserting: String(repeating: "가", count: 2_001),
                                                    current: String(repeating: "가", count: 2_001), selection: CFRange(location: 1, length: 0)))
        XCTAssertFalse(snapshot.observationIsBounded(inserting: "API", current: String(repeating: "가", count: 2_001),
                                                    selection: CFRange(location: 1, length: 0)))
    }
}
