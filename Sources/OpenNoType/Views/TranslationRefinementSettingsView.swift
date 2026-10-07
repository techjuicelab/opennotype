import SwiftUI

struct TranslationRefinementSettingsView: View {
    @Binding var isEnabled: Bool
    let reviewsBeforeTyping: Bool

    var body: some View {
        Surface(L("번역 문장 다듬기 · 실험 기능", "Translation refinement · Experimental")) {
            Toggle(L("번역 문장 다듬기", "Refine translations"), isOn: $isEnabled)
                .accessibilityHint(L("받아쓰기 번역과 번역 단축키에 적용하며 문장 처리 요청이 한 번 추가됩니다.", "Applies to translated dictation and the translation shortcut, adding one text-processing request."))
            Text(L("받아쓰기 번역과 별도 번역 단축키에 적용합니다. 인식 원문·번역 초안·목표 언어·말투·사전 힌트를 현재 문장 서비스로 한 번 더 보내 표현을 다듬습니다. 처리 시간과 API 비용이 추가될 수 있습니다.", "Applies to translated dictation and the separate translation shortcut. Sends the transcript, draft translation, target language, tone and dictionary hints once more to your current text service to refine the wording. This may add delay and API charges."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Text(L("기본값은 꺼짐이며 다음 번역 처리부터 적용합니다. 다듬기를 완료하지 못하면 원문이나 초안을 대신 자동 입력하지 않고 보류합니다. 진행 중 이 옵션을 끄면 추가 처리가 보류될 수 있습니다.", "Off by default and applies from your next translation job. If refinement cannot finish, typing is held instead of automatically using the transcript or draft. Turning this option off during a job may hold the additional processing."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Text(reviewsBeforeTyping
                 ? L("번역 입력 전 Jev 검토도 켜져 있습니다. 다듬기를 켜면 다듬은 결과를 검토합니다. 표현 다듬기와 검토 모두 정확성을 보장하지 않습니다.", "Pre-typing Jev translation review is also on. If refinement is enabled, it reviews the refined result. Neither refinement nor review guarantees accuracy.")
                 : L("표현 다듬기는 Jev 검토와 별개이며 뜻 보존을 보장하지 않습니다. 입력 전 Jev 검토는 AI 연결 설정에서 따로 켤 수 있습니다.", "Refinement is separate from Jev review and does not guarantee preserved meaning. You can enable pre-typing Jev review separately in AI connection settings."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }
}
