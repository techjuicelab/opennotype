import OpenNoTypeCore
import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case dictation, input, connection, privacy, general, advanced

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dictation: L("받아쓰기", "Dictation")
        case .advanced: L("고급 도구", "Advanced tools")
        case .connection: L("AI 연결", "AI connection")
        case .input: L("녹음·단축키", "Recording & shortcuts")
        case .privacy: L("개인정보", "Privacy")
        case .general: L("앱 관리", "App")
        }
    }
    var detail: String {
        switch self {
        case .dictation: L("입력 방식·언어·표현·검토를 조정하세요.", "Choose processing, language, expression and review.")
        case .advanced: L("실험 기능과 문제 해결 도구입니다.", "Experimental features and troubleshooting tools.")
        case .connection: L("API 키와 음성·문장 모델을 선택하고 사용량을 확인하세요.", "Choose API keys and speech and text models, and review usage.")
        case .input: L("마이크와 단축키 동작을 조정하세요.", "Choose your microphone and shortcut behavior.")
        case .privacy: L("AI에 보내는 문맥과 개인 사전 학습, 기록 보관을 관리하세요.", "Manage context sent to AI, dictionary learning, and history retention.")
        case .general: L("앱 업데이트, 로그인 시 실행, 화면 모드와 Mac 접근 권한을 관리하세요.", "Manage updates, launch at login, appearance, interface language, and Mac permissions.")
        }
    }
}

/// Ephemeral navigation only; this is not part of saved preferences or the vault.
enum DictionarySection: String, CaseIterable, Identifiable {
    case words, learning, names
    var id: String { rawValue }
    var title: String {
        switch self {
        case .words: L("단어", "Words")
        case .learning: L("교정 학습", "Learning")
        case .names: L("이름 후보", "Name candidates")
        }
    }
}
