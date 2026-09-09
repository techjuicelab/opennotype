import XCTest
@testable import OpenNoType

final class PreferencesRecoveryTests: XCTestCase {
    func testInvalidHotkeyFieldRestoresDefaultsWithoutResettingOtherPreferences() throws {
        let invalidValues = [
            "[]",
            #"[{"keyCode":49,"modifiers":2048}]"#,
            #"[{"keyCode":49,"modifiers":2048},{"keyCode":49,"modifiers":2048},{"keyCode":49,"modifiers":6144}]"#,
            #"[{"keyCode":0,"modifiers":0},{"keyCode":1,"modifiers":2048},{"keyCode":2,"modifiers":6144}]"#,
            #"[{"keyCode":999,"modifiers":2048},{"keyCode":1,"modifiers":2048},{"keyCode":2,"modifiers":6144}]"#,
            #"[{"keyCode":0,"modifiers":65536},{"keyCode":1,"modifiers":2048},{"keyCode":2,"modifiers":6144}]"#,
            #""unreadable""#
        ]
        for invalid in invalidValues {
            let json = "{\"provider\":\"groq\",\"retentionDays\":7,\"historyEnabled\":false,\"hotkeys\":\(invalid)}"
            let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
            XCTAssertEqual(preferences.hotkeys, HotkeyBinding.defaults, invalid)
            XCTAssertEqual(preferences.provider.rawValue, "groq", invalid)
            XCTAssertEqual(preferences.retentionDays, 7, invalid)
            XCTAssertFalse(preferences.historyEnabled, invalid)
        }
    }

    func testValidCustomHotkeysSurviveDecoding() throws {
        var preferences = Preferences()
        preferences.hotkeys = [.init(keyCode: 0, modifiers: 2048), .init(keyCode: 1, modifiers: 2560), .init(keyCode: 2, modifiers: 6144)]
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded.hotkeys, preferences.hotkeys)
    }

    func testAutomaticLearningIsSeparateFromHistoryAndSurvivesRelaunch() throws {
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data(#"{"historyEnabled":false}"#.utf8))
        XCTAssertTrue(legacy.automaticLearningEnabled)
        XCTAssertFalse(legacy.historyEnabled)
        var preferences = legacy
        preferences.automaticLearningEnabled = false
        preferences.historyEnabled = true
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertFalse(decoded.automaticLearningEnabled)
        XCTAssertTrue(decoded.historyEnabled)
    }
}
