import XCTest
@testable import OpenNoTypeCore

final class ShortcutActivationTests: XCTestCase {
    func testDefaultTogglePreservesAllFourModesAndIgnoresReleaseAndRepeat() {
        for mode in InputMode.allCases {
            var policy = ShortcutActivationPolicy()
            XCTAssertEqual(policy.press(mode, activation: .toggle, at: 0), event(mode, .toggle))
            XCTAssertNil(policy.press(mode, activation: .toggle, at: 0.5))
            XCTAssertNil(policy.release(mode, at: 1))
            XCTAssertEqual(policy.press(mode, activation: .toggle, at: 2), event(mode, .toggle))
        }
    }

    func testToggleKeepsExistingAppBusyFeedback() {
        var policy = ShortcutActivationPolicy()
        _ = policy.updateRecordingState(.busy)
        XCTAssertEqual(policy.press(.translation, activation: .toggle, at: 0), event(.translation, .toggle))
    }

    func testHoldStopsOnReleaseEvenForAShortPress() {
        var policy = ShortcutActivationPolicy()
        XCTAssertEqual(policy.press(.dictation, activation: .hold, at: 0), event(.dictation, .start))
        XCTAssertNil(policy.updateRecordingState(.starting(.dictation)))
        XCTAssertNil(policy.updateRecordingState(.recording(.dictation)))
        XCTAssertEqual(policy.release(.dictation, at: 0.1), event(.dictation, .stop))
        XCTAssertNil(policy.release(.dictation, at: 0.2))
    }

    func testHybridShortPressKeepsRecordingUntilTheNextPress() {
        var policy = ShortcutActivationPolicy()
        XCTAssertEqual(policy.press(.rewrite, activation: .holdOrToggle, at: 10), event(.rewrite, .start))
        _ = policy.updateRecordingState(.recording(.rewrite))
        XCTAssertNil(policy.release(.rewrite, at: 10.2))
        XCTAssertEqual(policy.press(.rewrite, activation: .holdOrToggle, at: 11), event(.rewrite, .stop))
        _ = policy.updateRecordingState(.busy)
        _ = policy.updateRecordingState(.idle)
        XCTAssertNil(policy.release(.rewrite, at: 12), "The stop gesture's release must not start a new recording")
    }

    func testHybridLongPressStopsAtReleaseIncludingThresholdBoundary() {
        for releasedAt in [0.3, 0.6, 3] {
            var policy = ShortcutActivationPolicy()
            XCTAssertEqual(policy.press(.prompt, activation: .holdOrToggle, at: 0), event(.prompt, .start))
            _ = policy.updateRecordingState(.recording(.prompt))
            XCTAssertEqual(policy.release(.prompt, at: releasedAt), event(.prompt, .stop))
        }
    }

    func testReleaseBeforeAsynchronousStartWaitsForRecordingAndStopsOnlyOnce() {
        for activation in [ShortcutActivationMode.hold, .holdOrToggle] {
            var policy = ShortcutActivationPolicy()
            XCTAssertEqual(policy.press(.dictation, activation: activation, at: 0), event(.dictation, .start))
            XCTAssertNil(policy.release(.dictation, at: 0.5))
            XCTAssertNil(policy.updateRecordingState(.starting(.dictation)))
            XCTAssertEqual(policy.updateRecordingState(.recording(.dictation)), event(.dictation, .stop))
            XCTAssertNil(policy.updateRecordingState(.recording(.dictation)))
            XCTAssertNil(policy.release(.dictation, at: 1))
        }
    }

    func testReleaseWhileMicrophonePreparationIsAwaitingStopsWhenReady() {
        var policy = ShortcutActivationPolicy()
        _ = policy.press(.translation, activation: .hold, at: 0)
        _ = policy.updateRecordingState(.starting(.translation))
        XCTAssertNil(policy.release(.translation, at: 0.1))
        XCTAssertEqual(policy.updateRecordingState(.recording(.translation)), event(.translation, .stop))
    }

    func testHybridShortReleaseBeforeAsyncStartDoesNotQueueAStop() {
        var policy = ShortcutActivationPolicy()
        _ = policy.press(.dictation, activation: .holdOrToggle, at: 0)
        XCTAssertNil(policy.release(.dictation, at: 0.1))
        XCTAssertNil(policy.updateRecordingState(.starting(.dictation)))
        XCTAssertNil(policy.updateRecordingState(.recording(.dictation)))
    }

    func testRapidSecondPressCannotStartAnotherJobBeforeFirstCallbackBegins() {
        var policy = ShortcutActivationPolicy()
        XCTAssertEqual(policy.press(.dictation, activation: .holdOrToggle, at: 0), event(.dictation, .start))
        XCTAssertNil(policy.release(.dictation, at: 0.1))
        XCTAssertNil(policy.press(.dictation, activation: .holdOrToggle, at: 0.15))
        XCTAssertNil(policy.release(.dictation, at: 0.2))
        XCTAssertNil(policy.press(.translation, activation: .hold, at: 0.25))
    }

    func testBusyOrExternallyStartingAppDoesNotAcquireAHoldGesture() {
        for state in [ShortcutRecordingState.busy, .starting(.translation)] {
            var policy = ShortcutActivationPolicy()
            _ = policy.updateRecordingState(state)
            XCTAssertNil(policy.press(.dictation, activation: .hold, at: 0))
            _ = policy.updateRecordingState(.recording(.translation))
            XCTAssertNil(policy.release(.dictation, at: 1), "A busy key must not stop a later unrelated recording")
        }
    }

    func testStartupFailureDiscardsQueuedStopBeforeALaterRecording() {
        var policy = ShortcutActivationPolicy()
        _ = policy.press(.dictation, activation: .hold, at: 0)
        _ = policy.release(.dictation, at: 0.1)
        _ = policy.updateRecordingState(.starting(.dictation))
        _ = policy.updateRecordingState(.idle)
        XCTAssertNil(policy.updateRecordingState(.recording(.dictation)))
    }

    func testRejectedStartBeforeAnyPhaseTransitionAllowsTheNextGesture() {
        var policy = ShortcutActivationPolicy()
        _ = policy.press(.dictation, activation: .hold, at: 0)
        // The app must acknowledge an early preflight rejection with its unchanged idle state.
        _ = policy.updateRecordingState(.idle)
        XCTAssertNil(policy.release(.dictation, at: 0.1))
        XCTAssertEqual(policy.press(.dictation, activation: .hold, at: 1), event(.dictation, .start))
    }

    func testCancelWhileHeldSuppressesRepeatsAndStaleRelease() {
        var policy = ShortcutActivationPolicy()
        _ = policy.press(.dictation, activation: .hold, at: 0)
        _ = policy.updateRecordingState(.starting(.dictation))
        _ = policy.updateRecordingState(.idle)
        XCTAssertNil(policy.press(.dictation, activation: .hold, at: 0.5))
        XCTAssertNil(policy.release(.dictation, at: 1))
        XCTAssertEqual(policy.press(.dictation, activation: .hold, at: 2), event(.dictation, .start))
    }

    func testExternalStopBeforeKeyReleaseDoesNotRestartOrStopANewerRecording() {
        var policy = ShortcutActivationPolicy()
        _ = policy.press(.dictation, activation: .hold, at: 0)
        _ = policy.updateRecordingState(.recording(.dictation))
        _ = policy.updateRecordingState(.busy)
        _ = policy.updateRecordingState(.idle)
        _ = policy.updateRecordingState(.recording(.dictation))
        XCTAssertNil(policy.release(.dictation, at: 1))
    }

    func testDifferentRecordingModeCannotReceiveAnOldGesturesDeferredStop() {
        var policy = ShortcutActivationPolicy()
        _ = policy.press(.dictation, activation: .hold, at: 0)
        _ = policy.release(.dictation, at: 0.1)
        XCTAssertNil(policy.updateRecordingState(.starting(.translation)))
        XCTAssertNil(policy.updateRecordingState(.recording(.translation)))
    }

    func testAnotherShortcutCanStopAnExistingRecordingWithoutStartingItsOwnMode() {
        var policy = ShortcutActivationPolicy()
        _ = policy.updateRecordingState(.recording(.dictation))
        XCTAssertEqual(policy.press(.translation, activation: .holdOrToggle, at: 0), event(.dictation, .stop))
        _ = policy.updateRecordingState(.idle)
        XCTAssertNil(policy.release(.translation, at: 1))
    }

    func testSettingChangeInvalidatesGestureButSuppressesHeldKeyUntilRelease() {
        var policy = ShortcutActivationPolicy()
        _ = policy.press(.dictation, activation: .hold, at: 0)
        _ = policy.updateRecordingState(.recording(.dictation))
        policy.cancelGesture()
        XCTAssertNil(policy.press(.dictation, activation: .toggle, at: 0.5))
        XCTAssertNil(policy.release(.dictation, at: 1))
        XCTAssertEqual(policy.press(.dictation, activation: .toggle, at: 2), event(.dictation, .toggle))
    }

    func testReregisteringKeysClearsSuppressionWithoutForgettingRecordingState() {
        var policy = ShortcutActivationPolicy()
        _ = policy.press(.dictation, activation: .hold, at: 0)
        _ = policy.updateRecordingState(.recording(.dictation))
        policy.resetPressedKeys()
        XCTAssertEqual(policy.press(.dictation, activation: .hold, at: 1), event(.dictation, .stop))
    }

    private func event(_ mode: InputMode, _ action: ShortcutActivationAction) -> ShortcutActivationEvent {
        .init(mode: mode, action: action)
    }
}
