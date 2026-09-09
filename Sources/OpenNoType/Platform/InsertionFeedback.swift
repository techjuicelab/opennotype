/// Presentation depends only on delivery state, never on dictated text or clipboard contents.
struct InsertionFeedback: Equatable {
    enum Severity: Equatable { case success, info, warning }

    let message: String
    let severity: Severity
    /// Only a delivery that never reached the target app brings the manager window forward.
    let showResultPage: Bool
    let warnsAboutDuplicatePaste: Bool

    /// Supports the existing notice presentation without rendering uncertain delivery as success.
    var isError: Bool { severity == .warning }

    /// A two-line summary for the floating bar, shown briefly after processing ends.
    var overlayMessage: String {
        switch severity {
        case .success: "입력했습니다."
        case .info: "입력을 보냈지만 완료를 확인하지 못했습니다. 입력창을 확인해 주세요."
        case .warning: "자동입력을 하지 못했습니다. OpenNoType 창에서 결과를 복사해 주세요."
        }
    }

    /// Wording for the recording-free input test, which produces no result to copy.
    var testMessage: String {
        switch severity {
        case .success: return "테스트 문구를 입력했습니다."
        case .info: return "테스트 문구 입력 요청을 보냈지만 완료를 확인하지 못했습니다. 입력창과 아래 진단 내용을 확인해 주세요."
        case .warning:
            let cause = message.components(separatedBy: ". ").first ?? message
            return "테스트 문구를 입력하지 못했습니다. \(cause). 아래 진단 내용을 확인해 주세요."
        }
    }

    init(outcome: InsertionOutcome) {
        switch outcome {
        case .confirmed:
            message = "원래 입력창에 글을 입력했습니다."
            severity = .success
            showResultPage = false
            warnsAboutDuplicatePaste = false
        case .notSubmitted(let reason):
            message = Self.message(for: reason)
            severity = .warning
            showResultPage = true
            warnsAboutDuplicatePaste = false
        case .submittedUnverified(_, let failure):
            let explanation = switch failure {
            case .timedOut: "입력 요청을 보냈지만 입력 완료를 확인하지 못했습니다."
            case .cancelled: "입력 요청을 보낸 뒤 확인이 취소되어 실제 입력 여부를 확인하지 못했습니다."
            }
            // The text was handed over; interrupting the user's app with a window would be worse than
            // a quiet notice. The result stays available under 최근 결과 and 기록.
            message = explanation + " 입력창에 글이 보이지 않으면 OpenNoType의 최근 결과를 복사해 붙여넣으세요. 이미 글이 들어갔다면 다시 붙여넣지 마세요."
            severity = .info
            showResultPage = false
            warnsAboutDuplicatePaste = true
        }
    }

    private static func message(for reason: InsertionBlockReason) -> String {
        switch reason {
        case .emptyText:
            "입력할 내용이 없어 자동입력을 시작하지 않았습니다. 다시 녹음해 주세요."
        case .busy:
            "다른 자동입력 작업이 진행 중이어서 입력하지 않았습니다. 현재 작업이 끝나면 결과를 복사해 원하는 입력창에 붙여넣으세요."
        case .cancelled:
            "자동입력 전에 작업이 취소되었습니다. 필요한 경우 결과를 복사해 원하는 입력창에 붙여넣으세요."
        case .noTarget:
            "글을 입력할 다른 앱을 찾지 못해 자동입력을 시작하지 않았습니다. 원하는 앱의 입력창을 클릭한 뒤 단축키를 누르거나, 결과를 복사해 붙여넣으세요."
        case .permissionMissing:
            "손쉬운 사용 권한이 없어 자동입력을 시작하지 않았습니다. 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 OpenNoType을 허용하거나, 결과를 복사해 붙여넣으세요."
        case .targetChanged:
            "입력할 앱·입력창·선택 문장이 바뀌었거나 원래 앱을 앞으로 가져오지 못해 자동입력을 중단했습니다. 원하는 입력 위치를 확인한 뒤 보관된 결과를 복사해 붙여넣으세요."
        case .secureInput:
            "비밀번호 입력란이거나 보안 입력이 켜진 상태여서 자동입력을 하지 않았습니다. 터미널 앱의 Secure Keyboard Entry 옵션도 같은 상태를 만듭니다. 옵션을 끄거나 다른 입력창에서 다시 시도하거나, 결과를 복사해 붙여넣으세요."
        case .eventsUnavailable:
            "붙여넣기 입력을 준비하지 못해 자동입력을 시작하지 않았습니다. 결과를 복사해 원하는 입력창에 붙여넣으세요."
        case .clipboardUnavailable:
            "현재 클립보드를 안전하게 보관할 수 없어 자동입력을 시작하지 않았습니다. 필요한 클립보드 내용을 따로 보관한 뒤 결과를 복사해 붙여넣으세요."
        case .clipboardChanged:
            "처리 중 클립보드가 바뀌어 자동입력을 중단했습니다. 새로 복사한 내용이 필요하면 먼저 보관한 뒤 결과를 복사해 붙여넣으세요."
        case .clipboardWriteFailed:
            "결과를 클립보드에 준비하지 못해 자동입력을 시작하지 않았습니다. 결과를 복사해 원하는 입력창에 직접 붙여넣으세요."
        }
    }
}
