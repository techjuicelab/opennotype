import XCTest
import OpenNoTypeCore
@testable import OpenNoType

final class PreferencesProviderTests: XCTestCase {
    func testLegacyPreferencesKeepTheSpokenLanguageDespiteTheOldTranslationShortcutTarget() throws {
        let data = Data(#"{"provider":"groq","targetLanguage":"Japanese","retentionDays":7}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(preferences.dictationOutputLanguage, .original)
        XCTAssertEqual(preferences.targetLanguage, "Japanese")
        XCTAssertEqual(preferences.provider, .groq)
        XCTAssertEqual(preferences.retentionDays, 7)
    }

    func testEveryDictationOutputLanguageSurvivesPreferencesRoundTripWithoutChangingRecognition() throws {
        for language in DictationOutputLanguage.allCases {
            var preferences = Preferences()
            preferences.provider = .groq
            preferences.useLocalTranscription = true
            preferences.dictationOutputLanguage = language
            preferences.targetLanguage = "Chinese (Simplified)"
            let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
            XCTAssertEqual(restored.dictationOutputLanguage, language)
            XCTAssertEqual(restored.targetLanguage, "Chinese (Simplified)")
            XCTAssertEqual(restored.provider, .groq)
            XCTAssertTrue(restored.needsLocal)
        }
    }

    func testUnknownOrCorruptDictationOutputLanguageKeepsOtherPreferencesAndDisablesTranslation() throws {
        let values: [Any] = ["future-language", 42, true, NSNull(), ["language": "japanese"]]
        for value in values {
            let data = try JSONSerialization.data(withJSONObject: ["dictationOutputLanguage": value,
                                                                   "targetLanguage": "Japanese",
                                                                   "provider": "groq", "retentionDays": 7])
            let preferences = try JSONDecoder().decode(Preferences.self, from: data)
            XCTAssertEqual(preferences.dictationOutputLanguage, .original)
            XCTAssertEqual(preferences.targetLanguage, "Japanese")
            XCTAssertEqual(preferences.provider, .groq)
            XCTAssertEqual(preferences.retentionDays, 7)
            XCTAssertTrue(preferences.recoveryState.requiresRecovery,
                          "Unreadable output settings must require review before an unintended original-language request")
            XCTAssertTrue(preferences.recoveryState.invalidFields.contains("dictationOutputLanguage"))
        }
    }

    func testLegacySingleProviderKeepsBothStagesOnGroq() throws {
        let legacy = Data(#"{"provider":"groq","transcriptionModels":{"groq":"saved-stt"},"textModels":{"groq":"saved-text"}}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: legacy)
        XCTAssertNil(preferences.textProvider)
        XCTAssertEqual(preferences.effectiveTextProvider, .groq)
        XCTAssertEqual(preferences.transcriptionModel, "saved-stt")
        XCTAssertEqual(preferences.textModel, "saved-text")
    }

    func testIndependentTextProviderPreservesAudioProviderAndModels() throws {
        var preferences = Preferences()
        preferences.provider = .groq
        preferences.textProvider = .openRouter
        preferences.transcriptionModels[AIProvider.groq.rawValue] = "saved-groq-stt"
        preferences.textModels[AIProvider.groq.rawValue] = "saved-groq-text"
        preferences.textModels[AIProvider.openRouter.rawValue] = "saved-router-text"
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.provider, .groq)
        XCTAssertEqual(restored.textProvider, .openRouter)
        XCTAssertEqual(restored.transcriptionModel, "saved-groq-stt")
        XCTAssertEqual(restored.textModel, "saved-router-text")
        XCTAssertEqual(restored.textModels[AIProvider.groq.rawValue], "saved-groq-text")
        XCTAssertFalse(restored.needsLocal)

        preferences.textProvider = .anthropic
        XCTAssertFalse(preferences.needsLocal, "The text provider cannot force Groq audio recognition onto the local engine")
        preferences.textProvider = nil
        XCTAssertEqual(preferences.textModel, "saved-groq-text")
    }

    func testUnreadableTextProviderDoesNotDiscardLegacyProviderOrModels() throws {
        let data = Data(#"{"provider":"groq","textProvider":42,"textModels":{"groq":"saved-text"}}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertNil(preferences.textProvider)
        XCTAssertEqual(preferences.provider, .groq)
        XCTAssertEqual(preferences.textModel, "saved-text")
    }

    func testUnknownTextProviderKeepsLegacyStageInsteadOfSelectingOpenAI() throws {
        let data = Data(#"{"provider":"groq","textProvider":"future-provider","textModels":{"groq":"saved-text","openAI":"unrelated-text"}}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertNil(preferences.textProvider)
        XCTAssertEqual(preferences.effectiveTextProvider, .groq)
        XCTAssertEqual(preferences.textModel, "saved-text")
    }

    func testNewPreferencesKeepOpenAIDefaultWhenGroqIsAvailable() {
        let preferences = Preferences()
        XCTAssertEqual(preferences.provider, .openAI)
        XCTAssertEqual(preferences.transcriptionModel, ProviderDefaults.forProvider(.openAI).transcriptionModel)
        XCTAssertEqual(preferences.textModel, ProviderDefaults.forProvider(.openAI).textModel)
        XCTAssertFalse(preferences.needsLocal)
    }

    func testGroqProviderAndCustomModelsSurvivePreferencesRoundTrip() throws {
        var preferences = Preferences()
        preferences.provider = .groq
        preferences.transcriptionModels[AIProvider.groq.rawValue] = "custom-groq-transcription"
        preferences.textModels[AIProvider.groq.rawValue] = "custom/groq-text"
        preferences.useLocalTranscription = true

        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))

        XCTAssertEqual(restored.provider, .groq)
        XCTAssertEqual(restored.transcriptionModel, "custom-groq-transcription")
        XCTAssertEqual(restored.textModel, "custom/groq-text")
        XCTAssertTrue(restored.useLocalTranscription)
        XCTAssertTrue(restored.needsLocal)
    }

    func testSwitchingProvidersPreservesEveryCustomModelAndUsesGroqDefaults() throws {
        var preferences = Preferences()
        let transcriptionModels = ["openAI": "custom-openai-stt", "openRouter": "custom/router-stt"]
        let textModels = ["openAI": "custom-openai-text", "openRouter": "custom/router-text", "anthropic": "custom-claude-text"]
        preferences.transcriptionModels = transcriptionModels
        preferences.textModels = textModels

        preferences.provider = .groq
        XCTAssertEqual(preferences.transcriptionModel, ProviderDefaults.forProvider(.groq).transcriptionModel)
        XCTAssertEqual(preferences.textModel, ProviderDefaults.forProvider(.groq).textModel)
        XCTAssertFalse(preferences.needsLocal)
        XCTAssertEqual(preferences.transcriptionModels, transcriptionModels)
        XCTAssertEqual(preferences.textModels, textModels)

        preferences.transcriptionModels[AIProvider.groq.rawValue] = "whisper-large-v3"
        preferences.textModels[AIProvider.groq.rawValue] = "custom/groq-text"
        preferences.provider = .openAI
        XCTAssertEqual(preferences.transcriptionModel, "custom-openai-stt")
        XCTAssertEqual(preferences.textModel, "custom-openai-text")
        preferences.provider = .openRouter
        XCTAssertEqual(preferences.transcriptionModel, "custom/router-stt")
        XCTAssertEqual(preferences.textModel, "custom/router-text")
        preferences.provider = .anthropic
        XCTAssertEqual(preferences.textModel, "custom-claude-text")
        XCTAssertTrue(preferences.needsLocal)
        preferences.provider = .groq

        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.transcriptionModel, "whisper-large-v3")
        XCTAssertEqual(restored.textModel, "custom/groq-text")
        XCTAssertEqual(restored.transcriptionModels, transcriptionModels.merging(["groq": "whisper-large-v3"]) { _, new in new })
        XCTAssertEqual(restored.textModels, textModels.merging(["groq": "custom/groq-text"]) { _, new in new })
    }

    func testLegacyOpenAISettingsAndLocalTranscriptionRemainWhenSelectingGroq() throws {
        let legacy = Data(#"""
        {
            "provider": "openAI",
            "transcriptionModels": { "openAI": "saved-openai-stt" },
            "textModels": { "openAI": "saved-openai-text" },
            "targetLanguage": "Japanese",
            "useLocalTranscription": true,
            "allowedContextApps": ["com.example.editor"],
            "writingProfiles": { "com.example.editor": { "kind": "notes", "tone": "polite" } },
            "retentionDays": 7,
            "historyEnabled": false,
            "speakerFilterEnabled": true,
            "appearance": "dark"
        }
        """#.utf8)
        var preferences = try JSONDecoder().decode(Preferences.self, from: legacy)
        XCTAssertEqual(preferences.provider, .openAI)
        XCTAssertEqual(preferences.transcriptionModel, "saved-openai-stt")
        XCTAssertEqual(preferences.textModel, "saved-openai-text")

        preferences.provider = .groq
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertTrue(restored.needsLocal)
        XCTAssertEqual(restored.textModel, ProviderDefaults.forProvider(.groq).textModel)
        XCTAssertEqual(restored.transcriptionModels, ["openAI": "saved-openai-stt"])
        XCTAssertEqual(restored.textModels, ["openAI": "saved-openai-text"])
        XCTAssertEqual(restored.targetLanguage, "Japanese")
        XCTAssertEqual(restored.allowedContextApps, ["com.example.editor"])
        XCTAssertEqual(restored.writingProfile(for: "com.example.editor"), .init(kind: .notes, tone: .polite))
        XCTAssertEqual(restored.retentionDays, 7)
        XCTAssertFalse(restored.historyEnabled)
        XCTAssertTrue(restored.speakerFilterEnabled)
        XCTAssertEqual(restored.appearance, "dark")
        XCTAssertEqual(restored.hotkeys, HotkeyBinding.defaults)
    }

    func testUnknownProviderOrProfileValuesFallBackWithoutDiscardingOtherSettings() throws {
        let future = Data(#"""
        {
            "provider": "someFutureProvider",
            "transcriptionModels": { "openAI": "saved-openai-stt" },
            "textModels": { "openAI": "saved-openai-text" },
            "writingProfiles": { "com.example.editor": { "kind": "poetry", "tone": "polite" } },
            "hotkeys": [ { "keyCode": 49, "modifiers": 2048 } ],
            "retentionDays": 7,
            "appearance": "dark"
        }
        """#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: future)
        XCTAssertEqual(preferences.provider, .openAI, "An unreadable provider falls back to the default")
        XCTAssertEqual(preferences.transcriptionModel, "saved-openai-stt")
        XCTAssertEqual(preferences.textModel, "saved-openai-text")
        XCTAssertTrue(preferences.writingProfiles.isEmpty, "An unreadable profile map falls back to defaults")
        XCTAssertEqual(preferences.hotkeys, HotkeyBinding.defaults, "A partial hotkey list is not adopted")
        XCTAssertEqual(preferences.retentionDays, 7)
        XCTAssertEqual(preferences.appearance, "dark")
    }

    func testBlankCustomModelIdsUseProviderDefaults() {
        var preferences = Preferences()
        preferences.provider = .groq
        preferences.transcriptionModels[AIProvider.groq.rawValue] = "   "
        preferences.textModels[AIProvider.groq.rawValue] = ""
        XCTAssertEqual(preferences.transcriptionModel, ProviderDefaults.forProvider(.groq).transcriptionModel)
        XCTAssertEqual(preferences.textModel, ProviderDefaults.forProvider(.groq).textModel)
        preferences.textModels[AIProvider.groq.rawValue] = " custom/model "
        XCTAssertEqual(preferences.textModel, "custom/model")
    }

    func testGroqUsesLocalTranscriptionOnlyWhenRequestedWithoutChangingSavedCloudModel() {
        var preferences = Preferences()
        preferences.provider = .groq
        preferences.transcriptionModels[AIProvider.groq.rawValue] = "whisper-large-v3"
        XCTAssertFalse(preferences.needsLocal)

        preferences.useLocalTranscription = true
        XCTAssertTrue(preferences.needsLocal)
        XCTAssertEqual(preferences.transcriptionModel, "whisper-large-v3")
        preferences.provider = .anthropic
        preferences.useLocalTranscription = false
        XCTAssertTrue(preferences.needsLocal)
        preferences.provider = .groq
        XCTAssertFalse(preferences.needsLocal)
        XCTAssertEqual(preferences.transcriptionModel, "whisper-large-v3")
    }
}
