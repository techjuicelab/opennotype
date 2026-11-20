import OpenNoTypeCore
import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case dictation, recording, aiModels, privacy, app

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dictation: L("받아쓰기·번역", "Dictation")
        case .recording: L("녹음·단축키", "Recording")
        case .aiModels: L("AI 모델·비용", "AI & Costs")
        case .privacy: L("개인정보·기록", "Privacy")
        case .app: L("앱·진단", "App")
        }
    }
    /// Short label for narrow windows. A segmented control gives every segment the width of its
    /// longest label, so long titles made the picker wider than the settings page.
    var tabTitle: String {
        switch self {
        case .dictation: L("받아쓰기", "Dictation")
        case .recording: L("녹음", "Record")
        case .aiModels: L("AI·비용", "AI")
        case .privacy: L("개인정보", "Privacy")
        case .app: L("앱", "App")
        }
    }
    var icon: String {
        switch self {
        case .dictation: "waveform"
        case .recording: "mic"
        case .aiModels: "cpu"
        case .privacy: "lock.shield"
        case .app: "gearshape"
        }
    }
    var detail: String {
        switch self {
        case .dictation: L("받아쓰기 방식·출력 언어·말투·번역·자동 검토를 정합니다.", "Choose processing, output language, tone, translation and automatic review.")
        case .recording: L("마이크와 단축키, 실험적 녹음 기능을 조정합니다.", "Choose your microphone, shortcuts and experimental recording features.")
        case .aiModels: L("기능별 AI 모델과 API 키, 단가와 비용을 관리합니다.", "Manage AI models by task, API keys, prices and costs.")
        case .privacy: L("기록 보관, 외부 전송과 주변 문맥, 학습과 사용량 기록을 관리합니다.", "Manage history, data sent to AI, context, learning and usage records.")
        case .app: L("Mac 권한과 입력 확인, 화면, 업데이트, 진단을 관리합니다.", "Manage Mac permissions, typing checks, appearance, updates and diagnostics.")
        }
    }
}

/// One owner for each settings destination, shared by the manager and its entry points.
/// These routes are ephemeral and never change saved processing preferences. Most destinations
/// are cards on their section page; only tools that need their own space open as sheets.
enum SettingsDetail: String, CaseIterable, Identifiable {
    case speech, text, reviewConnection, keys, costs, jev, assistance, learning, profiles, context
    case diagnostics, permissions, typingTest, comparison, speechComparison, speaker, licenses

    var id: String { rawValue }
    var section: SettingsSection {
        switch self {
        case .speech, .text, .reviewConnection, .keys, .costs, .comparison, .speechComparison: .aiModels
        case .jev, .assistance, .profiles: .dictation
        case .learning, .context: .privacy
        case .speaker: .recording
        case .permissions, .typingTest, .licenses, .diagnostics: .app
        }
    }
    /// Sheets keep long lists and comparison tools out of the page; everything else is a card.
    var opensSheet: Bool {
        switch self {
        case .profiles, .comparison, .speechComparison, .licenses: true
        default: false
        }
    }
    /// The card a destination scrolls to when it is shown inline.
    var anchor: String {
        switch self {
        case .speech: "settings-card-model-transcription"
        case .text: "settings-card-models"
        case .reviewConnection: "settings-card-model-review"
        case .keys: "settings-card-keys"
        case .costs: "settings-card-costs"
        case .jev, .assistance: "settings-card-review"
        case .learning: "settings-card-learning"
        case .context: "settings-card-transfer"
        case .speaker: "settings-card-experiments"
        case .permissions, .typingTest: "settings-card-permissions"
        case .diagnostics: "settings-card-diagnostics"
        case .profiles, .comparison, .speechComparison, .licenses: "settings-page-top"
        }
    }
    var title: String {
        switch self {
        case .speech: L("음성 인식 모델", "Speech recognition model")
        case .text: L("기능별 AI 모델", "AI models by task")
        case .reviewConnection: L("문장 검토 연결 · Jev", "Text review connection · Jev")
        case .keys: L("제공자와 API 키", "Providers and API keys")
        case .costs: L("비용 상세·예측", "Cost details & estimate")
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
