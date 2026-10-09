import AppKit
import ApplicationServices
import XCTest
@testable import OpenNoType

@MainActor
final class InputTargetSafetyTests: XCTestCase {
    @MainActor private final class Environment {
        let appA = InputTargetEnvironment.Application(pid: 41001, bundleID: "test.allowed", bundleURL: nil)
        let appB = InputTargetEnvironment.Application(pid: 41002, bundleID: "test.private", bundleURL: nil)
        // Creating handles is local. All reads are supplied below; no AX process is contacted.
        let elementA = AXUIElementCreateApplication(41001)
        let elementB = AXUIElementCreateApplication(41002)
        let secondElementA = AXUIElementCreateSystemWide()
        var frontmost: InputTargetEnvironment.Application?
        var focusedElement: AXUIElement?
        var resolve: ((pid_t) async -> AXUIElement?)?
        var ownerLookupFails = false
        var secure = false
        var secureField = false
        var text = "앞 선택 뒤"
        var valueUnavailable = false
        var range: CFRange? = CFRange(location: 2, length: 2)
        var contentReads = 0
        var onValueRead: (() -> Void)?

        init() { frontmost = appA; focusedElement = elementA }

        var operations: InputTargetEnvironment {
            InputTargetEnvironment(frontmostApplication: { self.frontmost }, focused: { self.focusedElement },
                focusedIn: { pid in
                    if let resolve = self.resolve { return await resolve(pid) }
                    return self.focusedElement
                }, elementPID: { element in
                    guard !self.ownerLookupFails else { return nil }
                    return CFEqual(element, self.elementA) || CFEqual(element, self.secondElementA) ? self.appA.pid : self.appB.pid
                }, secureInputActive: { self.secure }, isSecureField: { _ in self.secureField }, value: { _ in
                    self.contentReads += 1; self.onValueRead?(); return self.valueUnavailable ? nil : self.text
                }, selectedRange: { _ in self.contentReads += 1; return self.range },
                selectedText: { _ in self.contentReads += 1; return "선택" })
        }

        var target: InputTarget {
            InputTarget(pid: appA.pid, bundleID: appA.bundleID, element: elementA,
                        originalValue: "앞 선택 뒤", range: CFRange(location: 2, length: 2),
                        selectedText: "선택", context: "앞 ")
        }
    }

    func testCaptureKeepsContextOnlyForTheConsistentlyOwnedAllowedApp() async throws {
        let fixture = Environment()
        let captured = await TextInsertion.capture(allowedContextApps: ["test.allowed"], environment: fixture.operations)
        let target = try XCTUnwrap(captured)
        XCTAssertEqual(target.pid, fixture.appA.pid)
        XCTAssertEqual(target.context, "앞 ")
        XCTAssertEqual(target.selectedText, "선택")
        let unallowed = await TextInsertion.capture(allowedContextApps: [], environment: fixture.operations)
        XCTAssertNil(unallowed?.context)
    }

    func testFocusChangesDuringAwaitCannotCapturePrivateAppUnderAllowedAppIdentity() async {
        let fixture = Environment()
        fixture.resolve = { pid in
            XCTAssertEqual(pid, fixture.appA.pid)
            await Task.yield()
            fixture.frontmost = fixture.appB
            fixture.focusedElement = fixture.elementB
            return fixture.elementB
        }
        let target = await TextInsertion.capture(allowedContextApps: ["test.allowed"], environment: fixture.operations)
        XCTAssertNil(target)
        XCTAssertEqual(fixture.contentReads, 0, "Foreign field contents must not be read before ownership validation")
    }

    func testForeignOrUnknownElementOwnerIsRejectedEvenWhenFrontmostAppDidNotChange() async {
        for unknownOwner in [false, true] {
            let fixture = Environment()
            fixture.focusedElement = fixture.elementB
            fixture.ownerLookupFails = unknownOwner
            let target = await TextInsertion.capture(allowedContextApps: ["test.allowed"], environment: fixture.operations)
            XCTAssertNil(target)
            XCTAssertEqual(fixture.contentReads, 0)
        }
    }

    func testCaptureRechecksAppAfterReadingAttributes() async {
        let fixture = Environment()
        fixture.onValueRead = { fixture.frontmost = fixture.appB }
        let target = await TextInsertion.capture(allowedContextApps: ["test.allowed"], environment: fixture.operations)
        XCTAssertNil(target)
    }

    func testSecureInputEnabledDuringCaptureDoesNotReadFieldContents() async {
        let fixture = Environment()
        fixture.resolve = { _ in fixture.secure = true; return fixture.elementA }
        let target = await TextInsertion.capture(allowedContextApps: ["test.allowed"], environment: fixture.operations)
        XCTAssertEqual(target?.secureField, true)
        XCTAssertNil(target?.originalValue)
        XCTAssertNil(target?.selectedText)
        XCTAssertNil(target?.context)
        XCTAssertEqual(fixture.contentReads, 0)
    }

    func testUnreadableElementStillCapturesStableAppWithoutContext() async throws {
        let fixture = Environment()
        fixture.focusedElement = nil
        let captured = await TextInsertion.capture(allowedContextApps: ["test.allowed"], environment: fixture.operations)
        let target = try XCTUnwrap(captured)
        XCTAssertEqual(target.pid, fixture.appA.pid)
        XCTAssertNil(target.element)
        XCTAssertNil(target.context)
        XCTAssertEqual(fixture.contentReads, 0)
    }

    func testRewriteRequiresSameFieldOriginalValueAndSelection() {
        let fixture = Environment()
        let target = fixture.target
        XCTAssertTrue(TextInsertion.targetIsUnchanged(target, environment: fixture.operations))
        fixture.range = CFRange(location: 5, length: 1)
        XCTAssertFalse(TextInsertion.targetIsUnchanged(target, environment: fixture.operations), "Selecting B must block replacement generated from A")
        fixture.range = CFRange(location: 2, length: 2)
        fixture.text = "앞 수정 뒤"
        XCTAssertFalse(TextInsertion.targetIsUnchanged(target, environment: fixture.operations), "Editing the source text invalidates the rewrite request")
        fixture.text = "앞 선택 뒤"
        fixture.focusedElement = fixture.elementB
        XCTAssertFalse(TextInsertion.targetIsUnchanged(target, environment: fixture.operations))
        fixture.focusedElement = fixture.elementA
        fixture.frontmost = fixture.appB
        XCTAssertFalse(TextInsertion.targetIsUnchanged(target, environment: fixture.operations))
    }

    func testRewriteRejectsMissingSnapshotUnknownOwnerAndSecureField() {
        let fixture = Environment()
        let noSnapshot = InputTarget(pid: fixture.appA.pid, bundleID: fixture.appA.bundleID, element: fixture.elementA,
                                     originalValue: nil, range: nil, selectedText: "선택", context: nil)
        XCTAssertFalse(TextInsertion.targetIsUnchanged(noSnapshot, environment: fixture.operations))
        fixture.ownerLookupFails = true
        XCTAssertFalse(TextInsertion.targetIsUnchanged(fixture.target, environment: fixture.operations))
        fixture.ownerLookupFails = false
        fixture.secureField = true
        XCTAssertFalse(TextInsertion.targetIsUnchanged(fixture.target, environment: fixture.operations))
        XCTAssertEqual(fixture.contentReads, 0)
    }

    func testRewriteRechecksSelectionAndFocusAfterPotentiallySlowValueRead() {
        let fixture = Environment()
        fixture.onValueRead = { fixture.range = CFRange(location: 5, length: 1) }
        XCTAssertFalse(TextInsertion.targetIsUnchanged(fixture.target, environment: fixture.operations))
        fixture.range = CFRange(location: 2, length: 2)
        fixture.onValueRead = { fixture.frontmost = fixture.appB }
        XCTAssertFalse(TextInsertion.targetIsUnchanged(fixture.target, environment: fixture.operations))
    }

    func testSubmissionUsesTheCurrentCaretAndExistingTextForExactAcknowledgement() throws {
        let fixture = Environment()
        let captured = fixture.target
        fixture.text = "앞 선택 뒤 추가🙂"
        fixture.range = CFRange(location: (fixture.text as NSString).length, length: 0)
        let current = try XCTUnwrap(TextInsertion.submissionTarget(captured, element: fixture.elementA, environment: fixture.operations))
        let expected = try XCTUnwrap(current.snapshot).expectedValue(inserting: " 받아쓰기")
        let acknowledged = TextInsertion.acknowledgement(expected: expected, original: current.originalValue, text: " 받아쓰기")
        XCTAssertEqual(expected, "앞 선택 뒤 추가🙂 받아쓰기")
        XCTAssertTrue(acknowledged(expected))
        XCTAssertFalse(acknowledged(try XCTUnwrap(captured.snapshot).expectedValue(inserting: " 받아쓰기")))
        XCTAssertFalse(TextInsertion.targetIsUnchanged(captured, environment: fixture.operations), "A rewrite must still reject the changed request selection")
    }

    func testSubmissionTracksTheCurrentFieldAndKeepsUnreadableSnapshotUnreadable() throws {
        let fixture = Environment()
        fixture.focusedElement = fixture.secondElementA
        fixture.text = "다른 입력창"
        fixture.range = CFRange(location: 6, length: 0)
        let current = try XCTUnwrap(TextInsertion.submissionTarget(fixture.target, element: fixture.secondElementA, environment: fixture.operations))
        XCTAssertTrue(CFEqual(try XCTUnwrap(current.element), fixture.secondElementA))
        XCTAssertEqual(current.originalValue, "다른 입력창")
        fixture.valueUnavailable = true
        fixture.range = nil
        let unreadable = try XCTUnwrap(TextInsertion.submissionTarget(fixture.target, element: fixture.secondElementA, environment: fixture.operations))
        XCTAssertNil(unreadable.originalValue)
        XCTAssertNil(unreadable.snapshot, "Never fall back to the recording-start snapshot for correction learning")
    }

    func testSubmissionRejectsFocusAndSecurityChangesBeforeAnyContentRead() {
        for mutation in [0, 1, 2, 3] {
            let fixture = Environment()
            switch mutation {
            case 0: fixture.frontmost = fixture.appB
            case 1: fixture.focusedElement = fixture.elementB
            case 2: fixture.secure = true
            default: fixture.secureField = true
            }
            XCTAssertNil(TextInsertion.submissionTarget(fixture.target, element: fixture.elementA, environment: fixture.operations))
            XCTAssertEqual(fixture.contentReads, 0)
        }
    }

    func testSubmissionRejectsChangesDuringAttributeReads() {
        for mutation in [0, 1, 2] {
            let fixture = Environment()
            fixture.onValueRead = {
                switch mutation {
                case 0: fixture.frontmost = fixture.appB
                case 1: fixture.focusedElement = fixture.secondElementA
                default: fixture.secure = true
                }
            }
            XCTAssertNil(TextInsertion.submissionTarget(fixture.target, element: fixture.elementA, environment: fixture.operations))
        }
    }

    func testSameElementBindingAllowsCaretAndValueChangesWithoutRetargetingTheField() {
        let fixture = Environment()
        let bound = fixture.target.requiringSameElement()
        fixture.text = "사용자가 같은 입력창에 추가로 쓴 내용"
        fixture.range = CFRange(location: 7, length: 0)

        XCTAssertTrue(TextInsertion.sameElementIsCurrent(bound, environment: fixture.operations))
        XCTAssertEqual(fixture.contentReads, 0, "Identity checks must not require an unchanged text snapshot")
        XCTAssertFalse(TextInsertion.targetIsUnchanged(bound, environment: fixture.operations))

        fixture.focusedElement = fixture.secondElementA
        XCTAssertFalse(TextInsertion.sameElementIsCurrent(bound, environment: fixture.operations))
    }

    func testSameElementBindingRejectsForeignUnknownAndSecureFocus() {
        for mutation in 0..<6 {
            let fixture = Environment()
            let bound = fixture.target.requiringSameElement()
            switch mutation {
            case 0: fixture.frontmost = fixture.appB
            case 1: fixture.focusedElement = fixture.elementB
            case 2: fixture.ownerLookupFails = true
            case 3: fixture.secure = true
            case 4: fixture.secureField = true
            default: fixture.focusedElement = nil
            }
            XCTAssertFalse(TextInsertion.sameElementIsCurrent(bound, environment: fixture.operations))
            XCTAssertEqual(fixture.contentReads, 0)
        }
    }

    func testSameElementBindingPreservesAppOnlyCaptureButRejectsChangedElementAvailability() {
        let fixture = Environment()
        let appOnly = InputTarget(pid: fixture.appA.pid, bundleID: fixture.appA.bundleID, element: nil,
                                  originalValue: nil, range: nil, selectedText: nil, context: nil,
                                  requiresSameElement: true)
        XCTAssertFalse(TextInsertion.sameElementIsCurrent(appOnly, environment: fixture.operations))
        fixture.focusedElement = nil
        XCTAssertTrue(TextInsertion.sameElementIsCurrent(appOnly, environment: fixture.operations), "When both AX observations are unavailable, only the app identity can be checked")
        fixture.frontmost = fixture.appB
        XCTAssertFalse(TextInsertion.sameElementIsCurrent(appOnly, environment: fixture.operations))
        XCTAssertEqual(fixture.contentReads, 0)
    }

    func testSameElementIdentityRechecksAppAndSecurityAfterTheFocusQuery() {
        for secure in [false, true] {
            let fixture = Environment()
            var operations = fixture.operations
            operations.focused = {
                if secure { fixture.secure = true }
                else { fixture.frontmost = fixture.appB }
                return fixture.elementA
            }
            XCTAssertFalse(TextInsertion.sameElementIsCurrent(fixture.target.requiringSameElement(), environment: operations))
            XCTAssertEqual(fixture.contentReads, 0)
        }
    }

    func testSameElementSubmissionBlocksSameAppRetargetingButOrdinaryDictationStillAllowsIt() throws {
        let fixture = Environment()
        fixture.focusedElement = fixture.secondElementA
        let bound = fixture.target.requiringSameElement()

        XCTAssertNil(TextInsertion.submissionTarget(bound, element: fixture.secondElementA, environment: fixture.operations))
        XCTAssertEqual(fixture.contentReads, 0)
        let ordinary = try XCTUnwrap(TextInsertion.submissionTarget(fixture.target, element: fixture.secondElementA, environment: fixture.operations))
        XCTAssertFalse(ordinary.requiresSameElement)
        XCTAssertTrue(CFEqual(try XCTUnwrap(ordinary.element), fixture.secondElementA))
    }

    func testSameElementSubmissionCannotBypassTheBindingWithBackgroundFallback() {
        let fixture = Environment()
        let bound = fixture.target.requiringSameElement()
        XCTAssertNil(TextInsertion.submissionTarget(bound, element: fixture.secondElementA,
                                                    requireFocused: false, environment: fixture.operations))
        fixture.frontmost = fixture.appB
        XCTAssertNil(TextInsertion.submissionTarget(bound, element: fixture.elementA,
                                                    requireFocused: false, environment: fixture.operations))
        XCTAssertEqual(fixture.contentReads, 0)
    }

    func testSameElementBindingSurvivesObserversAndCurrentSubmissionSnapshots() throws {
        let fixture = Environment()
        XCTAssertFalse(fixture.target.requiresSameElement)
        var submitted: InputTarget?
        let bound = fixture.target.observingSubmission { submitted = $0 }.requiringSameElement()
        let observed = bound.observingSubmission { submitted = $0 }
        XCTAssertTrue(observed.requiresSameElement)
        XCTAssertEqual(observed.originalValue, fixture.target.originalValue)
        XCTAssertEqual(observed.selectedText, fixture.target.selectedText)
        fixture.text = "같은 입력창의 새 내용"
        let current = try XCTUnwrap(TextInsertion.submissionTarget(observed, element: fixture.elementA,
                                                                 environment: fixture.operations))
        XCTAssertTrue(current.requiresSameElement)
        XCTAssertEqual(current.originalValue, fixture.text)
        XCTAssertNil(current.selectedText)
        XCTAssertNil(current.context)
        XCTAssertNil(current.submissionObserver)
        observed.submissionObserver?(current)
        XCTAssertTrue(submitted?.requiresSameElement == true)
    }

    func testSameElementSubmissionRejectsFocusChangesDuringLocalSnapshotReads() {
        let fixture = Environment()
        let bound = fixture.target.requiringSameElement()
        fixture.onValueRead = { fixture.focusedElement = fixture.secondElementA }
        XCTAssertNil(TextInsertion.submissionTarget(bound, element: fixture.elementA, environment: fixture.operations))
    }

    func testSubmissionSnapshotDoesNotRetainOrForwardTheObserver() throws {
        let fixture = Environment()
        var submitted: InputTarget?
        let observed = fixture.target.observingSubmission { submitted = $0 }
        let current = try XCTUnwrap(TextInsertion.submissionTarget(observed, element: fixture.elementA, environment: fixture.operations))
        XCTAssertNil(current.submissionObserver)
        observed.submissionObserver?(current)
        XCTAssertEqual(submitted?.originalValue, fixture.text)
        XCTAssertNil(submitted?.submissionObserver)
    }
}
