import Carbon
import XCTest
@testable import OpenNoType

final class HotkeyConflictsTests: XCTestCase {
    private let optionSpace = HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    func testStoredKeyboardShortcutsJSONIsParsedFromStringOrData() {
        let json = #"{"carbonKeyCode":49,"carbonModifiers":2048}"#
        XCTAssertEqual(HotkeyConflicts.binding(fromStoredShortcut: json), optionSpace)
        XCTAssertEqual(HotkeyConflicts.binding(fromStoredShortcut: Data(json.utf8)), optionSpace)
        XCTAssertNil(HotkeyConflicts.binding(fromStoredShortcut: nil))
        XCTAssertNil(HotkeyConflicts.binding(fromStoredShortcut: "null"))
        XCTAssertNil(HotkeyConflicts.binding(fromStoredShortcut: #"{"carbonKeyCode":"49"}"#))
        XCTAssertNil(HotkeyConflicts.binding(fromStoredShortcut: 42))
    }

    func testWarningNamesTheOtherAppAndOnlyForMatchingInstalledApps() {
        let chatGPT: [String: Any] = [
            "KeyboardShortcuts_toggleLauncher": #"{"carbonKeyCode":49,"carbonModifiers":2048}"#,
            "KeyboardShortcuts_toggleAttachedLauncher": #"{"carbonKeyCode":18,"carbonModifiers":2560}"#
        ]
        let bindings = HotkeyBinding.defaults
        let warnings = HotkeyConflicts.warnings(for: bindings, defaults: { $0 == "com.openai.chat" ? chatGPT : nil },
                                                isRunning: { _ in true })
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("ChatGPT"))
        XCTAssertTrue(warnings[0].contains("⌥Space"))
        XCTAssertFalse(warnings[0].contains("⌥⇧Space"))

        XCTAssertTrue(HotkeyConflicts.warnings(for: bindings, defaults: { _ in chatGPT }, isRunning: { _ in false }).isEmpty,
                      "Preferences of an app that is not running must not warn")
        XCTAssertTrue(HotkeyConflicts.warnings(for: bindings, defaults: { _ in nil }, isRunning: { _ in true }).isEmpty)
        let moved = HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | cmdKey))
        XCTAssertTrue(HotkeyConflicts.warnings(for: [moved, bindings[1], bindings[2]], defaults: { _ in chatGPT },
                                               isRunning: { _ in true }).isEmpty)
    }
}
