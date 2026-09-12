import Carbon
import XCTest
@testable import OpenNoType

final class HotkeyConflictsTests: XCTestCase {
    private let optionSpace = HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    private let chatGPTID = "com.openai.chat"
    private let notypeID = "space.techjuicelab.notype"

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
        let chatGPTRunning: (String) -> Bool = { $0 == self.chatGPTID }
        let warnings = HotkeyConflicts.warnings(for: bindings, defaults: { $0 == self.chatGPTID ? chatGPT : nil },
                                                isRunning: chatGPTRunning)
        guard warnings.count == 1 else { return XCTFail("expected one warning, got \(warnings)") }
        XCTAssertTrue(warnings[0].contains("ChatGPT"))
        XCTAssertTrue(warnings[0].contains("⌥Space"))
        XCTAssertFalse(warnings[0].contains("⌥⇧Space"))

        XCTAssertTrue(HotkeyConflicts.warnings(for: bindings, defaults: { _ in chatGPT }, isRunning: { _ in false }).isEmpty,
                      "Preferences of an app that is not running must not warn")
        XCTAssertTrue(HotkeyConflicts.warnings(for: bindings, defaults: { _ in nil }, isRunning: chatGPTRunning).isEmpty,
                      "ChatGPT without stored shortcuts holds none")
        let moved = HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | cmdKey))
        XCTAssertTrue(HotkeyConflicts.warnings(for: [moved, bindings[1], bindings[2]], defaults: { _ in chatGPT },
                                               isRunning: chatGPTRunning).isEmpty)
    }

    func testRunningNotypeWarnsWithItsDefaultShortcutsWhenNothingIsStored() {
        let notypeRunning: (String) -> Bool = { $0 == self.notypeID }
        let warnings = HotkeyConflicts.warnings(for: HotkeyBinding.defaults, defaults: { _ in [:] }, isRunning: notypeRunning)
        // notype defaults to ⌥Space and ⌥⇧Space (plus ⌥⇧T); OpenNoType's third default ⌥⌃Space is free.
        guard warnings.count == 2 else { return XCTFail("expected two warnings, got \(warnings)") }
        XCTAssertTrue(warnings[0].contains("notype") && warnings[0].contains("⌥Space 단축키"))
        XCTAssertTrue(warnings[1].contains("⌥⇧Space"))
        XCTAssertTrue(warnings.allSatisfy { $0.contains("이전 버전") && $0.contains("메뉴 막대") && $0.contains("로그인 항목") })
        XCTAssertTrue(warnings.allSatisfy { $0.hasSuffix("주세요.") && !$0.contains(". 또는") }, "the alternative belongs to each app's own hint")
        XCTAssertTrue(warnings.allSatisfy { !$0.contains("창이 앞으로") }, "notype records instead of activating a window")

        XCTAssertTrue(HotkeyConflicts.warnings(for: HotkeyBinding.defaults, defaults: { _ in [:] }, isRunning: { _ in false }).isEmpty)
        XCTAssertEqual(HotkeyConflicts.warnings(for: HotkeyBinding.defaults, defaults: { _ in nil }, isRunning: notypeRunning).count, 2,
                       "An unreadable domain is treated like notype running on its defaults")
    }

    func testStoredNotypeBindingsReplaceItsDefaults() {
        // 받아쓰기 moved to ⌥⌘Space, 고쳐쓰기 still ⌥⇧Space: only the second OpenNoType default overlaps.
        let flat = #"["dictate",[{"keyCode":49,"modifiers":2304}],"translate",[{"keyCode":17,"modifiers":2560}],"rewrite",[{"keyCode":49,"modifiers":2560}]]"#
        let stored: [String: Any] = ["shortcutBindings.v1": Data(flat.utf8)]
        let warnings = HotkeyConflicts.warnings(for: HotkeyBinding.defaults, defaults: { _ in stored }, isRunning: { $0 == self.notypeID })
        guard warnings.count == 1 else { return XCTFail("expected one warning, got \(warnings)") }
        XCTAssertTrue(warnings[0].contains("⌥⇧Space"))

        let parsed = HotkeyConflicts.notypeBindings(fromStoredBindings: Data(flat.utf8))
        XCTAssertEqual(parsed, [HotkeyBinding(keyCode: 49, modifiers: 2304), HotkeyBinding(keyCode: 17, modifiers: 2560),
                                HotkeyBinding(keyCode: 49, modifiers: 2560)])
        // Two bindings for one mode are all registered; a repeated mode name keeps the later entry.
        let twoForDictate = #"["dictate",[{"keyCode":49,"modifiers":2304},{"keyCode":0,"modifiers":4096}],"translate",[{"keyCode":17,"modifiers":2560}],"rewrite",[{"keyCode":49,"modifiers":2560}]]"#
        XCTAssertEqual(HotkeyConflicts.notypeBindings(fromStoredBindings: Data(twoForDictate.utf8)).count, 4)
        let repeated = #"["dictate",[{"keyCode":49,"modifiers":2048}],"dictate",[{"keyCode":49,"modifiers":2304}],"translate",[{"keyCode":17,"modifiers":2560}],"rewrite",[{"keyCode":49,"modifiers":2560}]]"#
        XCTAssertFalse(HotkeyConflicts.notypeBindings(fromStoredBindings: Data(repeated.utf8)).contains(optionSpace))
    }

    func testNotypeFallsBackToItsDefaultsForAnythingItCouldNotDecodeOrValidate() {
        let defaults = HotkeyConflicts.notypeDefaultBindings
        XCTAssertTrue(defaults.contains(optionSpace))
        XCTAssertEqual(HotkeyConflicts.notypeBindings(fromStoredBindings: nil), defaults)
        XCTAssertEqual(HotkeyConflicts.notypeBindings(fromStoredBindings: Data("not json".utf8)), defaults)
        XCTAssertEqual(HotkeyConflicts.notypeBindings(fromStoredBindings: Data("[]".utf8)), defaults)
        // notype reads the value with data(forKey:) and JSONDecoder: strings and keyed objects never decode there.
        let flat = #"["dictate",[{"keyCode":49,"modifiers":2304}],"translate",[{"keyCode":17,"modifiers":2560}],"rewrite",[{"keyCode":49,"modifiers":2560}]]"#
        XCTAssertEqual(HotkeyConflicts.notypeBindings(fromStoredBindings: flat), defaults, "a String value is not Data")
        let keyed = #"{"dictate":[{"keyCode":49,"modifiers":2304}],"translate":[{"keyCode":17,"modifiers":2560}],"rewrite":[{"keyCode":49,"modifiers":2560}]}"#
        XCTAssertEqual(HotkeyConflicts.notypeBindings(fromStoredBindings: Data(keyed.utf8)), defaults)
        // Partially valid sets are rejected as a whole, never merged with the good entries.
        let invalid = [
            #"["dictate",[{"keyCode":49,"modifiers":2304}]]"#,                                                                  // 번역·고쳐쓰기 missing
            #"["dictate",[{"keyCode":"49","modifiers":2304}],"translate",[{"keyCode":17,"modifiers":2560}],"rewrite",[{"keyCode":49,"modifiers":2560}]]"#, // string keyCode
            #"["dictate",[{"keyCode":49}],"translate",[{"keyCode":17,"modifiers":2560}],"rewrite",[{"keyCode":49,"modifiers":2560}]]"#,               // missing field
            #"["dictate",[{"keyCode":-1,"modifiers":2304}],"translate",[{"keyCode":17,"modifiers":2560}],"rewrite",[{"keyCode":49,"modifiers":2560}]]"#, // negative
            #"["dictate",[{"keyCode":true,"modifiers":2304}],"translate",[{"keyCode":17,"modifiers":2560}],"rewrite",[{"keyCode":49,"modifiers":2560}]]"#, // bool
            #"["dictate",[{"keyCode":49,"modifiers":2304}],"translate",[],"rewrite",[{"keyCode":49,"modifiers":2560}]]"#,                    // empty mode
            #"["dictate",[{"keyCode":49,"modifiers":2560}],"translate",[{"keyCode":17,"modifiers":2560}],"rewrite",[{"keyCode":49,"modifiers":2560}]]"#, // duplicate across modes
            #"["dictate",[{"keyCode":49,"modifiers":0}],"translate",[{"keyCode":17,"modifiers":2560}],"rewrite",[{"keyCode":49,"modifiers":2560}]]"#,    // no modifier
            #"["dictate",[{"keyCode":49,"modifiers":2304}],"other",[{"keyCode":17,"modifiers":2560}],"rewrite",[{"keyCode":49,"modifiers":2560}]]"#,  // unknown mode
            #"["dictate",[{"keyCode":49,"modifiers":2304}],"translate",[{"keyCode":17,"modifiers":2560}],"rewrite"]"#                                 // odd count
        ]
        for json in invalid {
            XCTAssertEqual(HotkeyConflicts.notypeBindings(fromStoredBindings: Data(json.utf8)), defaults, json)
        }
    }

    func testParserAcceptsWhatSwiftsJSONEncoderWritesForNotype() throws {
        // notype encodes [ShortcutMode: [ShortcutBinding]] with JSONEncoder; the dictionary order is random.
        let data = try JSONEncoder().encode([NotypeMode.dictate: [NotypeBinding(keyCode: 49, modifiers: 2304)],
                                             .translate: [NotypeBinding(keyCode: 17, modifiers: 2560)],
                                             .rewrite: [NotypeBinding(keyCode: 49, modifiers: 2560)]])
        XCTAssertEqual(HotkeyConflicts.notypeBindings(fromStoredBindings: data),
                       [HotkeyBinding(keyCode: 49, modifiers: 2304), HotkeyBinding(keyCode: 17, modifiers: 2560),
                        HotkeyBinding(keyCode: 49, modifiers: 2560)])
        let stored: [String: Any] = ["shortcutBindings.v1": data]
        let warnings = HotkeyConflicts.warnings(for: HotkeyBinding.defaults, defaults: { _ in stored }, isRunning: { $0 == self.notypeID })
        XCTAssertEqual(warnings.count, 1)
    }
}

/// Shapes copied from notype's ShortcutSettings.swift so the fixture is produced by the same encoder path.
private enum NotypeMode: String, Codable { case dictate, translate, rewrite }
private struct NotypeBinding: Codable { var keyCode: UInt32; var modifiers: UInt32 }
