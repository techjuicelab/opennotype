import AppKit
import XCTest
@testable import OpenNoType

@MainActor
final class MenuBarLaunchTests: XCTestCase {
    private func makeWindow() -> LaunchTrackingWindow {
        _ = NSApplication.shared
        let window = LaunchTrackingWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                                          styleMask: [.titled, .closable, .resizable],
                                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("main")
        return window
    }

    func testFirstManagerStaysTransparentUntilItsSurfaceIsReadyThenHides() throws {
        let window = makeWindow(), scheduler = LaunchScheduler()
        defer { window.close() }
        var surfaceReady = false
        let windows = AppWindows(isPreview: false, hasSurface: { _ in surfaceReady },
                                 schedule: { scheduler.enqueue($0) }, activate: {})

        windows.attach(window)
        XCTAssertTrue(windows.window === window)
        XCTAssertFalse(window.isRestorable)
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertEqual(window.orderOutCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 1)

        try scheduler.runNext()
        XCTAssertEqual(window.alphaValue, 0, "An unfinished surface must not flash on screen")
        XCTAssertEqual(window.orderOutCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 1)

        surfaceReady = true
        try scheduler.runNext()
        XCTAssertEqual(window.alphaValue, 1, "An explicit open must later use normal opacity")
        XCTAssertEqual(window.orderOutCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testExplicitOpenWhileWaitingCannotBeHiddenByThePendingCallback() throws {
        let window = makeWindow(), scheduler = LaunchScheduler()
        defer { window.close() }
        var surfaceReady = false, openCount = 0, activationCount = 0
        let windows = AppWindows(isPreview: false, hasSurface: { _ in surfaceReady },
                                 schedule: { scheduler.enqueue($0) }, activate: { activationCount += 1 })
        windows.connectWindowOpening { openCount += 1 }
        windows.attach(window)
        XCTAssertEqual(window.alphaValue, 0)

        windows.show()
        XCTAssertEqual(window.alphaValue, 1)
        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(window.makeKeyAndOrderFrontCount, 1)

        surfaceReady = true
        try scheduler.runNext()
        XCTAssertEqual(window.alphaValue, 1)
        XCTAssertEqual(window.orderOutCount, 0, "The user's open wins over a delayed launch suppression")
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testExplicitOpenBeforeAttachmentDoesNotSuppressTheNewManager() {
        let window = makeWindow(), scheduler = LaunchScheduler()
        defer { window.close() }
        let windows = AppWindows(isPreview: false, hasSurface: { _ in false },
                                 schedule: { scheduler.enqueue($0) }, activate: {})
        windows.connectWindowOpening { [weak windows] in windows?.attach(window) }

        windows.show()

        XCTAssertTrue(windows.window === window)
        XCTAssertEqual(window.alphaValue, 1)
        XCTAssertEqual(window.orderOutCount, 0)
        XCTAssertEqual(window.makeKeyAndOrderFrontCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testAttachingAgainAfterLaunchSuppressionDoesNotHideAnOpenedManager() {
        let window = makeWindow(), scheduler = LaunchScheduler()
        defer { window.close() }
        let windows = AppWindows(isPreview: false, hasSurface: { _ in true },
                                 schedule: { scheduler.enqueue($0) }, activate: {})
        windows.attach(window)
        XCTAssertEqual(window.orderOutCount, 1)

        windows.show()
        windows.attach(window)

        XCTAssertEqual(window.alphaValue, 1)
        XCTAssertEqual(window.orderOutCount, 1)
        XCTAssertEqual(window.makeKeyAndOrderFrontCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testReplacementManagerIsNotTreatedAsAnotherAutomaticLaunch() {
        let first = makeWindow(), replacement = makeWindow(), scheduler = LaunchScheduler()
        defer { first.close(); replacement.close() }
        let windows = AppWindows(isPreview: false, hasSurface: { _ in true },
                                 schedule: { scheduler.enqueue($0) }, activate: {})
        windows.attach(first)
        XCTAssertEqual(first.orderOutCount, 1)

        windows.attach(replacement)

        XCTAssertTrue(windows.window === replacement)
        XCTAssertFalse(replacement.isRestorable)
        XCTAssertEqual(replacement.alphaValue, 1)
        XCTAssertEqual(replacement.orderOutCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testPreviewManagerKeepsItsInitialVisibilityAndOpacity() {
        let window = makeWindow(), scheduler = LaunchScheduler()
        defer { window.close() }
        let windows = AppWindows(isPreview: true, hasSurface: { _ in false },
                                 schedule: { scheduler.enqueue($0) }, activate: {})

        windows.attach(window)

        XCTAssertTrue(windows.window === window)
        XCTAssertEqual(window.alphaValue, 1)
        XCTAssertEqual(window.orderOutCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testMissingSurfaceEventuallyRestoresOpacityAndAllowsAnExplicitOpen() throws {
        let window = makeWindow(), scheduler = LaunchScheduler()
        defer { window.close() }
        let windows = AppWindows(isPreview: false, hasSurface: { _ in false },
                                 schedule: { scheduler.enqueue($0) }, activate: {})
        windows.attach(window)
        XCTAssertEqual(window.alphaValue, 0)

        // Keep this bounded so an accidental unending retry fails without hanging the suite.
        for _ in 0..<100 where scheduler.pendingCount > 0 { try scheduler.runNext() }

        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(window.alphaValue, 1, "A missing WindowServer surface must not strand a transparent manager")
        XCTAssertEqual(window.orderOutCount, 0)
        windows.show()
        XCTAssertEqual(window.makeKeyAndOrderFrontCount, 1)
        XCTAssertEqual(window.alphaValue, 1)
    }

    func testPanelsAndStatusWindowsCannotReplaceTheManager() {
        let manager = makeWindow(), scheduler = LaunchScheduler()
        defer { manager.close() }
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.identifier = NSUserInterfaceItemIdentifier("main")
        let status = makeWindow()
        status.identifier = nil
        status.level = .statusBar
        defer { panel.close(); status.close() }
        let windows = AppWindows(isPreview: true, hasSurface: { _ in true },
                                 schedule: { scheduler.enqueue($0) }, activate: {})
        windows.attach(manager)

        XCTAssertFalse(AppWindows.isMainWindow(panel))
        XCTAssertFalse(AppWindows.isMainWindow(status))
        windows.attach(panel)
        windows.attach(status)

        XCTAssertTrue(windows.window === manager)
        XCTAssertEqual(manager.orderOutCount, 0)
        XCTAssertEqual(status.orderOutCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testMainWindowIdentityExcludesOtherNamedWindows() {
        let window = makeWindow()
        defer { window.close() }
        XCTAssertTrue(AppWindows.isMainWindow(window))
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        XCTAssertFalse(AppWindows.isMainWindow(window))
        window.identifier = NSUserInterfaceItemIdentifier("main")
        XCTAssertTrue(AppWindows.isMainWindow(window))
        window.identifier = nil
        XCTAssertTrue(AppWindows.isMainWindow(window), "A main-capable normal window also supports attachment before SwiftUI assigns its identifier")
    }
}

@MainActor
private final class LaunchScheduler {
    private var callbacks: [@MainActor () -> Void] = []
    var pendingCount: Int { callbacks.count }

    func enqueue(_ callback: @escaping @MainActor () -> Void) {
        callbacks.append(callback)
    }

    func runNext() throws {
        let callback = try XCTUnwrap(callbacks.first)
        callbacks.removeFirst()
        callback()
    }
}

@MainActor
private final class LaunchTrackingWindow: NSWindow {
    private(set) var orderOutCount = 0
    private(set) var makeKeyAndOrderFrontCount = 0

    // A unit-test NSApplication is not running its normal window lifecycle.
    override var canBecomeMain: Bool { true }

    override func orderOut(_ sender: Any?) {
        orderOutCount += 1
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCount += 1
    }
}
