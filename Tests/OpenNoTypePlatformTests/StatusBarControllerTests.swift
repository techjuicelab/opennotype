import AppKit
import XCTest
import OpenNoTypeCore
@testable import OpenNoType

@MainActor
final class StatusBarControllerTests: XCTestCase {
    private func makeModel() -> AppModel {
        _ = NSApplication.shared
        var runtime = AppRuntime()
        runtime.readKey = { _ in nil }
        runtime.readDecisionKey = { _ in nil }
        runtime.accessibilityPermitted = { false }
        runtime.microphonePermission = { .notDetermined }
        runtime.hotkeyConflictWarnings = { _ in [] }
        return AppModel(runtime: runtime, startServices: false, preferences: Preferences())
    }

    func testDelegateRetainsExactlyOneVisibleNonremovableItemUntilTermination() throws {
        let model = makeModel()
        let delegate = UpdateApplicationDelegate()
        delegate.configureStatusBar(model: model)
        defer { delegate.statusBarController?.stop() }
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let controller = try XCTUnwrap(delegate.statusBarController)
        let item = try XCTUnwrap(controller.statusItem)
        XCTAssertTrue(item.isVisible)
        XCTAssertFalse(item.behavior.contains(.removalAllowed))
        XCTAssertFalse(item.behavior.contains(.terminationOnRemoval))
        XCTAssertNil(item.autosaveName, "A prior removable SwiftUI item's visibility must not be restored")
        XCTAssertNotNil(item.button?.image)

        delegate.configureStatusBar(model: makeModel())
        item.isVisible = false
        delegate.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        XCTAssertTrue(delegate.statusBarController === controller)
        XCTAssertTrue(controller.statusItem === item)
        XCTAssertTrue(item.isVisible)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertNil(controller.statusItem)
    }

    func testClosedManagerDoesNotRemoveItemAndMenuUsesRetainedReopenCallback() throws {
        let model = makeModel()
        let controller = StatusBarController(model: model, isPreview: false)
        controller.start()
        defer { controller.stop() }
        let item = try XCTUnwrap(controller.statusItem)
        let menu = try XCTUnwrap(item.menu)
        var shownPages: [AppPage] = []
        model.showManager = { shownPages.append(model.page) }
        let window = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.close()
        XCTAssertTrue(controller.statusItem === item)
        XCTAssertTrue(item.isVisible)

        let manager = try XCTUnwrap(menu.items.firstIndex { $0.title == "Open OpenNoType" })
        model.page = .home
        menu.performActionForItem(at: manager)
        let settings = try XCTUnwrap(menu.items.firstIndex { $0.keyEquivalent == "," })
        menu.performActionForItem(at: settings)
        XCTAssertEqual(shownPages, [.home, .settings])
        XCTAssertTrue(controller.statusItem === item)
    }

    func testRecordingAndInterfaceLanguageRefreshTheExistingButton() async throws {
        let previousLanguage = AppLocalization.shared.language
        defer { AppLocalization.shared.language = previousLanguage }
        let model = makeModel()
        let controller = StatusBarController(model: model)
        controller.start()
        defer { controller.stop() }
        let item = try XCTUnwrap(controller.statusItem)
        XCTAssertTrue(item.button?.image === AppBrand.menuBarImage(isRecording: false))
        model.phase = .recording // Synthetic state only: no microphone or processing service starts.
        await Task.yield()
        await Task.yield()
        XCTAssertTrue(item.button?.image === AppBrand.menuBarImage(isRecording: true))
        XCTAssertEqual(item.button?.toolTip, "OpenNoType — Recording")
        model.preferences.interfaceLanguage = .korean
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(item.button?.toolTip, "OpenNoType — 녹음 중")
        model.phase = .idle
        await Task.yield()
        await Task.yield()
        XCTAssertTrue(item.button?.image === AppBrand.menuBarImage(isRecording: false))
        XCTAssertTrue(controller.statusItem === item)
    }

    func testOpeningMenuRefreshesBusyActionsAndLanguageWithoutChangingSettings() throws {
        let previousLanguage = AppLocalization.shared.language
        defer { AppLocalization.shared.language = previousLanguage }
        let model = makeModel()
        let controller = StatusBarController(model: model, isPreview: false)
        controller.start()
        defer { controller.stop() }
        let menu = try XCTUnwrap(controller.statusItem?.menu)
        XCTAssertFalse(menu.items.contains { $0.title == "Cancel current task" })
        model.phase = .processing
        controller.menuWillOpen(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "Cancel current task" })
        model.preferences.interfaceLanguage = .korean
        controller.menuWillOpen(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "현재 작업 취소" })
        XCTAssertTrue(menu.items.contains { $0.title == "설정…" })
        XCTAssertEqual(menu.items.first?.title, model.status)
        XCTAssertEqual(menu.items.filter { $0.action?.description == "toggleInput:" }.count, InputMode.allCases.count)
        XCTAssertEqual(model.phase, .processing)
    }

    func testPreviewDisablesRecordingAndSettingsButRetainsQuit() throws {
        let model = makeModel()
        var quitRequests = 0
        let controller = StatusBarController(model: model, isPreview: true, terminate: { quitRequests += 1 })
        controller.start()
        defer { controller.stop() }
        let menu = try XCTUnwrap(controller.statusItem?.menu)
        let recordingItems = menu.items.filter { $0.action?.description == "toggleInput:" }
        XCTAssertEqual(recordingItems.count, InputMode.allCases.count)
        XCTAssertTrue(recordingItems.allSatisfy { !$0.isEnabled })
        XCTAssertFalse(try XCTUnwrap(menu.items.first { $0.keyEquivalent == "," }).isEnabled)
        let quit = try XCTUnwrap(menu.items.firstIndex { $0.keyEquivalent == "q" })
        XCTAssertTrue(menu.items[quit].isEnabled)
        menu.performActionForItem(at: quit)
        XCTAssertEqual(quitRequests, 1, "The production closure still routes through NSApp.terminate and its busy guard")
        XCTAssertEqual(model.phase, .idle)
    }
}
