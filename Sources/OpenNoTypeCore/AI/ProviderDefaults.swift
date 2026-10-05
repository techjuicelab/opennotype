import Foundation

/// Documented model identifiers, not a claim of account access or measured quality.
public struct ProviderDefaults: Sendable {
    public let transcriptionModel: String
    public let textModel: String
    public let requiresLocalTranscription: Bool

    public static func forProvider(_ provider: AIProvider) -> Self {
        switch provider {
        case .openAI:
            return Self(transcriptionModel: "gpt-transcribe", textModel: "gpt-4.1-mini", requiresLocalTranscription: false)
        case .openRouter:
            return Self(transcriptionModel: "openai/gpt-transcribe", textModel: "openai/gpt-4.1-mini", requiresLocalTranscription: false)
        case .anthropic:
            return Self(transcriptionModel: "", textModel: "claude-haiku-4-5-20251001", requiresLocalTranscription: true)
        case .groq:
            return Self(transcriptionModel: "whisper-large-v3-turbo", textModel: "openai/gpt-oss-120b", requiresLocalTranscription: false)
        }
    }
}

public enum ProviderError: Error, LocalizedError, Equatable, Sendable {
    case missingAPIKey, missingModel, localTranscriptionRequired
    case invalidInput, unsupportedAudioFormat, audioTooLarge, unreadableAudio
    case httpStatus(Int), connectionFailed, timedOut, responseTooLarge, invalidResponse, emptyOutput, incompleteOutput, refused
    case translationLiteralChanged, translationTimeInferred

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return L("설정에서 선택한 제공자의 API 키를 입력해 주세요.", "Enter an API key for the selected provider in Settings.")
        case .missingModel: return L("설정에서 사용할 모델을 지정해 주세요.", "Choose a model in Settings.")
        case .localTranscriptionRequired: return L("Claude는 먼저 기기 내 음성 인식으로 전사해야 합니다.", "Claude requires on-device transcription first.")
        case .invalidInput: return L("처리할 입력이 비어 있거나 지원 범위를 벗어났습니다.", "The input is empty or outside the supported limits.")
        case .unsupportedAudioFormat: return L("지원하지 않는 녹음 파일 형식입니다.", "This recording format is not supported.")
        case .audioTooLarge: return L("녹음 파일이 25 MB를 초과했습니다. 더 짧게 녹음해 주세요.", "The recording exceeds 25 MB. Record a shorter clip.")
        case .unreadableAudio: return L("녹음 파일을 읽을 수 없습니다.", "The recording could not be read.")
        case .httpStatus(401), .httpStatus(403): return L("API 키 또는 선택한 모델의 사용 권한을 확인해 주세요.", "Check your API key and access to the selected model.")
        case .httpStatus(402): return L("선택한 제공자의 API 잔액과 결제 설정을 확인해 주세요.", "Check your API balance and billing settings with the selected provider.")
        case .httpStatus(429): return L("제공자의 사용 한도에 도달했습니다. 잠시 후 다시 시도해 주세요.", "The provider usage limit was reached. Try again later.")
        case .httpStatus(let status): return L("AI 제공자 요청에 실패했습니다. HTTP \(status).", "The AI provider request failed. HTTP \(status).")
        case .connectionFailed: return L("AI 제공자에 연결하지 못했습니다. 네트워크 상태를 확인해 주세요.", "Could not connect to the AI provider. Check your network connection.")
        case .timedOut: return L("AI 응답 대기 시간이 초과되어 입력하지 않았습니다. 잠시 후 다시 시도해 주세요.", "Nothing was inserted because the AI request timed out. Try again later.")
        case .responseTooLarge: return L("AI 응답이 크기 제한을 초과하여 입력하지 않았습니다.", "Nothing was inserted because the AI response exceeded the size limit.")
        case .invalidResponse: return L("AI 응답 형식을 확인할 수 없어 입력하지 않았습니다.", "Nothing was inserted because the AI response format could not be verified.")
        case .emptyOutput: return L("인식된 문장이 없어 입력하지 않았습니다.", "Nothing was inserted because no text was recognized.")
        case .translationLiteralChanged: return L("번역에서 보존해야 할 표기가 달라져 입력하지 않았습니다. 원문을 확인하고 다시 시도해 주세요.", "Nothing was inserted because the translation changed a protected identifier or URL. Check the source and try again.")
        case .translationTimeInferred: return L("번역에서 원문에 없는 오전·오후가 추가되어 입력하지 않았습니다. 원문을 확인하고 다시 시도해 주세요.", "Nothing was inserted because the translation added an unstated AM or PM. Check the source and try again.")
        case .incompleteOutput: return L("AI 응답이 완성되지 않아 입력하지 않았습니다.", "Nothing was inserted because the AI response was incomplete.")
        case .refused: return L("AI 제공자가 요청을 처리하지 않아 입력하지 않았습니다.", "Nothing was inserted because the AI provider declined the request.")
        }
    }
}
