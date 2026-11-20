import AppKit
import XCTest
import OpenNoTypeCore
@testable import OpenNoType

@MainActor
final class AppNoticeTests: XCTestCase {
    private func makeModel() -> AppModel {
        var runtime = AppRuntime()
        runtime.readKey = { _ in nil }
        runtime.readDecisionKey = { _ in nil }
        runtime.accessibilityPermitted = { false }
        runtime.microphonePermission = { .notDetermined }
        runtime.hotkeyConflictWarnings = { _ in [] }
        return AppModel(runtime: runtime, startServices: false, preferences: Preferences())
    }

    func testPlainNoticeAssignmentDefaultsToPersistentInfo() {
        let model = makeModel()
        model.setNotice("Copied", kind: .success)
        XCTAssertEqual(model.noticeKind, .success)
        XCTAssertTrue(model.noticeKind.autoDismisses)

        model.notice = "Manual info notice"
        XCTAssertEqual(model.notice, "Manual info notice")
        XCTAssertEqual(model.noticeKind, .info)
        XCTAssertFalse(model.noticeKind.autoDismisses)

        model.setNotice("Conflict warning", kind: .warning)
        XCTAssertEqual(model.noticeKind, .warning)
        XCTAssertFalse(model.noticeKind.autoDismisses)

        model.notice = nil
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.noticeKind, .info)
    }

    #if DEBUG
    func testPreviewLaunchNoticeIsPersistentInfo() {
        let preview = AppLaunch.makePreviewModel()
        XCTAssertNotNil(preview.notice)
        XCTAssertEqual(preview.noticeKind, .info)
        XCTAssertFalse(preview.noticeKind.autoDismisses)
    }
    #endif

    func testFloatingToastAutoDismissRequiresSuccessVisibleAndUnhovered() {
        XCTAssertTrue(FloatingNoticeToast.shouldAutoDismiss(kind: .success, isWindowVisible: true, isHovered: false))
        XCTAssertFalse(FloatingNoticeToast.shouldAutoDismiss(kind: .success, isWindowVisible: false, isHovered: false))
        XCTAssertFalse(FloatingNoticeToast.shouldAutoDismiss(kind: .success, isWindowVisible: true, isHovered: true))
        XCTAssertFalse(FloatingNoticeToast.shouldAutoDismiss(kind: .info, isWindowVisible: true, isHovered: false))
        XCTAssertFalse(FloatingNoticeToast.shouldAutoDismiss(kind: .warning, isWindowVisible: true, isHovered: false))
    }

    func testWindowVisibilityRejectsNilHiddenTransparentAndMiniaturizedWindows() {
        _ = NSApplication.shared
        XCTAssertFalse(WindowVisibilityObserver.ObserverView.isVisible(nil))

        let hidden = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        hidden.isReleasedWhenClosed = false
        defer { hidden.close() }
        XCTAssertFalse(WindowVisibilityObserver.ObserverView.isVisible(hidden))

        hidden.alphaValue = 0
        XCTAssertFalse(WindowVisibilityObserver.ObserverView.isVisible(hidden))
    }
}
