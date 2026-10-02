import XCTest
import OpenNoTypeCore
@testable import OpenNoType

final class PreferencesWritingProfileTests: XCTestCase {
    func testExpressionDefaultAndLegacyProfileKeepCurrentDictation() throws {
        let old = Data(#"{"provider":"groq","writingProfiles":{"test.editor":{"kind":"development","tone":"polite"}}}"#.utf8)
        let restored = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertEqual(restored.dictationExpression, .init())
        XCTAssertEqual(restored.writingProfile(for: "test.editor"), .init(kind: .development, tone: .polite))
        for value in [#""unsupported""#, #"{"style":"unknown","strength":80}"#, #"{"style":"summary","strength":"high"}"#] {
            let data = Data("{\"dictationExpression\":\(value),\"retentionDays\":7}".utf8)
            let preferences = try JSONDecoder().decode(Preferences.self, from: data)
            XCTAssertFalse(preferences.dictationExpression.isActive)
            XCTAssertEqual(preferences.retentionDays, 7)
        }
    }

    func testExpressionRoundTripDoesNotReplaceAppLayoutToneOrProvider() throws {
        var preferences = Preferences()
        preferences.provider = .groq; preferences.textProvider = .openRouter
        preferences.writingProfiles["test.editor"] = .init(kind: .email, tone: .formal)
        preferences.dictationExpression = .init(style: .summary, strength: 75)
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.writingProfile(for: "test.editor"),
                       .init(kind: .email, tone: .formal, expression: .init(style: .summary, strength: 75)))
        XCTAssertEqual(restored.writingProfile(for: nil).expression, restored.dictationExpression)
        XCTAssertEqual(restored.provider, .groq)
        XCTAssertEqual(restored.effectiveTextProvider, .openRouter)
        preferences.dictationExpression = .init()
        XCTAssertEqual(preferences.writingProfile(for: "test.editor"), .init(kind: .email, tone: .formal))
    }

    func testLegacyPreferencesKeepEveryExistingSettingWhenProfilesAreAbsent() throws {
        let legacy = Data(#"""
        {
            "provider": "openRouter",
            "transcriptionModels": { "openRouter": "custom-transcription", "openAI": "saved-openai-stt" },
            "textModels": { "openRouter": "custom-text", "anthropic": "saved-claude-text" },
            "targetLanguage": "Japanese",
            "useLocalTranscription": true,
            "allowedContextApps": ["com.example.private-editor"],
            "retentionDays": 90,
            "historyEnabled": false,
            "speakerFilterEnabled": true,
            "hotkeys": [
                { "keyCode": 0, "modifiers": 2048 },
                { "keyCode": 1, "modifiers": 2304 },
                { "keyCode": 2, "modifiers": 6144 }
            ],
            "launchAtLogin": true,
            "appearance": "dark"
        }
        """#.utf8)
        let migrated = try JSONDecoder().decode(Preferences.self, from: legacy)
        XCTAssertEqual(migrated.provider, .openRouter)
        XCTAssertEqual(migrated.transcriptionModels, ["openRouter": "custom-transcription", "openAI": "saved-openai-stt"])
        XCTAssertEqual(migrated.textModels, ["openRouter": "custom-text", "anthropic": "saved-claude-text"])
        XCTAssertEqual(migrated.targetLanguage, "Japanese")
        XCTAssertTrue(migrated.useLocalTranscription)
        XCTAssertEqual(migrated.allowedContextApps, ["com.example.private-editor"])
        XCTAssertEqual(migrated.retentionDays, 90)
        XCTAssertFalse(migrated.historyEnabled)
        XCTAssertTrue(migrated.speakerFilterEnabled)
        XCTAssertEqual(migrated.hotkeys, [.init(keyCode: 0, modifiers: 2048), .init(keyCode: 1, modifiers: 2304), .init(keyCode: 2, modifiers: 6144)])
        XCTAssertTrue(migrated.launchAtLogin)
        XCTAssertEqual(migrated.appearance, "dark")
        XCTAssertEqual(migrated.interfaceLanguage, .korean)
        XCTAssertTrue(migrated.writingProfiles.isEmpty)
        XCTAssertEqual(migrated.dictationExpression, .init())
        XCTAssertEqual(migrated.decisionReviewMode, .off)
        XCTAssertEqual(migrated.decisionProvider, .openRouter)
        XCTAssertTrue(migrated.improvementModels.isEmpty)
        XCTAssertFalse(migrated.jevDetailedReviewEnabled)
        XCTAssertFalse(migrated.jevEconomyEnabled)
        XCTAssertFalse(migrated.jevAutomaticImprovementEnabled)
        XCTAssertFalse(migrated.jevClarifyEditsEnabled)
        XCTAssertFalse(migrated.jevReRecognitionEnabled)
        XCTAssertFalse(migrated.jevFeedbackLearningEnabled)
        XCTAssertTrue(migrated.jevNameCatalog.isEmpty)

        var originalFields = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        var migratedFields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as? [String: Any])
        migratedFields.removeValue(forKey: "writingProfiles")
        migratedFields.removeValue(forKey: "dictationExpression")
        migratedFields.removeValue(forKey: "automaticLearningEnabled")
        migratedFields.removeValue(forKey: "usageTrackingEnabled")
        migratedFields.removeValue(forKey: "usageAccountingIncomplete")
        migratedFields.removeValue(forKey: "decisionReviewMode")
        migratedFields.removeValue(forKey: "decisionProvider")
        migratedFields.removeValue(forKey: "improvementModels")
        migratedFields.removeValue(forKey: "interfaceLanguage")
        for key in ["jevDetailedReviewEnabled", "jevEconomyEnabled", "jevAutomaticImprovementEnabled",
                    "jevClarifyEditsEnabled", "jevReRecognitionEnabled", "jevFeedbackLearningEnabled", "jevNameCatalog"] {
            migratedFields.removeValue(forKey: key)
        }
        // Sets have no stable JSON order; compare them semantically above.
        originalFields.removeValue(forKey: "allowedContextApps")
        migratedFields.removeValue(forKey: "allowedContextApps")
        XCTAssertEqual(originalFields as NSDictionary, migratedFields as NSDictionary)
    }

    func testOlderPartialPreferencesFillMissingSettingsWithoutDiscardingSavedValues() throws {
        let migrated = try JSONDecoder().decode(Preferences.self, from: Data(#"{"provider":"anthropic","retentionDays":7,"historyEnabled":false}"#.utf8))
        XCTAssertEqual(migrated.provider, .anthropic)
        XCTAssertEqual(migrated.retentionDays, 7)
        XCTAssertFalse(migrated.historyEnabled)
        XCTAssertEqual(migrated.hotkeys, HotkeyBinding.defaults)
        XCTAssertEqual(migrated.appearance, "system")
        XCTAssertTrue(migrated.allowedContextApps.isEmpty)
        XCTAssertTrue(migrated.writingProfiles.isEmpty)
    }

    func testExplicitProfileWinsAndResetRestoresAppDefaultWithoutAllowingContext() throws {
        var preferences = Preferences()
        let bundleID = "com.openai.codex"
        XCTAssertEqual(preferences.writingProfile(for: bundleID), .init(kind: .development))
        let customized = WritingProfile(kind: .notes, tone: .polite)
        preferences.writingProfiles[bundleID] = customized
        XCTAssertEqual(preferences.writingProfile(for: bundleID), customized)
        XCTAssertTrue(preferences.allowedContextApps.isEmpty)

        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.writingProfile(for: bundleID), customized)
        XCTAssertTrue(restored.allowedContextApps.isEmpty)

        preferences.writingProfiles.removeValue(forKey: bundleID)
        XCTAssertEqual(preferences.writingProfile(for: bundleID), .init(kind: .development))
        XCTAssertTrue(preferences.allowedContextApps.isEmpty)
    }

    func testCustomAppsAndContextPermissionsRemainIndependent() {
        var preferences = Preferences()
        let unknownApp = "com.example.my-app"
        XCTAssertEqual(preferences.writingProfile(for: unknownApp), .init())
        XCTAssertEqual(preferences.writingProfile(for: nil), .init())
        preferences.allowedContextApps.insert(unknownApp)
        XCTAssertEqual(preferences.writingProfile(for: unknownApp), .init())
        preferences.writingProfiles[unknownApp] = .init(kind: .email, tone: .formal)
        preferences.allowedContextApps.remove(unknownApp)
        XCTAssertEqual(preferences.writingProfile(for: unknownApp), .init(kind: .email, tone: .formal))
        XCTAssertTrue(preferences.allowedContextApps.isEmpty)
    }
}
