import Foundation
import XCTest
@testable import OpenNoType

final class RecordingMuteTests: XCTestCase {
    private final class Output {
        var muted = false
        var writes: [Bool] = []
        var observed: ((Bool) -> Void)?
        var observersRemoved = 0
        var writeFailure: Error?
        var failAfterApplying = false

        var access: RecordingMuteAccess {
            .init(read: { self.muted }, write: { value in
                self.writes.append(value)
                if let failure = self.writeFailure, !self.failAfterApplying { throw failure }
                self.muted = value; self.observed?(value)
                if let failure = self.writeFailure { self.writeFailure = nil; throw failure }
            }, observe: { changed in
                self.observed = changed
                return { self.observed = nil; self.observersRemoved += 1 }
            })
        }

        func userSetsMute(_ value: Bool) { muted = value; observed?(value) }
    }

    func testRestoresOnlyTheMuteItAppliedAndOnlyOnce() throws {
        let output = Output()
        let session = try RecordingMuteSession(access: output.access)
        XCTAssertTrue(output.muted)
        try session.restore()
        try session.restore()
        XCTAssertFalse(output.muted)
        XCTAssertEqual(output.writes, [true, false])
        XCTAssertEqual(output.observersRemoved, 1)
    }

    func testAlreadyMutedOutputIsNeverChangedOrObserved() throws {
        let output = Output(); output.muted = true
        let session = try RecordingMuteSession(access: output.access)
        try session.restore()
        XCTAssertTrue(output.muted)
        XCTAssertTrue(output.writes.isEmpty)
        XCTAssertNil(output.observed)
    }

    func testDroppingAnOwnedSessionRestoresTheOutput() throws {
        let output = Output()
        var session: RecordingMuteSession? = try RecordingMuteSession(access: output.access)
        XCTAssertNotNil(session)
        XCTAssertTrue(output.muted)
        session = nil
        XCTAssertFalse(output.muted)
        XCTAssertEqual(output.writes, [true, false])
        XCTAssertNil(output.observed)
    }

    func testUserUnmuteThenMuteIsPreservedEvenWhenFinalValueMatchesOurMute() throws {
        let output = Output()
        let session = try RecordingMuteSession(access: output.access)
        output.userSetsMute(false)
        output.userSetsMute(true)
        try session.restore()
        XCTAssertTrue(output.muted)
        XCTAssertEqual(output.writes, [true])
    }

    func testUserUnmuteIsPreservedWhenObserverHasNotYetDeliveredIt() throws {
        let output = Output()
        let session = try RecordingMuteSession(access: output.access)
        output.muted = false
        try session.restore()
        XCTAssertFalse(output.muted)
        XCTAssertEqual(output.writes, [true])
    }

    func testSetterFailureAfterMutationStillRestoresAndRemovesObserver() throws {
        let output = Output()
        output.writeFailure = NSError(domain: "SyntheticAudioOutput", code: 1)
        output.failAfterApplying = true
        XCTAssertThrowsError(try RecordingMuteSession(access: output.access))
        XCTAssertFalse(output.muted)
        XCTAssertEqual(output.writes, [true, false])
        XCTAssertNil(output.observed)
    }

    func testRestoreFailureIsReportedAndDoesNotRetryOverLaterUserChanges() throws {
        let output = Output()
        let session = try RecordingMuteSession(access: output.access)
        output.writeFailure = NSError(domain: "SyntheticAudioOutput", code: 2)
        XCTAssertThrowsError(try session.restore())
        output.userSetsMute(false)
        try session.restore()
        XCTAssertFalse(output.muted)
        XCTAssertEqual(output.writes, [true, false])
        XCTAssertNil(output.observed)
    }
}
