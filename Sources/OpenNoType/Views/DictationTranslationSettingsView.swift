import SwiftUI
import OpenNoTypeCore

struct DictationTranslationSettingsView: View {
    @Binding var outputLanguage: DictationOutputLanguage
    var isEditable: Bool = true
    @State private var showsExamples = false
    @State private var appliedLanguage: DictationOutputLanguage?

    var body: some View {
        Surface {
            HStack(alignment: .center, spacing: 12) {
                OptionHelpLabel(L("받아쓰기 출력 언어", "Dictation output language"), help: outputLanguageHelp)
                Spacer()
                Label(outputLanguage.title, systemImage: outputLanguage.isTranslation ? "character.bubble" : "waveform")
                    .font(.system(size: 13, weight: .medium))
                    .accessibilityLabel(L("현재 받아쓰기 출력 언어: \(outputLanguage.title)", "Current dictation output language: \(outputLanguage.title)"))
                Button(L("언어·예시…", "Language & examples…"), systemImage: "rectangle.on.rectangle") {
                    showsExamples = true
                }
                .disabled(!isEditable)
                .help(L("번역 예시를 비교한 뒤 적용합니다. 미리보기만으로 설정이 바뀌지 않습니다.", "Compare translation examples before applying. Previewing does not change your setting."))
            }
            if outputLanguage.isTranslation {
                Text(L("번역 출력 · 받아쓰기 표현 설정은 사용하지 않습니다.", "Translation output · Dictation wording settings are not applied."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let appliedLanguage {
                Label(L("\(appliedLanguage.title) 적용됨 · 다음 녹음부터 사용합니다.", "\(appliedLanguage.title) applied · Starts with your next recording."), systemImage: "checkmark.circle")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.accentForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showsExamples) {
            DictationTranslationExamplesView(outputLanguage: editableOutputLanguage) { language in
                guard isEditable else { return }
                appliedLanguage = language
            }
        }
        .onChange(of: isEditable) { _, editable in
            if !editable { showsExamples = false }
        }
    }

    private var outputLanguageHelp: String {
        L("평소 받아쓰기 단축키로 말한 내용을 선택한 언어로 입력합니다. ‘말한 언어 유지’는 한국어와 영어 등 말한 언어를 유지합니다. 별도 번역 단축키의 출력 언어와는 다른 설정입니다.", "Your usual dictation shortcut types in the language you choose. Keep spoken language retains the languages you spoke, such as Korean and English. This is separate from the translation shortcut’s output language.")
        + "\n\n" + outputLanguage.detail
        + "\n\n" + L("번역에는 AI 문장 처리를 사용하며 요약·창작 등 받아쓰기 표현 설정을 적용하지 않습니다. 숫자·이름·조건·부정과 말투를 유지하도록 번역하지만, AI 모델에 따라 의미나 표현이 달라질 수 있습니다. 최근 결과에서 원문과 비교하거나 Jev로 직접 검토할 수 있습니다.", "Translation uses AI text processing and does not apply dictation wording settings such as summary or creative. It aims to preserve numbers, names, conditions, negation and tone, but meaning or wording may vary with the AI model. Compare with the transcript or request a Jev review from Latest result.")
        + "\n\n" + L("언어·예시에서 미리보기만 해서는 설정이 바뀌지 않습니다. 직접 적용하면 다음 받아쓰기 녹음부터 사용합니다.", "Browsing Language & examples does not change your setting. Applying a choice uses it from your next dictation recording.")
    }

    private var editableOutputLanguage: Binding<DictationOutputLanguage> {
        Binding(get: { outputLanguage }, set: { language in
            guard isEditable else { return }
            outputLanguage = language
        })
    }
}
