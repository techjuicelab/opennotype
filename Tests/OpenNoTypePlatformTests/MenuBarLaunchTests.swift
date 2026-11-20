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

    func testFreshInstallOptInAllowsInitialManagerWindowOnceOnly() throws {
        let suiteName = "MenuBarLaunchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstWindow = makeWindow(), scheduler = LaunchScheduler()
        defer { firstWindow.close() }
        let firstLaunch = AppWindows(isPreview: false, hasSurface: { _ in true },
                                     schedule: { scheduler.enqueue($0) }, activate: {})
        XCTAssertTrue(firstLaunch.allowInitialWindowForFreshInstall(isFreshInstall: true, defaults: defaults))
        firstLaunch.attach(firstWindow)
        XCTAssertEqual(firstWindow.alphaValue, 1)
        XCTAssertEqual(firstWindow.orderOutCount, 0)

        let secondWindow = makeWindow()
        defer { secondWindow.close() }
        let secondLaunch = AppWindows(isPreview: false, hasSurface: { _ in true },
                                      schedule: { scheduler.enqueue($0) }, activate: {})
        XCTAssertFalse(secondLaunch.allowInitialWindowForFreshInstall(isFreshInstall: true, defaults: defaults))
        secondLaunch.attach(secondWindow)
        XCTAssertEqual(secondWindow.orderOutCount, 1)
    }

    func testLoginLaunchWithoutSwiftUISceneCreatesAndReusesFallbackManagerWindow() {
        let fallback = makeWindow(), scheduler = LaunchScheduler()
        defer { fallback.close() }
        var factoryCalls = 0, activationCount = 0
        let windows = AppWindows(isPreview: false, hasSurface: { _ in false },
                                 schedule: { scheduler.enqueue($0) }, activate: { activationCount += 1 })
        windows.connectFallbackWindowFactory {
            factoryCalls += 1
            return fallback
        }

        // Neither attach() nor connectWindowOpening() ran (matching macOS login-item launch).
        windows.show()

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertTrue(windows.window === fallback)
        XCTAssertFalse(fallback.isRestorable)
        XCTAssertFalse(fallback.isReleasedWhenClosed)
        XCTAssertEqual(fallback.alphaValue, 1)
        XCTAssertEqual(fallback.orderOutCount, 0)
        XCTAssertEqual(fallback.makeKeyAndOrderFrontCount, 1)
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 0)

        // Hosting view mounting triggers attach(fallback): must not re-suppress or hide it.
        windows.attach(fallback)
        XCTAssertEqual(fallback.orderOutCount, 0)
        XCTAssertEqual(fallback.alphaValue, 1)

        // Reopening after closing reuses the retained fallback window without creating a second one.
        fallback.orderOut(nil)
        windows.show()
        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(fallback.makeKeyAndOrderFrontCount, 2)
        XCTAssertEqual(activationCount, 2)
    }

    func testDuplicateSwiftUIWindowIsClosedWhenFallbackWindowAlreadyExists() throws {
        let fallback = makeWindow(), lateSwiftUI = makeWindow(), scheduler = LaunchScheduler()
        defer { fallback.close(); lateSwiftUI.close() }
        var lateOpenCount = 0
        let windows = AppWindows(isPreview: false, hasSurface: { _ in true },
                                 schedule: { scheduler.enqueue($0) }, activate: {})
        windows.connectFallbackWindowFactory { fallback }

        windows.show()
        windows.attach(lateSwiftUI)
        // Late SwiftUI ManagerWindowContent.onAppear must not re-arm openWindow after fallback owns the manager.
        windows.connectWindowOpening { lateOpenCount += 1 }

        XCTAssertTrue(windows.window === fallback)
        XCTAssertFalse(lateSwiftUI.isRestorable)
        XCTAssertEqual(lateSwiftUI.alphaValue, 0)
        XCTAssertEqual(lateSwiftUI.orderOutCount, 1)
        XCTAssertEqual(lateSwiftUI.closeCount, 0, "Deferred close avoids racing SwiftUI's initial window order-in")
        XCTAssertEqual(scheduler.pendingCount, 1)

        try scheduler.runNext()
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(lateSwiftUI.closeCount, 1)
        XCTAssertEqual(fallback.orderOutCount, 0)

        windows.show()
        XCTAssertEqual(lateOpenCount, 0, "Reopening the fallback manager must not trigger SwiftUI openWindow")
        XCTAssertEqual(fallback.makeKeyAndOrderFrontCount, 2)
    }

    func testAsyncOpenWindowFailureFallsBackToAppKitManagerWindow() throws {
        let fallback = makeWindow(), scheduler = LaunchScheduler()
        defer { fallback.close() }
        var openCount = 0, factoryCalls = 0
        let windows = AppWindows(isPreview: false, hasSurface: { _ in true },
                                 schedule: { scheduler.enqueue($0) }, activate: {})
        windows.connectWindowOpening { openCount += 1 }
        windows.connectFallbackWindowFactory {
            factoryCalls += 1
            return fallback
        }

        windows.show()
        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(factoryCalls, 0)

        for _ in 0..<60 where scheduler.pendingCount > 0 { try scheduler.runNext() }

        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(factoryCalls, 1)
        XCTAssertTrue(windows.window === fallback)
        XCTAssertEqual(fallback.makeKeyAndOrderFrontCount, 1)

        // Subsequent opens must reuse the fallback window directly without invoking SwiftUI openWindow again.
        windows.show()
        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(fallback.makeKeyAndOrderFrontCount, 2)
    }

    func testAsyncOpenWindowSuccessCancelsFallbackCreation() throws {
        let swiftUIWindow = makeWindow(), fallback = makeWindow(), scheduler = LaunchScheduler()
        defer { swiftUIWindow.close(); fallback.close() }
        var factoryCalls = 0
        let windows = AppWindows(isPreview: false, hasSurface: { _ in true },
                                 schedule: { scheduler.enqueue($0) }, activate: {})
        windows.connectWindowOpening {}
        windows.connectFallbackWindowFactory {
            factoryCalls += 1
            return fallback
        }

        windows.show()
        XCTAssertEqual(scheduler.pendingCount, 1)

        // SwiftUI attaches its window on a later runloop turn before fallback retries expire.
        windows.attach(swiftUIWindow)
        try scheduler.runNext()

        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(factoryCalls, 0)
        XCTAssertTrue(windows.window === swiftUIWindow)
        XCTAssertEqual(swiftUIWindow.makeKeyAndOrderFrontCount, 1)
        XCTAssertEqual(swiftUIWindow.orderOutCount, 0)
    }

    func testShowRecoversExistingUnattachedMainWindowAndDeminiaturizes() {
        let existing = makeWindow(), fallback = makeWindow(), scheduler = LaunchScheduler()
        defer { existing.close(); fallback.close() }
        existing.simulatedMiniaturized = true
        var factoryCalls = 0
        let windows = AppWindows(isPreview: false, hasSurface: { _ in true },
                                 schedule: { scheduler.enqueue($0) }, activate: {},
                                 existingWindows: { [existing] })
        windows.connectFallbackWindowFactory {
            factoryCalls += 1
            return fallback
        }

        windows.show()

        XCTAssertEqual(factoryCalls, 0)
        XCTAssertTrue(windows.window === existing)
        XCTAssertEqual(existing.deminiaturizeCount, 1)
        XCTAssertTrue(existing.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertEqual(existing.makeKeyAndOrderFrontCount, 1)
        XCTAssertEqual(existing.orderOutCount, 0)
    }

    func testShowIgnoresUnrelatedUntaggedWindowAndCreatesFallbackManager() {
        let unrelated = makeWindow(), fallback = makeWindow(), scheduler = LaunchScheduler()
        unrelated.identifier = nil
        defer { unrelated.close(); fallback.close() }
        var factoryCalls = 0
        let windows = AppWindows(isPreview: false, hasSurface: { _ in true },
                                 schedule: { scheduler.enqueue($0) }, activate: {},
                                 existingWindows: { [unrelated] })
        windows.connectFallbackWindowFactory {
            factoryCalls += 1
            return fallback
        }

        XCTAssertFalse(AppWindows.isExistingMainWindow(unrelated))
        windows.show()

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertTrue(windows.window === fallback)
        XCTAssertEqual(unrelated.makeKeyAndOrderFrontCount, 0)
        XCTAssertEqual(fallback.makeKeyAndOrderFrontCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 0)

        // An untagged window that actually hosts ManagerWindowAccessor still matches.
        let untaggedManager = makeWindow()
        untaggedManager.identifier = nil
        defer { untaggedManager.close() }
        let accessor = ManagerWindowAccessor.WindowAccessorView(windows: AppWindows(isPreview: true), appearanceName: "system")
        untaggedManager.contentView?.addSubview(accessor)
        XCTAssertTrue(AppWindows.isExistingMainWindow(untaggedManager))
    }

    func testNilFallbackFactoryResultActivatesWithoutCachingEmptyWindow() {
        let fallback = makeWindow(), scheduler = LaunchScheduler()
        defer { fallback.close() }
        var shouldProvideWindow = false
        var activationCount = 0
        let windows = AppWindows(isPreview: false, hasSurface: { _ in true },
                                 schedule: { scheduler.enqueue($0) }, activate: { activationCount += 1 },
                                 existingWindows: { [] })
        windows.connectFallbackWindowFactory {
            shouldProvideWindow ? fallback : nil
        }

        windows.show()
        XCTAssertNil(windows.window)
        XCTAssertEqual(activationCount, 1)

        shouldProvideWindow = true
        windows.show()
        XCTAssertTrue(windows.window === fallback)
        XCTAssertEqual(fallback.makeKeyAndOrderFrontCount, 1)
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testDuplicateKeySwiftUIWindowReopensClosedFallbackManager() throws {
        let fallback = makeWindow(), lateSwiftUI = makeWindow(), scheduler = LaunchScheduler()
        defer { fallback.close(); lateSwiftUI.close() }
        var activationCount = 0
        let windows = AppWindows(isPreview: false, hasSurface: { _ in true },
                                 schedule: { scheduler.enqueue($0) }, activate: { activationCount += 1 },
                                 existingWindows: { [] })
        windows.connectFallbackWindowFactory { fallback }

        windows.show()
        XCTAssertEqual(fallback.makeKeyAndOrderFrontCount, 1)
        XCTAssertEqual(activationCount, 1)

        // Simulate user closing the fallback window, then a SwiftUI window opening as key.
        fallback.simulatedVisible = false
        lateSwiftUI.simulatedKeyWindow = true
        windows.attach(lateSwiftUI)
        XCTAssertEqual(scheduler.pendingCount, 1)

        try scheduler.runNext()
        XCTAssertEqual(lateSwiftUI.closeCount, 1)
        XCTAssertEqual(fallback.makeKeyAndOrderFrontCount, 2, "A key duplicate SwiftUI window must bring back a closed fallback window")
        XCTAssertEqual(activationCount, 2)

        // A background (non-key) late SwiftUI window must NOT reopen a closed fallback window.
        let backgroundSwiftUI = makeWindow()
        defer { backgroundSwiftUI.close() }
        fallback.simulatedVisible = false
        backgroundSwiftUI.simulatedKeyWindow = false
        windows.attach(backgroundSwiftUI)
        try scheduler.runNext()
        XCTAssertEqual(backgroundSwiftUI.closeCount, 1)
        XCTAssertEqual(fallback.makeKeyAndOrderFrontCount, 2)
        XCTAssertEqual(activationCount, 2)
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
    private(set) var closeCount = 0
    private(set) var deminiaturizeCount = 0
    var simulatedMiniaturized = false
    var simulatedKeyWindow = false
    var simulatedVisible = false

    // A unit-test NSApplication is not running its normal window lifecycle.
    override var canBecomeMain: Bool { true }
    override var isMiniaturized: Bool { simulatedMiniaturized }
    override var isKeyWindow: Bool { simulatedKeyWindow }
    override var isVisible: Bool { simulatedVisible }

    override func orderOut(_ sender: Any?) {
        orderOutCount += 1
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCount += 1
    }

    override func close() {
        closeCount += 1
        super.close()
    }

    override func deminiaturize(_ sender: Any?) {
        deminiaturizeCount += 1
        simulatedMiniaturized = false
    }
}
