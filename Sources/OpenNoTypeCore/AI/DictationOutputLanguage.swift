import Foundation

/// Dictation output is independent of recognition, interface language and wording preferences.
public enum DictationOutputLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, english, japanese, korean

    public var id: String { rawValue }
    public var isTranslation: Bool { self != .original }

    public var title: String {
        switch self {
        case .original: L("말한 언어 유지", "Keep spoken language")
        case .english: L("영어", "English")
        case .japanese: L("일본어", "Japanese")
        case .korean: L("한국어", "Korean")
        }
    }

    public var detail: String {
        switch self {
        case .original:
            L("말한 언어로 문장을 정리합니다.", "Cleans up your words in the language you spoke.")
        case .english:
            L("뜻과 말투를 유지하며 자연스러운 영어로 전달합니다.", "Expresses the same meaning and tone in natural English.")
        case .japanese:
            L("뜻과 공손함을 유지하며 자연스러운 일본어로 전달합니다.", "Expresses the same meaning and politeness in natural Japanese.")
        case .korean:
            L("뜻과 말투를 유지하며 자연스러운 한국어로 전달합니다.", "Expresses the same meaning and tone in natural Korean.")
        }
    }

    /// Fixed targets only; dictated text cannot select a language or inject instructions.
    public var targetLanguage: String? {
        switch self {
        case .original: nil
        case .english: "English (United States)"
        case .japanese: "Japanese"
        case .korean: "Korean"
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .original
    }
}
