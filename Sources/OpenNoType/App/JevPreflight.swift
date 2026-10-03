import Foundation
import OpenNoTypeCore

/// The same required-review state is used by Home, recording, and recovery.
/// Optional observation never changes the ordinary recording requirements.
enum JevPreflightIssue: Equatable {
    case keyLoading, keyMissing, incompatibleTextProvider

    var message: String {
        switch self {
        case .keyLoading:
            return L("입력 전 교정에 필요한 Jev 키를 준비하고 있습니다. Keychain 작업이 끝난 뒤 시작해 주세요.", "Preparing the Jev key required for pre-typing repair. Start after the Keychain operation finishes.")
        case .keyMissing:
            return L("입력 전 교정을 사용하려면 설정에서 Jev 연결 키를 저장해 주세요. 녹음과 유료 처리는 시작하지 않았습니다.", "Save a Jev connection key in Settings to use pre-typing repair. Recording and paid processing have not started.")
        case .incompatibleTextProvider:
            return L("입력 전 교정의 OpenRouter 키 재사용은 문장 정리 제공자가 OpenRouter일 때 가능합니다. 문장 연결 또는 Jev 직접 연결을 변경해 주세요.", "Pre-typing repair can reuse an OpenRouter key only when OpenRouter processes text. Change the text provider or use a direct Jev connection.")
        }
    }
}

/// Typed diagnostics retain the reason while deliberately omitting provider response bodies.
enum JevReviewFailure: Equatable, Sendable {
    case authentication, lengthLimit, rateLimit, timeout, connection, malformed, invalidInput, service, cancelled

    init(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { self = .cancelled; return }
        guard let error = error as? DecisionError else {
            self = (error as? URLError)?.code == .timedOut ? .timeout : .connection; return
        }
        switch error {
        case .missingAPIKey: self = .authentication
        case .inputTooLarge: self = .lengthLimit
        case .timedOut: self = .timeout
        case .connectionFailed: self = .connection
        case .invalidResponse, .responseTooLarge: self = .malformed
        case .invalidInput: self = .invalidInput
        case .httpStatus(let status):
            switch status {
            case 401, 403: self = .authentication
            case 413: self = .lengthLimit
            case 429: self = .rateLimit
            default: self = .service
            }
        }
    }

    var message: String {
        switch self {
        case .authentication: return L("Jev 인증에 실패했습니다. 저장된 키와 계정 접근을 확인해 주세요.", "Jev authentication failed. Check the saved key and account access.")
        case .lengthLimit: return L("Jev 검토 길이 한도를 넘었습니다. 원문·결과·수정 원문 합계는 24,000 UTF-8 바이트, 요청 전체는 64,000바이트까지입니다. 결과를 직접 확인하거나 녹음을 나누어 주세요.", "The Jev review limit was exceeded: source, result, and edit source can total up to 24,000 UTF-8 bytes; the full request can be up to 64,000 bytes. Review the result yourself or split the recording.")
        case .rateLimit: return L("Jev 요청 한도에 도달했습니다. 잠시 후 다시 검토해 주세요.", "Jev rate limit reached. Review again later.")
        case .timeout: return L("Jev 검토 제한 시간 10초를 넘었습니다. 직접 검토를 다시 실행할 수 있습니다.", "Jev review exceeded its 10-second limit. You can run a manual review again.")
        case .connection: return L("Jev 서비스에 연결하지 못했습니다. 네트워크를 확인해 주세요.", "Could not connect to Jev. Check the network.")
        case .malformed: return L("Jev 응답 형식 또는 크기를 확인하지 못했습니다. 정확한 검토로 처리하지 않았습니다.", "The Jev response format or size could not be verified. It was not treated as a valid review.")
        case .invalidInput: return L("Jev 검토 입력을 확인하지 못했습니다.", "The Jev review input could not be verified.")
        case .service: return L("Jev 서비스가 요청을 처리하지 못했습니다. 잠시 후 다시 검토해 주세요.", "Jev could not process the request. Review again later.")
        case .cancelled: return L("Jev 검토를 취소했습니다.", "Jev review cancelled.")
        }
    }
}
