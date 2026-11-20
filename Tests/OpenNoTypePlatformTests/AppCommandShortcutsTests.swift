import AppKit
import XCTest
import OpenNoTypeCore
@testable import OpenNoType

@MainActor
final class AppCommandShortcutsTests: XCTestCase {
    private func makeModel() -> AppModel {
        var runtime = AppRuntime()
        runtime.readKey = { _ in nil }
        runtime.readDecisionKey = { _ in nil }
        runtime.accessibilityPermitted = { false }
        runtime.microphonePermission = { .notDetermined }
        runtime.hotkeyConflictWarnings = { _ in [] }
        return AppModel(runtime: runtime, startServices: false, preferences: Preferences())
    }

    func testFindCommandFocusesSearchOnNonEditorAndPreservesDictionaryPage() {
        let model = makeModel()
        var opens = 0
        model.showManager = { opens += 1 }
        model.page = .home

        let navigated = AppNavigationCommands.handleFind(model: model, keyWindow: nil)
        XCTAssertTrue(navigated)
        XCTAssertEqual(model.page, .history)
        XCTAssertTrue(model.pendingSearchFocus)
        XCTAssertEqual(opens, 1)

        model.pendingSearchFocus = false
        model.page = .dictionary
        model.dictionarySection = .learning
        let stayedOnDictionary = AppNavigationCommands.handleFind(model: model, keyWindow: nil)
        XCTAssertTrue(stayedOnDictionary)
        XCTAssertEqual(model.page, .dictionary)
        XCTAssertEqual(model.dictionarySection, .words)
        XCTAssertTrue(model.pendingSearchFocus)
        XCTAssertEqual(opens, 2)
    }

    func testFindCommandDelegatesToFocusedTextEditorInsteadOfSwitchingPage() {
        _ = NSApplication.shared
        let model = makeModel()
        model.page = .recovery
        var opens = 0
        model.showManager = { opens += 1 }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let textView = FindTrackingTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.usesFindBar = true
        textView.isFieldEditor = false
        scroll.documentView = textView
        window.contentView?.addSubview(scroll)
        XCTAssertTrue(window.makeFirstResponder(textView))

        let navigated = AppNavigationCommands.handleFind(model: model, keyWindow: window)
        XCTAssertFalse(navigated)
        XCTAssertEqual(textView.findActionTags, [Int(NSFindPanelAction.showFindPanel.rawValue)])
        XCTAssertEqual(model.page, .recovery, "Cmd+F inside a TextEditor must not yank the user away to History")
        XCTAssertFalse(model.pendingSearchFocus)
        XCTAssertEqual(opens, 0)
    }

    func testFindCommandStillNavigatesWhenFocusedOnSingleLineFieldEditor() {
        _ = NSApplication.shared
        let model = makeModel()
        model.page = .home

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let fieldEditor = FindTrackingTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        fieldEditor.usesFindBar = true
        fieldEditor.isFieldEditor = true
        window.contentView?.addSubview(fieldEditor)
        XCTAssertTrue(window.makeFirstResponder(fieldEditor))

        let navigated = AppNavigationCommands.handleFind(model: model, keyWindow: window)
        XCTAssertTrue(navigated)
        XCTAssertTrue(fieldEditor.findActionTags.isEmpty)
        XCTAssertEqual(model.page, .history)
        XCTAssertTrue(model.pendingSearchFocus)
    }
}

private final class FindTrackingTextView: NSTextView {
    private(set) var findActionTags: [Int] = []

    override func performFindPanelAction(_ sender: Any?) {
        if let item = sender as? NSMenuItem {
            findActionTags.append(item.tag)
        }
    }
}
