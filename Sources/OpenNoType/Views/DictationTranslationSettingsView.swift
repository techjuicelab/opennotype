import SwiftUI
import OpenNoTypeCore

struct DictationTranslationSettingsView: View {
    @Binding var outputLanguage: DictationOutputLanguage
    var isEditable: Bool = true
    var embedded = false
    @State private var showsExamples = false
    @State private var appliedLanguage: DictationOutputLanguage?

    var body: some View {
        Group {
            if embedded { optionRow }
            else { SettingsPanel { optionRow } }
        }
        .sheet(isPresented: $showsExamples) {
            DictationTranslationExamplesView(outputLanguage: editableOutputLanguage, isEditable: isEditable) { language in
                guard isEditable else { return }
                appliedLanguage = language
            }
        }
    }

    private var optionRow: some View {
        SettingsRow(L("출력 언어", "Output language"), help: outputLanguageHelp,
                    state: appliedLanguage.map { L("\($0.title) 적용됨 · 다음 녹음부터", "\($0.title) applied · Next recording") }) {
            Picker(L("받아쓰기 출력 언어", "Dictation output language"), selection: editableOutputLanguage) {
                ForEach(DictationOutputLanguage.allCases) { Text($0.title).tag($0) }
            }.labelsHidden().frame(width: 168).disabled(!isEditable)
            Button(L("예시", "Examples")) { showsExamples = true }
                .frame(width: 64)
                .accessibilityLabel(L("출력 언어 예시 보기", "View output language examples"))
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
