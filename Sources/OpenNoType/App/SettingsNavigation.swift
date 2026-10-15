import OpenNoTypeCore
import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case dictation, input, connection, privacy, general, advanced

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dictation: L("받아쓰기", "Dictation")
        case .advanced: L("실험·진단", "Experiments & diagnostics")
        case .connection: L("AI 연결", "AI connections")
        case .input: L("녹음·단축키", "Recording & shortcuts")
        case .privacy: L("개인정보", "Privacy")
        case .general: L("앱 설정", "App settings")
        }
    }
    var detail: String {
        switch self {
        case .dictation: L("입력 방식·언어·표현·검토를 조정하세요.", "Choose processing, language, expression and review.")
        case .advanced: L("실험 기능, 모델 비교와 처리 진단을 확인하세요.", "Explore experiments, model comparisons and processing diagnostics.")
        case .connection: L("음성 인식·문장 처리·문장 검토의 제공자와 API 키를 설정하세요.", "Set up providers and API keys for speech, text processing and text review.")
        case .input: L("마이크와 단축키 동작을 조정하세요.", "Choose your microphone and shortcut behavior.")
        case .privacy: L("AI에 보내는 문맥과 개인 사전 학습, 기록 보관을 관리하세요.", "Manage context sent to AI, dictionary learning, and history retention.")
        case .general: L("앱 업데이트, 로그인 시 실행, 화면 모드와 Mac 접근 권한을 관리하세요.", "Manage updates, launch at login, appearance, interface language, and Mac permissions.")
        }
    }
}

/// One owner for each settings destination, shared by the manager and its entry points.
/// These routes are ephemeral and never change saved processing preferences.
enum SettingsDetail: String, CaseIterable, Identifiable {
    case speech, text, reviewConnection, jev, assistance, learning, profiles, context
    case diagnostics, permissions, typingTest, comparison, speechComparison, speaker, licenses

    var id: String { rawValue }
    var section: SettingsSection {
        switch self {
        case .speech, .text, .reviewConnection: .connection
        case .jev, .assistance, .profiles: .dictation
        case .learning, .context: .privacy
        case .permissions, .typingTest, .licenses: .general
        case .diagnostics, .comparison, .speechComparison, .speaker: .advanced
        }
    }
    var title: String {
        switch self {
        case .speech: L("음성 인식 연결", "Speech connection")
        case .text: L("문장 처리 연결", "Text connection")
        case .reviewConnection: L("문장 검토 연결 · Jev", "Text review connection · Jev")
        case .jev: L("자동 문장 검토", "Automatic text review")
        case .assistance: L("검토 도움 설정", "Review assistance settings")
        case .learning: L("오류 유형 학습", "Error-pattern learning")
        case .profiles: L("앱별 작성 방식", "Writing style by app")
        case .context: L("주변 문맥 허용", "Context access")
        case .diagnostics: L("처리 진단", "Processing diagnostics")
        case .permissions: L("Mac 접근 권한", "Mac permissions")
        case .typingTest: L("입력 테스트", "Typing test")
        case .comparison: L("문장 모델 비교", "Text model comparison")
        case .speechComparison: L("음성 모델 비교", "Speech model comparison")
        case .speaker: L("내 목소리 구분", "Recognize my voice")
        case .licenses: L("모델·라이선스", "Models and licenses")
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
