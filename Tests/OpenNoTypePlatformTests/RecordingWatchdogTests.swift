import XCTest
@testable import OpenNoType

final class RecordingWatchdogTests: XCTestCase {
    private func progress(callback: TimeInterval? = nil, delivery: TimeInterval? = nil,
                          gap: TimeInterval = 0, pending: Int = 0) -> AudioCapture.Progress {
        var value = AudioCapture.Progress()
        value.lastCallbackAt = callback
        value.lastDeliveryAt = delivery
        value.maximumCallbackGap = gap
        value.pendingBuffers = pending
        return value
    }

    func testCallbacksStoppingAfterReadyAreDetectedAtTheBoundary() {
        let subject = RecordingWatchdog(readyAt: 100)
        let state = progress(callback: 101, delivery: 101)
        XCTAssertNil(subject.failure(at: 105.999, progress: state))
        XCTAssertEqual(subject.failure(at: 106, progress: state), .callbackStalled)
    }

    func testContinuingCallbacksWithBlockedDeliveryAreDetectedIndependently() {
        let subject = RecordingWatchdog(readyAt: 100)
        XCTAssertNil(subject.failure(at: 109.999, progress: progress(callback: 109.9, delivery: 100, pending: 2)))
        XCTAssertEqual(subject.failure(at: 110, progress: progress(callback: 109.9, delivery: 100, pending: 2)),
                       .deliveryStalled)
    }

    func testSilentFramesAndLongMainActorDelayAreStillHealthyWhenCaptureProgresses() {
        let subject = RecordingWatchdog(readyAt: 100)
        // Amplitude is deliberately absent: zero-valued PCM is valid progress.
        XCTAssertNil(subject.failure(at: 160, progress: progress(callback: 159.99, delivery: 159.98, gap: 0.1)))
    }

    func testGapIsDetectedEvenWhenCallbacksResumeBeforeStopChecks() {
        let subject = RecordingWatchdog(readyAt: 100)
        XCTAssertEqual(subject.failure(at: 160, progress: progress(callback: 159.99, delivery: 159.98, gap: 6)),
                       .callbackStalled)
    }

    func testFreshSessionDoesNotInheritIdleSuspensionOrPriorSessionProgress() {
        let subject = RecordingWatchdog(readyAt: 1_000)
        XCTAssertNil(subject.failure(at: 1_000, progress: progress()))
        // Baselines cannot predate the current ready signal, even for a late stale snapshot.
        XCTAssertNil(subject.failure(at: 1_004, progress: progress(callback: 100, delivery: 100, pending: 1)))
    }

    func testStopBeforeNextTimerStillDetectsMissingCallbacksAcrossSuspension() {
        let subject = RecordingWatchdog(readyAt: 100)
        XCTAssertEqual(subject.failure(at: 200, progress: progress(callback: 101, delivery: 101)), .callbackStalled)
    }

    func testNoPendingInputDoesNotTreatRetainedConverterTailAsDeliveryFailure() {
        let subject = RecordingWatchdog(readyAt: 100)
        XCTAssertNil(subject.failure(at: 120, progress: progress(callback: 119.9, delivery: 100)))
    }

    func testDurationLimitDoesNotTurnIntentionallyStoppedCallbacksIntoFailure() {
        let subject = RecordingWatchdog(readyAt: 100)
        XCTAssertNil(subject.failure(at: 160, progress: progress(callback: 110, delivery: 110), reachedDurationLimit: true))
        XCTAssertEqual(subject.failure(at: 160, progress: progress(callback: 110, delivery: 110, gap: 6),
                                       reachedDurationLimit: true), .callbackStalled)
    }
}
