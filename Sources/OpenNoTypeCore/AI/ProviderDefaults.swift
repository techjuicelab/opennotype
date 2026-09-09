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
    case httpStatus(Int), connectionFailed, invalidResponse, emptyOutput, incompleteOutput, refused

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "설정에서 선택한 제공자의 API 키를 입력해 주세요."
        case .missingModel: return "설정에서 사용할 모델을 지정해 주세요."
        case .localTranscriptionRequired: return "Claude는 먼저 기기 내 음성 인식으로 전사해야 합니다."
        case .invalidInput: return "처리할 입력이 비어 있거나 지원 범위를 벗어났습니다."
        case .unsupportedAudioFormat: return "지원하지 않는 녹음 파일 형식입니다."
        case .audioTooLarge: return "녹음 파일이 25 MB를 초과했습니다. 더 짧게 녹음해 주세요."
        case .unreadableAudio: return "녹음 파일을 읽을 수 없습니다."
        case .httpStatus(401), .httpStatus(403): return "API 키 또는 선택한 모델의 사용 권한을 확인해 주세요."
        case .httpStatus(402): return "선택한 제공자의 API 잔액과 결제 설정을 확인해 주세요."
        case .httpStatus(429): return "제공자의 사용 한도에 도달했습니다. 잠시 후 다시 시도해 주세요."
        case .httpStatus(let status): return "AI 제공자 요청에 실패했습니다. HTTP \(status)."
        case .connectionFailed: return "AI 제공자에 연결하지 못했습니다. 네트워크 상태를 확인해 주세요."
        case .invalidResponse: return "AI 응답 형식을 확인할 수 없어 입력하지 않았습니다."
        case .emptyOutput: return "인식된 문장이 없어 입력하지 않았습니다."
        case .incompleteOutput: return "AI 응답이 완성되지 않아 입력하지 않았습니다."
        case .refused: return "AI 제공자가 요청을 처리하지 않아 입력하지 않았습니다."
        }
    }
}
