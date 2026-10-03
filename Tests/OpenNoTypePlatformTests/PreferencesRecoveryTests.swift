import XCTest
@testable import OpenNoType

final class PreferencesRecoveryTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let name = "OpenNoTypePreferencesRecoveryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testFreshInstallationAndValidLegacyRecordAreDistinct() throws {
        let defaults = isolatedDefaults()
        let fresh = Preferences.load(from: defaults)
        XCTAssertEqual(fresh.recoveryState, .fresh)
        XCTAssertEqual(fresh.interfaceLanguage.rawValue, "en")
        XCTAssertEqual(fresh.retentionDays, 30)
        defaults.set(Data(#"{"provider":"groq","retentionDays":-1}"#.utf8), forKey: "preferences.v1")
        let loaded = Preferences.load(from: defaults)
        XCTAssertEqual(loaded.recoveryState, .loaded)
        XCTAssertEqual(loaded.interfaceLanguage.rawValue, "ko")
        XCTAssertEqual(loaded.retentionDays, -1)
    }

    func testCorruptedBlobIsPreservedAcrossRelaunchAndUnrelatedSettingsChanges() {
        for raw in [Data("{broken".utf8), Data("[]".utf8), Data("null".utf8)] {
            let defaults = isolatedDefaults()
            defaults.set(raw, forKey: "preferences.v1")
            var recovered = Preferences.load(from: defaults)
            XCTAssertEqual(recovered.recoveryState, .corrupted)
            XCTAssertEqual(recovered.retentionDays, -1)
            recovered.appearance = "dark"
            XCTAssertFalse(recovered.save(to: defaults))
            XCTAssertEqual(defaults.data(forKey: "preferences.v1"), raw)
            XCTAssertEqual(defaults.data(forKey: Preferences.recoveryOriginalKey), raw)
            XCTAssertEqual(Preferences.load(from: defaults).recoveryState, .corrupted)
        }
    }

    func testWrongStorageTypeIsNotTreatedAsANewInstallation() {
        let defaults = isolatedDefaults()
        defaults.set("invalid stored type", forKey: "preferences.v1")
        let recovered = Preferences.load(from: defaults)
        XCTAssertTrue(recovered.recoveryState.requiresRecovery)
        XCTAssertFalse(recovered.save(to: defaults))
        XCTAssertEqual(defaults.string(forKey: "preferences.v1"), "invalid stored type")
        XCTAssertEqual(defaults.string(forKey: Preferences.recoveryOriginalKey), "invalid stored type")
    }

    func testPartialRecoveryKeepsOtherFieldsAndRequiresAnExplicitDecision() throws {
        let defaults = isolatedDefaults()
        let raw = Data(#"{"provider":"groq","textProvider":"openRouter","textModels":{"openRouter":"openai/gpt-6-luna"},"retentionDays":-1,"decisionProvider":"typesafe","decisionReviewMode":"repair","hotkeys":"broken"}"#.utf8)
        defaults.set(raw, forKey: "preferences.v1")
        var recovered = Preferences.load(from: defaults)
        XCTAssertEqual(recovered.recoveryState, .partiallyRecovered(["hotkeys"]))
        XCTAssertEqual(recovered.provider.rawValue, "groq")
        XCTAssertEqual(recovered.effectiveTextProvider.rawValue, "openRouter")
        XCTAssertEqual(recovered.textModel, "openai/gpt-6-luna")
        XCTAssertEqual(recovered.retentionDays, -1)
        XCTAssertEqual(recovered.decisionReviewMode, .repair)
        recovered.appearance = "dark"
        XCTAssertFalse(recovered.save(to: defaults))
        XCTAssertEqual(defaults.data(forKey: "preferences.v1"), raw)
        let accepted = try XCTUnwrap(recovered.acceptRecovery(to: defaults))
        XCTAssertEqual(accepted.recoveryState, .loaded)
        XCTAssertEqual(Preferences.load(from: defaults).appearance, "dark")
        XCTAssertEqual(defaults.data(forKey: Preferences.recoveryOriginalKey), raw)
    }

    func testInvalidRetentionCannotBecomeAnAutomaticDeletionPolicy() throws {
        for invalid in [#""broken""#, "-2", "null"] {
            let defaults = isolatedDefaults()
            defaults.set(Data("{\"provider\":\"groq\",\"retentionDays\":\(invalid)}".utf8), forKey: "preferences.v1")
            let recovered = Preferences.load(from: defaults)
            XCTAssertEqual(recovered.retentionDays, -1)
            XCTAssertEqual(recovered.recoveryState, .partiallyRecovered(["retentionDays"]))
            let accepted = try XCTUnwrap(recovered.acceptRecovery(to: defaults))
            XCTAssertEqual(accepted.retentionDays, -1)
            XCTAssertEqual(Preferences.load(from: defaults).retentionDays, -1)
        }
    }

    func testLastKnownGoodRestorePreservesOriginalCorruptionBackup() throws {
        let defaults = isolatedDefaults()
        var intended = Preferences()
        intended.provider = .groq; intended.textProvider = .openRouter
        intended.textModels = ["openRouter": "openai/gpt-6-luna"]
        intended.retentionDays = -1; intended.decisionReviewMode = .repair; intended.decisionProvider = .typeSafe
        XCTAssertTrue(intended.save(to: defaults))
        let corrupt = Data("{invalid".utf8)
        defaults.set(corrupt, forKey: "preferences.v1")
        _ = Preferences.load(from: defaults)
        XCTAssertTrue(Preferences.canRestoreLastKnownGood(from: defaults))
        let restored = try XCTUnwrap(Preferences.restoreLastKnownGood(from: defaults))
        XCTAssertEqual(restored.textModel, "openai/gpt-6-luna")
        XCTAssertEqual(restored.retentionDays, -1)
        XCTAssertEqual(restored.decisionReviewMode, .repair)
        XCTAssertFalse(Preferences.load(from: defaults).recoveryState.requiresRecovery)
        XCTAssertEqual(defaults.data(forKey: Preferences.recoveryOriginalKey), corrupt)
    }

    func testMissingPrimaryWithAnExistingBackupNeedsRecovery() {
        let defaults = isolatedDefaults()
        XCTAssertTrue(Preferences().save(to: defaults))
        defaults.removeObject(forKey: "preferences.v1")
        XCTAssertEqual(Preferences.load(from: defaults).recoveryState, .corrupted)
        XCTAssertTrue(Preferences.canRestoreLastKnownGood(from: defaults))
    }

    func testCorruptedLastKnownGoodBackupCannotBeRestored() {
        let defaults = isolatedDefaults()
        defaults.set(Data("{}".utf8), forKey: Preferences.lastKnownGoodKey)
        // A legacy object is valid, but partially decoded settings are not a trusted backup.
        defaults.set(Data(#"{"provider":"unknown"}"#.utf8), forKey: Preferences.lastKnownGoodKey)
        XCTAssertFalse(Preferences.canRestoreLastKnownGood(from: defaults))
        XCTAssertNil(Preferences.restoreLastKnownGood(from: defaults))
    }

    func testNormalInMemorySettingsCannotOverwriteNewlyCorruptedStoredSource() {
        let defaults = isolatedDefaults()
        var inMemory = Preferences()
        XCTAssertTrue(inMemory.save(to: defaults))
        let raw = Data("{external corruption".utf8)
        defaults.set(raw, forKey: "preferences.v1")
        inMemory.appearance = "dark"
        XCTAssertFalse(inMemory.save(to: defaults))
        XCTAssertEqual(defaults.data(forKey: "preferences.v1"), raw)
        XCTAssertEqual(defaults.data(forKey: Preferences.recoveryOriginalKey), raw)
    }

    func testStaleRecoveryChoiceDoesNotReplaceAnUpdatedSource() {
        let defaults = isolatedDefaults()
        defaults.set(Data("{first corrupted source".utf8), forKey: "preferences.v1")
        let recovered = Preferences.load(from: defaults)
        let newer = Data("{newer corrupted source".utf8)
        defaults.set(newer, forKey: "preferences.v1")
        XCTAssertNil(recovered.acceptRecovery(to: defaults))
        XCTAssertEqual(defaults.data(forKey: "preferences.v1"), newer)
    }

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
