import Foundation

public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI, groq, openRouter, anthropic
    public var id: String { rawValue }
    public var displayName: String {
        switch self { case .openAI: "OpenAI"; case .groq: "Groq"; case .openRouter: "OpenRouter"; case .anthropic: "Claude" }
    }

    /// A provider added by a newer build must not make an older build reject the whole encrypted vault
    /// or the preferences; the entry is kept and attributed to the default provider instead.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AIProvider(rawValue: raw) ?? .openAI
    }
}

public enum InputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case dictation, translation, rewrite, prompt
    public var id: String { rawValue }
    public var title: String {
        switch self { case .dictation: L("받아쓰기", "Dictation"); case .translation: L("번역", "Translation"); case .rewrite: L("선택 문장 수정", "Edit selected text"); case .prompt: L("프롬프트 만들기", "Create a prompt") }
    }
}

public struct ProviderConfiguration: Sendable {
    public var provider: AIProvider
    public var apiKey: String
    public var transcriptionModel: String
    public var textModel: String
    public init(provider: AIProvider, apiKey: String, transcriptionModel: String, textModel: String) {
        self.provider = provider; self.apiKey = apiKey
        self.transcriptionModel = transcriptionModel; self.textModel = textModel
    }
}

public struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var spoken: String
    public var written: String
    public var createdAt: Date
    public var learned: Bool
    public init(id: UUID = UUID(), spoken: String, written: String, createdAt: Date = Date(), learned: Bool = false) {
        self.id = id; self.spoken = spoken; self.written = written; self.createdAt = createdAt; self.learned = learned
    }
}

public struct ProcessingRequest: Sendable {
    public var mode: InputMode
    public var transcript: String
    public var selectedText: String?
    public var context: String?
    public var dictionary: [DictionaryEntry]
    public var targetLanguage: String
    /// Applies only to dictation. Translation mode retains its explicit target; voice edits ignore it.
    public var outputLanguage: DictationOutputLanguage
    public var writingProfile: WritingProfile
    /// An explicit alternative or a bounded reviewed repair. Never sent in ordinary processing.
    public var previousOutput: String?
    /// Fixed categories learned from verified repairs, without previous utterances or results.
    public var reviewLessons: [JevRepairIssue]
    /// Fixed risk categories for one repair of previousOutput. They are not proof of an error.
    public var repairIssues: [JevRepairIssue]
    /// A first translation to refine against transcript, never a user-requested alternative.
    public var translationDraft: String?
    /// A reviewed prompt draft for one final polish, isolated from translation and dictation.
    public var promptDraft: String?
    public var promptReviewIssues: [PromptCompositionIssue]
    public var effectiveMode: InputMode {
        mode == .dictation && outputLanguage.isTranslation ? .translation : mode
    }
    public var effectiveTargetLanguage: String {
        mode == .dictation ? outputLanguage.targetLanguage ?? targetLanguage : targetLanguage
    }
    public var requiresTranslation: Bool { effectiveMode == .translation }

    public init(mode: InputMode, transcript: String, selectedText: String? = nil, context: String? = nil, dictionary: [DictionaryEntry] = [], targetLanguage: String = "English (United States)", outputLanguage: DictationOutputLanguage = .original, writingProfile: WritingProfile = .init(), previousOutput: String? = nil, reviewLessons: [JevRepairIssue] = [], repairIssues: [JevRepairIssue] = [], translationDraft: String? = nil, promptDraft: String? = nil, promptReviewIssues: [PromptCompositionIssue] = []) {
        self.mode = mode; self.transcript = transcript; self.selectedText = selectedText
        self.context = context; self.dictionary = dictionary; self.targetLanguage = targetLanguage
        self.outputLanguage = outputLanguage
        self.writingProfile = writingProfile
        self.previousOutput = previousOutput
        self.reviewLessons = reviewLessons
        self.repairIssues = repairIssues
        self.translationDraft = translationDraft
        self.promptDraft = promptDraft
        self.promptReviewIssues = promptReviewIssues
    }
}

/// Captured delivery state, separate from an explicit copy or a later manual review.
public struct PromptCompositionReviewSummary: Codable, Equatable, Sendable {
    public var deliveryDisposition: PromptCompositionDeliveryDisposition
    public var warningIssues: [PromptCompositionIssue]
    public init(deliveryDisposition: PromptCompositionDeliveryDisposition, warningIssues: [PromptCompositionIssue] = []) {
        self.deliveryDisposition = deliveryDisposition
        self.warningIssues = warningIssues
    }
}

public struct HistoryEntry: Codable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var mode: InputMode
    public var originalText: String
    public var resultText: String
    public var sourceBundleID: String?
    public var provider: AIProvider
    /// Captured transformation settings; absent in legacy history entries.
    public var writingProfile: WritingProfile?
    /// Captured output settings; absent in legacy history entries.
    public var outputLanguage: DictationOutputLanguage?
    public var targetLanguage: String?
    /// Missing in legacy records; absence never implies that a prompt passed review.
    public var promptReviewSummary: PromptCompositionReviewSummary?
    public var effectiveMode: InputMode {
        mode == .dictation && outputLanguage?.isTranslation == true ? .translation : mode
    }
    public init(id: UUID = UUID(), createdAt: Date = Date(), mode: InputMode, originalText: String, resultText: String, sourceBundleID: String? = nil, provider: AIProvider, writingProfile: WritingProfile? = nil, outputLanguage: DictationOutputLanguage? = nil, targetLanguage: String? = nil, promptReviewSummary: PromptCompositionReviewSummary? = nil) {
        self.id = id; self.createdAt = createdAt; self.mode = mode; self.originalText = originalText
        self.resultText = resultText; self.sourceBundleID = sourceBundleID; self.provider = provider
        self.writingProfile = writingProfile
        self.outputLanguage = outputLanguage
        self.targetLanguage = targetLanguage
        self.promptReviewSummary = promptReviewSummary
    }
}

public struct FailedRecording: Codable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var expiresAt: Date
    public var mode: InputMode
    public var provider: AIProvider
    /// nil preserves the single-provider setting stored by earlier builds.
    public var textProvider: AIProvider?
    public var targetLanguage: String
    public var transcriptionModel: String?
    public var textModel: String?
    public var usedLocalTranscription: Bool?
    public var usedSpeakerFilter: Bool?
    public var writingProfile: WritingProfile?
    public var outputLanguage: DictationOutputLanguage?
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, expiresAt, mode, provider, textProvider, targetLanguage
        case transcriptionModel, textModel, usedLocalTranscription, usedSpeakerFilter, writingProfile, outputLanguage
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        expiresAt = try values.decode(Date.self, forKey: .expiresAt)
        mode = try values.decode(InputMode.self, forKey: .mode)
        provider = try values.decode(AIProvider.self, forKey: .provider)
        // Unknown optional stage providers retain the earlier single-provider contract.
        // AIProvider's global decoder defaults to OpenAI, which would change this stage's route.
        let rawTextProvider = try? values.decodeIfPresent(String.self, forKey: .textProvider)
        textProvider = rawTextProvider.flatMap(AIProvider.init(rawValue:))
        targetLanguage = try values.decode(String.self, forKey: .targetLanguage)
        transcriptionModel = try values.decodeIfPresent(String.self, forKey: .transcriptionModel)
        textModel = try values.decodeIfPresent(String.self, forKey: .textModel)
        usedLocalTranscription = try values.decodeIfPresent(Bool.self, forKey: .usedLocalTranscription)
        usedSpeakerFilter = try values.decodeIfPresent(Bool.self, forKey: .usedSpeakerFilter)
        writingProfile = try values.decodeIfPresent(WritingProfile.self, forKey: .writingProfile)
        outputLanguage = try values.decodeIfPresent(DictationOutputLanguage.self, forKey: .outputLanguage)
    }
    public init(id: UUID = UUID(), createdAt: Date = Date(), mode: InputMode, provider: AIProvider, textProvider: AIProvider? = nil, targetLanguage: String, transcriptionModel: String? = nil, textModel: String? = nil, usedLocalTranscription: Bool? = nil, usedSpeakerFilter: Bool? = nil, writingProfile: WritingProfile? = nil, outputLanguage: DictationOutputLanguage? = nil) {
        self.id = id; self.createdAt = createdAt; self.expiresAt = createdAt.addingTimeInterval(86400)
        self.mode = mode; self.provider = provider; self.textProvider = textProvider; self.targetLanguage = targetLanguage
        self.transcriptionModel = transcriptionModel; self.textModel = textModel
        self.usedLocalTranscription = usedLocalTranscription; self.usedSpeakerFilter = usedSpeakerFilter
        self.writingProfile = writingProfile
        self.outputLanguage = outputLanguage
    }
}

public enum RecordingPolicy {
    public static let maximumDuration: TimeInterval = 540
    public static let warningStartsAt: TimeInterval = 480
    public static func countdown(elapsed: TimeInterval) -> Int? {
        guard elapsed >= warningStartsAt else { return nil }
        return max(0, Int(ceil(maximumDuration - elapsed)))
    }
}

/// The separately installed prompt test app never shares the production app's storage namespace.
public struct AppIdentity: Equatable, Sendable {
    public let isPromptTest: Bool

    public init(bundleIdentifier: String?) {
        isPromptTest = bundleIdentifier == "app.opennotype.prompt-test"
    }

    public static var current: AppIdentity { AppIdentity(bundleIdentifier: Bundle.main.bundleIdentifier) }
    public var displayName: String { isPromptTest ? "OpenNoType Prompt Test" : "OpenNoType" }
    public var supportDirectoryName: String { displayName }
    public var providerSecretService: String {
        isPromptTest ? "app.opennotype.prompt-test.provider-secrets" : "app.opennotype.provider-secrets"
    }
    public var encryptionKeyService: String {
        isPromptTest ? "app.opennotype.prompt-test.encryption-key" : "app.opennotype.encryption-key"
    }
    public var temporaryDirectoryName: String { isPromptTest ? "OpenNoType-Prompt-Test" : "OpenNoType" }
}
