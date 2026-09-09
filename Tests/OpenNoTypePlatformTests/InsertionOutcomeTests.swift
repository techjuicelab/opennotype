import AppKit
import ApplicationServices
import XCTest
@testable import OpenNoType

@MainActor
final class InsertionOutcomeTests: XCTestCase {
    private final class Clock {
        var elapsed: TimeInterval = 0
        func advance(_ interval: TimeInterval) async { elapsed += interval }
    }

    private func probe(_ clock: Clock, value: @escaping () -> String?) -> InsertionVerification {
        InsertionVerification(readValue: value, now: { clock.elapsed }, pause: clock.advance)
    }

    private func fakeTarget(value: String?, range: CFRange?) -> InputTarget {
        InputTarget(pid: getpid(), bundleID: nil, element: AXUIElementCreateApplication(getpid()),
                    originalValue: value, range: range, selectedText: nil, context: nil)
    }

    func testCancellationBeforeSubmissionDoesNotReadAXOrPrepareClipboard() async {
        var stages: [String] = []
        let outcome = await TextInsertion.insertOutcome("synthetic text",
            at: fakeTarget(value: "", range: CFRange(location: 0, length: 0)),
            isCancelled: { true }, trace: { stages.append($0) })
        XCTAssertEqual(outcome, .notSubmitted(.cancelled))
        XCTAssertEqual(stages, ["notSubmitted.cancelled"])
    }

    func testOwnProcessIsNeverATargetAndBlocksBeforeAnySubmission() async {
        // The test process stands in for OpenNoType itself: no activation, no AX write, no clipboard use.
        for target in [fakeTarget(value: nil, range: CFRange(location: 0, length: 0)),
                       fakeTarget(value: "", range: nil),
                       fakeTarget(value: "", range: CFRange(location: 0, length: 0))] {
            var stages: [String] = []
            let outcome = await TextInsertion.insertOutcome("synthetic text", at: target,
                                                            trace: { stages.append($0) })
            XCTAssertEqual(outcome, .notSubmitted(.noTarget))
            XCTAssertEqual(stages, ["notSubmitted.noTarget"])
        }
    }

    func testMissingSnapshotNoLongerBlocksPolicyOrPasteRouting() {
        let target = InputTarget(pid: 1, bundleID: "com.example.editor", element: nil,
                                 originalValue: nil, range: nil, selectedText: nil, context: nil)
        XCTAssertNil(target.snapshot)
        XCTAssertEqual(TextInsertion.policy(for: target), .accessibilityThenPaste)
        XCTAssertEqual(TextInsertion.policy(for: InputTarget(pid: 1, bundleID: "com.google.antigravity", element: nil,
                                                             originalValue: nil, range: nil, selectedText: nil, context: nil)), .pasteOnly)
    }

    func testAcceptedAXWriteWithoutVisibleEditIsUnverifiedAndNeverPastes() async {
        let clock = Clock()
        let verification = probe(clock) { "unchanged" }
        var pasteCount = 0
        let outcome = await InsertionDelivery.perform(accessibility: { .accepted }, verifyAccessibility: {
            await verification.wait(for: "expected", method: .accessibility, isCancelled: { false })
        }, paste: { pasteCount += 1; return .confirmed(.paste) }, isCancelled: { false })

        XCTAssertEqual(outcome, .submittedUnverified(.accessibility, .timedOut))
        XCTAssertFalse(outcome.isConfirmed)
        XCTAssertTrue(outcome.wasSubmitted)
        XCTAssertEqual(pasteCount, 0, "An accepted AX write may arrive after the acknowledgement deadline")
        XCTAssertGreaterThanOrEqual(clock.elapsed, 1.0)
    }

    func testDelayedAXCannotDuplicateTextAfterVerificationDeadlineOrCancellation() async {
        // The review probe reproduced two copies when a queued AX edit arrived at 1.05 seconds,
        // just after the old fallback posted Cmd-V. Exercise the production delivery seam with time
        // on either side of its deadline; no real AX write or clipboard is involved.
        for submission: AccessibilitySubmission in [.accepted, .submissionUncertain] {
            for delay in [0.9, 1.05, 2.0] {
                for cancellationTime: TimeInterval? in [nil, 0.1] {
                    var elapsed: TimeInterval = 0
                    var pendingAX = false
                    var copies = 0
                    var pasteCount = 0
                    let pause: (TimeInterval) async -> Void = { interval in
                        elapsed += interval
                        if pendingAX, elapsed >= delay { copies += 1; pendingAX = false }
                    }
                    let verification = InsertionVerification(readValue: { copies == 0 ? "" : String(repeating: "입력", count: copies) },
                                                             now: { elapsed }, pause: pause)
                    let cancelled = { cancellationTime.map { elapsed >= $0 } ?? false }
                    let outcome = await InsertionDelivery.perform(accessibility: {
                        pendingAX = true
                        return submission
                    }, verifyAccessibility: {
                        await verification.wait(for: "입력", method: .accessibility, isCancelled: cancelled)
                    }, paste: {
                        pasteCount += 1; copies += 1
                        return .confirmed(.paste)
                    }, isCancelled: cancelled)

                    if cancellationTime != nil {
                        XCTAssertEqual(outcome, .submittedUnverified(.accessibility, .cancelled))
                    } else if delay < 1.0 {
                        XCTAssertEqual(outcome, .confirmed(.accessibility))
                    } else {
                        XCTAssertEqual(outcome, .submittedUnverified(.accessibility, .timedOut))
                    }
                    await pause(delay + 0.1)
                    XCTAssertEqual(pasteCount, 0, "An unchanged field does not prove the queued AX write was dropped")
                    XCTAssertEqual(copies, 1)
                }
            }
        }
    }

    func testOnlyExplicitAXRejectionsAllowPasteFallback() {
        XCTAssertEqual(TextInsertion.accessibilitySubmission(status: .success), .accepted)
        for status: AXError in [.cannotComplete, .failure] {
            XCTAssertEqual(TextInsertion.accessibilitySubmission(status: status), .submissionUncertain)
        }
        for status: AXError in [.attributeUnsupported, .invalidUIElement, .illegalArgument, .apiDisabled, .notImplemented] {
            XCTAssertEqual(TextInsertion.accessibilitySubmission(status: status), .unavailableOrRejected)
        }
        XCTAssertEqual(TextInsertion.accessibilitySubmission(status: .cannotComplete, alreadyObserved: true), .alreadyObserved)
    }

    func testPasteOnlyBundlesAndChromiumFlagRoutePastPasteWhileOthersKeepAXFirst() {
        for identifier in ["com.google.antigravity", "com.openai.codex", "com.microsoft.VSCode", "com.google.Chrome",
                           "com.apple.Terminal", "com.tinyspeck.slackmacgap", "com.hnc.Discord"] {
            XCTAssertEqual(InsertionPolicy.forBundleID(identifier), .pasteOnly, identifier)
        }
        for identifier in [nil, "", "com.google.antigravity.preview", "com.apple.Notes", "com.kakao.KakaoTalkMac"] {
            XCTAssertEqual(InsertionPolicy.forBundleID(identifier), .accessibilityThenPaste, identifier ?? "nil")
            XCTAssertEqual(InsertionPolicy.forBundleID(identifier, usesChromium: true), .pasteOnly, identifier ?? "nil")
        }
    }

    func testChromiumRuntimeDetectionDrivesPolicyForUnknownBundles() throws {
        XCTAssertFalse(TextInsertion.usesChromiumRuntime(bundleURL: nil))
        XCTAssertFalse(TextInsertion.usesChromiumRuntime(bundleURL: URL(fileURLWithPath: "/System/Applications/TextEdit.app")))
        for frameworkName in ["Electron Framework.framework", "Google Chrome Framework.framework", "Chromium Embedded Framework.framework"] {
            let fake = FileManager.default.temporaryDirectory.appendingPathComponent("OpenNoTypeChromium-\(UUID().uuidString).app")
            try FileManager.default.createDirectory(at: fake.appendingPathComponent("Contents/Frameworks/" + frameworkName),
                                                    withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: fake) }
            XCTAssertTrue(TextInsertion.usesChromiumRuntime(bundleURL: fake), frameworkName)
            let target = InputTarget(pid: 1, bundleID: "com.example.unknown", bundleURL: fake, element: nil,
                                     originalValue: nil, range: nil, selectedText: nil, context: nil)
            XCTAssertEqual(TextInsertion.policy(for: target), .pasteOnly, frameworkName)
        }
        let native = FileManager.default.temporaryDirectory.appendingPathComponent("OpenNoTypeNative-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: native.appendingPathComponent("Contents/Frameworks/Sparkle.framework"),
                                                withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: native) }
        XCTAssertFalse(TextInsertion.usesChromiumRuntime(bundleURL: native))
    }

    func testPasteOnlyPolicySkipsAXWriteAndConfirmsOneMockPaste() async {
        for identifier in ["com.google.antigravity", "com.openai.codex"] {
            let clock = Clock()
            let verification = probe(clock) { clock.elapsed >= 0.05 ? "expected" : "" }
            var axCalls = 0
            var verificationCalls = 0
            var pasteCalls = 0
            let outcome = await InsertionDelivery.perform(policy: .forBundleID(identifier), accessibility: {
                axCalls += 1; return .accepted // An accepted-but-ineffective AX write must not be attempted.
            }, verifyAccessibility: {
                verificationCalls += 1; return .submittedUnverified(.accessibility, .timedOut)
            }, paste: {
                pasteCalls += 1
                return await verification.wait(for: "expected", method: .paste, isCancelled: { false })
            }, isCancelled: { false })

            XCTAssertEqual(outcome, .confirmed(.paste))
            XCTAssertEqual(axCalls, 0)
            XCTAssertEqual(verificationCalls, 0)
            XCTAssertEqual(pasteCalls, 1)
            XCTAssertGreaterThanOrEqual(clock.elapsed, 0.2)
        }
    }

    func testPasteOnlyNeverRetriesAfterBlockedOrUnverifiedPaste() async {
        for result: InsertionOutcome in [.notSubmitted(.targetChanged), .notSubmitted(.clipboardUnavailable),
                                         .submittedUnverified(.paste, .timedOut), .submittedUnverified(.paste, .cancelled)] {
            var axCalls = 0
            var pasteCalls = 0
            let outcome = await InsertionDelivery.perform(policy: .pasteOnly, accessibility: {
                axCalls += 1; return .accepted
            }, verifyAccessibility: {
                XCTFail("Paste-only policy must never verify an AX write"); return .confirmed(.accessibility)
            }, paste: { pasteCalls += 1; return result }, isCancelled: { false })

            XCTAssertEqual(outcome, result)
            XCTAssertEqual(axCalls, 0)
            XCTAssertEqual(pasteCalls, 1)
        }
    }

    func testDelayedAXAcknowledgementConfirmsWithoutKeyboardFallback() async {
        let clock = Clock()
        let verification = probe(clock) { clock.elapsed >= 0.4 ? "prefix inserted suffix" : "prefix suffix" }
        var pasteCount = 0
        let outcome = await InsertionDelivery.perform(accessibility: { .accepted }, verifyAccessibility: {
            await verification.wait(for: "prefix inserted suffix", method: .accessibility, isCancelled: { false })
        }, paste: { pasteCount += 1; return .confirmed(.paste) }, isCancelled: { false })

        XCTAssertEqual(outcome, .confirmed(.accessibility))
        XCTAssertEqual(pasteCount, 0)
        XCTAssertGreaterThanOrEqual(clock.elapsed, 0.4)
    }

    func testCancellationAfterAcceptedAXSubmissionIsNotReportedAsNeverSubmitted() async {
        let clock = Clock()
        let verification = probe(clock) { nil }
        var pasteCount = 0
        let outcome = await InsertionDelivery.perform(accessibility: { .accepted }, verifyAccessibility: {
            await verification.wait(for: "expected", method: .accessibility, isCancelled: { clock.elapsed >= 0.1 })
        }, paste: { pasteCount += 1; return .confirmed(.paste) }, isCancelled: { false })

        XCTAssertEqual(outcome, .submittedUnverified(.accessibility, .cancelled))
        XCTAssertEqual(pasteCount, 0)
    }

    func testBlockedTargetNeverRunsVerificationOrPaste() async {
        var verificationCount = 0
        var pasteCount = 0
        let outcome = await InsertionDelivery.perform(accessibility: { .blocked(.targetChanged) }, verifyAccessibility: {
            verificationCount += 1; return .confirmed(.accessibility)
        }, paste: { pasteCount += 1; return .confirmed(.paste) }, isCancelled: { false })

        XCTAssertEqual(outcome, .notSubmitted(.targetChanged))
        XCTAssertEqual(verificationCount, 0)
        XCTAssertEqual(pasteCount, 0)
    }

    func testUnsupportedOrRejectedAXWriteCanUseExistingPastePathOnce() async {
        var verificationCount = 0
        var pasteCount = 0
        let outcome = await InsertionDelivery.perform(accessibility: { .unavailableOrRejected }, verifyAccessibility: {
            verificationCount += 1; return .confirmed(.accessibility)
        }, paste: { pasteCount += 1; return .notSubmitted(.clipboardUnavailable) }, isCancelled: { false })

        XCTAssertEqual(outcome, .notSubmitted(.clipboardUnavailable))
        XCTAssertEqual(verificationCount, 0)
        XCTAssertEqual(pasteCount, 1)
    }

    func testAlreadyObservedAXEditNeverPastesAgainEvenAfterCancellation() async {
        var pasteCount = 0
        let outcome = await InsertionDelivery.perform(accessibility: { .alreadyObserved }, verifyAccessibility: {
            XCTFail("An already observed edit needs no second verification"); return .confirmed(.accessibility)
        }, paste: { pasteCount += 1; return .confirmed(.paste) }, isCancelled: { true })

        XCTAssertEqual(outcome, .submittedUnverified(.accessibility, .cancelled))
        XCTAssertEqual(pasteCount, 0)
    }

    func testPostedPasteWithUnreadableValueIsUnverifiedAfterFullLeaseDeadline() async {
        let clock = Clock()
        let verification = probe(clock) { nil }
        let outcome = await verification.wait(for: "expected", method: .paste, isCancelled: { false })

        XCTAssertEqual(outcome, .submittedUnverified(.paste, .timedOut))
        XCTAssertGreaterThanOrEqual(clock.elapsed, 3.0)
        XCTAssertLessThan(clock.elapsed, 3.1)
    }

    func testPasteAcknowledgementKeepsMinimumClipboardGracePeriod() async {
        let clock = Clock()
        let verification = probe(clock) { "expected" }
        let outcome = await verification.wait(for: "expected", method: .paste, isCancelled: { false })

        XCTAssertEqual(outcome, .confirmed(.paste))
        XCTAssertGreaterThanOrEqual(clock.elapsed, 0.2)
        XCTAssertLessThan(clock.elapsed, 0.3)
    }

    func testCancellationAfterPasteDispatchDoesNotEndClipboardLeaseEarly() async {
        let clock = Clock()
        let verification = probe(clock) { nil }
        let outcome = await verification.wait(for: "expected", method: .paste, isCancelled: { true })

        XCTAssertEqual(outcome, .submittedUnverified(.paste, .cancelled))
        XCTAssertGreaterThanOrEqual(clock.elapsed, 3.0)
    }

    func testChangedOutsideTextCannotFalselyAcknowledgeInsertion() async {
        let clock = Clock()
        let verification = probe(clock) { "changed prefix inserted suffix" }
        let outcome = await verification.wait(for: "prefix inserted suffix", method: .paste, isCancelled: { false })

        XCTAssertEqual(outcome, .submittedUnverified(.paste, .timedOut))
    }

    func testAcknowledgementRequiresExactValueWithSnapshotAndChangedContainingValueWithout() {
        let exact = TextInsertion.acknowledgement(expected: "앞 받아쓴 문장 뒤", original: "앞  뒤", text: "받아쓴 문장")
        XCTAssertTrue(exact("앞 받아쓴 문장 뒤"))
        XCTAssertFalse(exact("앞  뒤 받아쓴 문장"), "Text elsewhere in the field does not satisfy an exact snapshot")
        XCTAssertFalse(exact(nil))
        let loose = TextInsertion.acknowledgement(expected: nil, original: "받아쓴 문장", text: "받아쓴 문장")
        XCTAssertFalse(loose("받아쓴 문장"), "A field that already held the text at capture time proves nothing")
        XCTAssertTrue(loose("받아쓴 문장 받아쓴 문장"))
        XCTAssertFalse(loose(nil))
        XCTAssertFalse(loose("다른 내용"))
    }

    func testLoosePredicateWithoutSnapshotAcceptsContainingValueButNotUnchangedOne() async {
        let text = "받아쓴 문장"
        let original = "이전 내용"
        let acknowledged = TextInsertion.acknowledgement(expected: nil, original: original, text: text)
        let unchanged = Clock()
        let stale = await probe(unchanged) { original }.wait(method: .paste, isCancelled: { false }, acknowledged: acknowledged)
        XCTAssertEqual(stale, .submittedUnverified(.paste, .timedOut))

        let updated = Clock()
        let visible = await probe(updated) { original + " " + text }.wait(method: .paste, isCancelled: { false }, acknowledged: acknowledged)
        XCTAssertEqual(visible, .confirmed(.paste))
        XCTAssertLessThan(updated.elapsed, 0.3)
    }
}
