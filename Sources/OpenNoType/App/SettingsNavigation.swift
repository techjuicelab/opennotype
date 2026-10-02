import OpenNoTypeCore
import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case connection, input, privacy, general

    var id: String { rawValue }
    var title: String {
        switch self {
        case .connection: L("AI 연결", "AI connection")
        case .input: L("입력·단축키", "Input & shortcuts")
        case .privacy: L("개인정보", "Privacy")
        case .general: L("Mac·일반", "Mac & general")
        }
    }
    var detail: String {
        switch self {
        case .connection: L("API 키와 음성·문장 모델을 선택하고 사용량을 확인하세요.", "Choose API keys and speech and text models, and review usage.")
        case .input: L("단축키, 번역 언어, 앱별 작성 방식을 조정하세요.", "Set shortcuts, the translation language, and writing styles for each app.")
        case .privacy: L("AI에 보내는 문맥과 개인 사전 학습, 기록 보관을 관리하세요.", "Manage context sent to AI, dictionary learning, and history retention.")
        case .general: L("앱 업데이트, 로그인 시 실행, 화면 모드와 Mac 접근 권한을 관리하세요.", "Manage updates, launch at login, appearance, interface language, and Mac permissions.")
        }
    }
}
