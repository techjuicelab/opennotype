import Foundation

/// File-transcription choices for the app's existing speech endpoints.
/// This catalog does not claim account access, quality, or text-token pricing for audio.
public struct SpeechModelCatalogEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let note: String?
    public let sourceURL: URL
    public let asOf: String

    public init(id: String, title: String, note: String? = nil, sourceURL: URL, asOf: String) {
        self.id = id; self.title = title; self.note = note
        self.sourceURL = sourceURL; self.asOf = asOf
    }
}

public enum SpeechModelCatalog {
    public static let checkedAt = "2026-10-15"

    public static func entries(for provider: AIProvider) -> [SpeechModelCatalogEntry] {
        switch provider {
        case .openAI:
            return [
                entry("gpt-transcribe", "GPT-Transcribe", source: openAISource),
                entry("gpt-4o-mini-transcribe", "GPT-4o Mini Transcribe", note: openAILegacyNote, source: openAISource),
                entry("gpt-4o-transcribe", "GPT-4o Transcribe", note: openAILegacyNote, source: openAISource),
                entry("whisper-1", "Whisper", note: openAILegacyNote, source: openAISource)
            ]
        case .groq:
            return [
                entry("whisper-large-v3-turbo", "Whisper Large v3 Turbo", source: groqSource),
                entry("whisper-large-v3", "Whisper Large v3", source: groqSource)
            ]
        case .openRouter:
            return [
                entry("openai/gpt-transcribe", "GPT-Transcribe", source: openRouterSource),
                entry("openai/gpt-4o-mini-transcribe", "GPT-4o Mini Transcribe", note: openRouterLegacyNote, source: openRouterSource),
                entry("openai/gpt-4o-transcribe", "GPT-4o Transcribe", note: openRouterLegacyNote, source: openRouterSource),
                entry("openai/whisper-1", "Whisper", note: openRouterLegacyNote, source: openRouterSource),
                entry("openai/whisper-large-v3", "Whisper Large v3", source: openRouterSource),
                entry("openai/whisper-large-v3-turbo", "Whisper Large v3 Turbo", source: openRouterSource)
            ]
        case .anthropic:
            return []
        }
    }

    private static let openAISource = "https://developers.openai.com/api/docs/guides/speech-to-text"
    private static let groqSource = "https://console.groq.com/docs/speech-to-text"
    private static let openRouterSource = "https://openrouter.ai/api/v1/models?output_modalities=transcription"
    private static var openAILegacyNote: String {
        L("기존 전사 모델입니다. OpenAI 직접 API는 2027-02-26 지원 종료 예정입니다. 현재 기본 GPT-Transcribe는 유지됩니다.", "A legacy transcription model scheduled to shut down on the direct OpenAI API on 2027-02-26. GPT-Transcribe remains the existing default.")
    }
    private static var openRouterLegacyNote: String {
        L("OpenAI 기반 기존 전사 모델입니다. OpenAI 직접 API의 지원 종료 예정일은 2027-02-26이며 OpenRouter 제공 일정은 별도로 확인해야 합니다.", "A legacy OpenAI transcription model. The direct OpenAI API is scheduled to shut it down on 2027-02-26; check the OpenRouter availability schedule separately.")
    }
    private static func entry(_ id: String, _ title: String, note: String? = nil, source: String) -> SpeechModelCatalogEntry {
        SpeechModelCatalogEntry(id: id, title: title, note: note, sourceURL: URL(string: source)!, asOf: checkedAt)
    }
}
