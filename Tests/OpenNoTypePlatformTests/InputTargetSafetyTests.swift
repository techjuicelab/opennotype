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
        var frontmost: InputTargetEnvironment.Application?
        var focusedElement: AXUIElement?
        var resolve: ((pid_t) async -> AXUIElement?)?
        var ownerLookupFails = false
        var secure = false
        var secureField = false
        var text = "앞 선택 뒤"
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
                    return CFEqual(element, self.elementA) ? self.appA.pid : self.appB.pid
                }, secureInputActive: { self.secure }, isSecureField: { _ in self.secureField }, value: { _ in
                    self.contentReads += 1; self.onValueRead?(); return self.text
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
}
