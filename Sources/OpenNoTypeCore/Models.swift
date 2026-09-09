import Foundation

public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI, openRouter, anthropic
    public var id: String { rawValue }
    public var displayName: String {
        switch self { case .openAI: "OpenAI"; case .openRouter: "OpenRouter"; case .anthropic: "Claude" }
    }
}

public enum InputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case dictation, translation, rewrite
    public var id: String { rawValue }
    public var title: String {
        switch self { case .dictation: "받아쓰기"; case .translation: "번역"; case .rewrite: "선택 문장 수정" }
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
    public var writingProfile: WritingProfile
    public init(mode: InputMode, transcript: String, selectedText: String? = nil, context: String? = nil, dictionary: [DictionaryEntry] = [], targetLanguage: String = "English (United States)", writingProfile: WritingProfile = .init()) {
        self.mode = mode; self.transcript = transcript; self.selectedText = selectedText
        self.context = context; self.dictionary = dictionary; self.targetLanguage = targetLanguage
        self.writingProfile = writingProfile
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
    public init(id: UUID = UUID(), createdAt: Date = Date(), mode: InputMode, originalText: String, resultText: String, sourceBundleID: String? = nil, provider: AIProvider) {
        self.id = id; self.createdAt = createdAt; self.mode = mode; self.originalText = originalText
        self.resultText = resultText; self.sourceBundleID = sourceBundleID; self.provider = provider
    }
}

public struct FailedRecording: Codable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var expiresAt: Date
    public var mode: InputMode
    public var provider: AIProvider
    public var targetLanguage: String
    public var transcriptionModel: String?
    public var textModel: String?
    public var usedLocalTranscription: Bool?
    public var usedSpeakerFilter: Bool?
    public var writingProfile: WritingProfile?
    public init(id: UUID = UUID(), createdAt: Date = Date(), mode: InputMode, provider: AIProvider, targetLanguage: String, transcriptionModel: String? = nil, textModel: String? = nil, usedLocalTranscription: Bool? = nil, usedSpeakerFilter: Bool? = nil, writingProfile: WritingProfile? = nil) {
        self.id = id; self.createdAt = createdAt; self.expiresAt = createdAt.addingTimeInterval(86400)
        self.mode = mode; self.provider = provider; self.targetLanguage = targetLanguage
        self.transcriptionModel = transcriptionModel; self.textModel = textModel
        self.usedLocalTranscription = usedLocalTranscription; self.usedSpeakerFilter = usedSpeakerFilter
        self.writingProfile = writingProfile
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
