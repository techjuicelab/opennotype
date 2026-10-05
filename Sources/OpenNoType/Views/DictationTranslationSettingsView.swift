import SwiftUI
import OpenNoTypeCore

struct DictationTranslationSettingsView: View {
    @Binding var outputLanguage: DictationOutputLanguage
    @State private var showsExamples = false
    @State private var appliedLanguage: DictationOutputLanguage?

    var body: some View {
        Surface(L("받아쓰기 출력 언어", "Dictation output language")) {
            Text(L("평소 받아쓰기 단축키로 말하고, 선택한 언어로 바로 입력하세요. 말한 언어 유지를 선택하면 원래 언어로 정리합니다.", "Use your usual dictation shortcut and type in the language you choose. Keep spoken language cleans up your speech in its original language."))
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            HStack(alignment: .center, spacing: 16) {
                Label(outputLanguage.title, systemImage: outputLanguage.isTranslation ? "character.bubble" : "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .accessibilityLabel(L("현재 받아쓰기 출력 언어: \(outputLanguage.title)", "Current dictation output language: \(outputLanguage.title)"))
                Spacer()
                Button(L("언어 선택·예시 보기…", "Choose language & preview…"), systemImage: "rectangle.on.rectangle") {
                    showsExamples = true
                }
                .help(L("번역 예시를 비교한 뒤 적용합니다. 미리보기만으로 설정이 바뀌지 않습니다.", "Compare translation examples before applying. Previewing does not change your setting."))
            }
            Text(outputLanguage.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            if outputLanguage.isTranslation {
                Text(L("번역할 때는 요약·창작 설정을 적용하지 않습니다. 숫자·이름·조건·부정과 말투를 유지하도록 번역합니다.", "Translation does not apply summary or creative settings. It aims to preserve numbers, names, conditions, negation, and tone."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                Text(L("AI 모델에 따라 의미나 표현이 달라질 수 있습니다. 최근 결과에서 원문과 비교하거나 Jev로 직접 검토할 수 있습니다.", "Meaning or wording can vary with the AI model. Compare with the transcript or request a Jev review from Latest result."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }
            if let appliedLanguage {
                Label(L("\(appliedLanguage.title) 적용됨 · 다음 녹음부터 사용합니다.", "\(appliedLanguage.title) applied · Starts with your next recording."), systemImage: "checkmark.circle")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.accentForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showsExamples) {
            DictationTranslationExamplesView(outputLanguage: $outputLanguage) { language in
                appliedLanguage = language
            }
        }
    }
}
