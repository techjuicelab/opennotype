import XCTest
@testable import OpenNoTypeCore

final class RecordingPolicyTests: XCTestCase {
    func testEightMinuteWarningBoundaryStartsAtSixtySeconds() {
        XCTAssertNil(RecordingPolicy.countdown(elapsed: 0))
        XCTAssertNil(RecordingPolicy.countdown(elapsed: 479.999))
        XCTAssertEqual(RecordingPolicy.countdown(elapsed: 480), 60)
        XCTAssertEqual(RecordingPolicy.countdown(elapsed: 480.001), 60)
        XCTAssertEqual(RecordingPolicy.countdown(elapsed: 481), 59)
    }

    func testNineMinuteBoundaryNeverDisplaysNegativeCountdown() {
        XCTAssertEqual(RecordingPolicy.maximumDuration, 540)
        XCTAssertEqual(RecordingPolicy.countdown(elapsed: 539), 1)
        XCTAssertEqual(RecordingPolicy.countdown(elapsed: 539.999), 1)
        XCTAssertEqual(RecordingPolicy.countdown(elapsed: 540), 0)
        XCTAssertEqual(RecordingPolicy.countdown(elapsed: 541), 0)
    }
}
