import AppKit
import ApplicationServices
import XCTest
@testable import OpenNoType

@MainActor
final class InputFocusReadinessTests: XCTestCase {
    @MainActor private final class Environment {
        let app = InputTargetEnvironment.Application(pid: 41001, bundleID: "test.editor", bundleURL: nil)
        let otherApp = InputTargetEnvironment.Application(pid: 41002, bundleID: "test.other", bundleURL: nil)
        // Handles are local identities only; every observation is injected below.
        let original = AXUIElementCreateApplication(41001)
        let another = AXUIElementCreateSystemWide()
        var frontmost: InputTargetEnvironment.Application?
        var current: AXUIElement?
        var foreignOwner = false
        var unknownOwner = false
        var secure = false
        var secureField = false
        var cancelled = false
        var elapsed: TimeInterval = 0
        var pauses = 0
        var contentReads = 0
        var onPause: (() -> Void)?
        var onFocus: (() -> Void)?

        init() { frontmost = app }

        var operations: InputTargetEnvironment {
            InputTargetEnvironment(frontmostApplication: { self.frontmost }, focused: {
                self.onFocus?(); return self.current
            }, focusedIn: { _ in self.current }, elementPID: { _ in
                self.unknownOwner ? nil : self.foreignOwner ? self.otherApp.pid : self.app.pid
            }, secureInputActive: { self.secure }, isSecureField: { _ in self.secureField }, value: { _ in
                self.contentReads += 1; return "synthetic"
            }, selectedRange: { _ in self.contentReads += 1; return CFRange(location: 0, length: 0) },
                selectedText: { _ in self.contentReads += 1; return "" })
        }

        func target(appOnly: Bool = false) -> InputTarget {
            InputTarget(pid: app.pid, bundleID: app.bundleID, element: appOnly ? nil : original,
                        originalValue: nil, range: nil, selectedText: nil, context: nil)
        }

        func wait(for target: InputTarget? = nil) async -> InsertionBlockReason? {
            await TextInsertion.waitForInputFocus(of: target ?? self.target(), environment: operations,
                now: { self.elapsed }, pause: { seconds in
                    self.elapsed += seconds; self.pauses += 1; self.onPause?()
                    if self.pauses > 40 { XCTFail("Focus readiness must be bounded"); self.cancelled = true }
                }, isCancelled: { self.cancelled })
        }
    }

    func testTransientMissingFocusRecoversBeforeSubmissionWithoutReadingContents() async {
        let fixture = Environment()
        fixture.onPause = { if fixture.elapsed >= 0.1 { fixture.current = fixture.original } }
        let result = await fixture.wait()
        XCTAssertNil(result)
        XCTAssertGreaterThanOrEqual(fixture.elapsed, 0.1)
        XCTAssertLessThan(fixture.elapsed, 1.0)
        XCTAssertEqual(fixture.contentReads, 0)
    }

    func testSameAppFieldRecoveryKeepsOrdinaryAndStrictBindingPoliciesSeparate() async {
        let fixture = Environment()
        fixture.onPause = { fixture.current = fixture.another }
        let ordinary = fixture.target()
        let result = await fixture.wait(for: ordinary)
        XCTAssertNil(result, "Ordinary dictation may use the current field in its captured app")
        XCTAssertGreaterThanOrEqual(fixture.pauses, 1)
        XCTAssertNotNil(TextInsertion.submissionTarget(ordinary, element: fixture.another,
                                                       environment: fixture.operations))
        XCTAssertNil(TextInsertion.submissionTarget(ordinary.requiringSameElement(), element: fixture.another,
                                                    environment: fixture.operations),
                     "Waiting must not relax prompt/rewrite field identity")
    }

    func testForeignOrUnknownOwnerAfterFocusRecoveryIsBlockedWithoutContentReads() async {
        for unknown in [false, true] {
            let fixture = Environment()
            fixture.onPause = {
                fixture.current = fixture.another
                fixture.foreignOwner = !unknown; fixture.unknownOwner = unknown
            }
            let result = await fixture.wait()
            XCTAssertEqual(result, .targetChanged)
            XCTAssertGreaterThanOrEqual(fixture.pauses, 1)
            XCTAssertEqual(fixture.contentReads, 0)
        }
    }

    func testOtherAppTakingFocusDuringWaitStopsImmediately() async {
        let fixture = Environment()
        fixture.onPause = { fixture.frontmost = fixture.otherApp; fixture.current = fixture.original }
        let result = await fixture.wait()
        XCTAssertEqual(result, .targetChanged)
        XCTAssertEqual(fixture.pauses, 1)
        XCTAssertEqual(fixture.contentReads, 0)
    }

    func testSecureInputOrPasswordFocusDuringWaitStopsBeforeContentReads() async {
        for passwordField in [false, true] {
            let fixture = Environment()
            fixture.onPause = {
                fixture.current = fixture.original
                if passwordField { fixture.secureField = true } else { fixture.secure = true }
            }
            let result = await fixture.wait()
            XCTAssertEqual(result, .secureInput)
            XCTAssertEqual(fixture.pauses, 1)
            XCTAssertEqual(fixture.contentReads, 0)
        }
    }

    func testCancellationDuringWaitStopsBeforeAnySubmission() async {
        let fixture = Environment()
        fixture.onPause = { fixture.cancelled = true; fixture.current = fixture.original }
        let result = await fixture.wait()
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(fixture.pauses, 1)
        XCTAssertEqual(fixture.contentReads, 0)
    }

    func testPermanentlyMissingFocusHasABoundedDeadline() async {
        let fixture = Environment()
        let result = await fixture.wait()
        XCTAssertEqual(result, .targetChanged)
        XCTAssertGreaterThanOrEqual(fixture.elapsed, 0.3)
        XCTAssertLessThan(fixture.elapsed, 1.0)
        XCTAssertEqual(fixture.contentReads, 0)
    }

    func testAppOnlyCaptureWithNoAXFocusDoesNotWaitOrReadContents() async {
        let fixture = Environment()
        let result = await fixture.wait(for: fixture.target(appOnly: true))
        XCTAssertNil(result, "Editors without AX focus retain their app-only paste route")
        XCTAssertEqual(fixture.pauses, 0)
        XCTAssertEqual(fixture.contentReads, 0)
    }

    func testFocusObservationCannotHideAnAppSecurityOrCancellationChange() async {
        for change in 0..<3 {
            let fixture = Environment()
            fixture.current = fixture.original
            fixture.onFocus = {
                switch change {
                case 0: fixture.frontmost = fixture.otherApp
                case 1: fixture.secure = true
                default: fixture.cancelled = true
                }
            }
            let result = await fixture.wait()
            XCTAssertEqual(result, change == 0 ? .targetChanged : change == 1 ? .secureInput : .cancelled)
            XCTAssertEqual(fixture.pauses, 0)
            XCTAssertEqual(fixture.contentReads, 0)
        }
    }
}
