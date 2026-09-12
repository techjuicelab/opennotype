import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case connection, input, privacy, general

    var id: String { rawValue }
    var title: String {
        switch self {
        case .connection: "AI 연결"
        case .input: "입력·단축키"
        case .privacy: "개인정보"
        case .general: "Mac·일반"
        }
    }
    var detail: String {
        switch self {
        case .connection: "API 키와 음성·문장 모델을 선택하고 사용량을 확인하세요."
        case .input: "단축키, 번역 언어, 앱별 작성 방식을 조정하세요."
        case .privacy: "AI에 보내는 문맥과 개인 사전 학습, 기록 보관을 관리하세요."
        case .general: "앱 업데이트, 로그인 시 실행, 화면 모드와 Mac 접근 권한을 관리하세요."
        }
    }
}
