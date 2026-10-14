import SwiftUI
import OpenNoTypeCore

struct DictationExpressionSettingsView: View {
    @Binding var expression: DictationExpression
    var outputLanguage: DictationOutputLanguage = .original
    var isFastDictation: Bool = false
    var isEditable: Bool = true
    @State private var exampleStyle: DictationExpressionStyle?

    var body: some View {
        Surface(L("받아쓰기 표현", "Dictation expression")) {
            if outputLanguage.isTranslation {
                Label(L("번역 출력 중 미적용 · 아래 선택은 유지됩니다.", "Not applied during translation · Your choices are kept."), systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else if isFastDictation {
                Label(L("빠른 로컬 받아쓰기 중 미적용 · 아래 선택은 유지됩니다.", "Not applied to quick on-device dictation · Your choices are kept."), systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 12) {
                OptionHelpLabel(L("표현 방식", "Wording direction"), help: expressionHelp)
                Spacer()
                Picker(L("표현 방식", "Wording direction"), selection: styleBinding) {
                    ForEach(DictationExpressionStyle.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
                .disabled(!controlsEnabled)
                Button(L("예시 비교…", "Compare examples…"), systemImage: "rectangle.on.rectangle") {
                    exampleStyle = expression.style
                }
                .disabled(!controlsEnabled)
                .help(L("설정을 바꾸기 전에 모든 표현 방식의 예시를 비교합니다.", "Compare all wording examples before changing your setting."))
            }
            Divider()
            HStack {
                OptionHelpLabel(L("AI 편집 강도", "AI editing strength"), help: strengthHelp)
                Spacer()
                Text(strengthDescription).monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 13))
            Slider(value: strengthBinding, in: 0...100, step: 5) {
                Text(L("AI 편집 강도", "AI editing strength"))
            } minimumValueLabel: {
                Text(L("현재 그대로", "As today"))
            } maximumValueLabel: {
                Text(L("적극적으로", "Substantial"))
            }
            .disabled(!controlsEnabled || expression.style == .faithful)
            .accessibilityValue(strengthDescription)
            if !outputLanguage.isTranslation, !isFastDictation, expression.style == .faithful {
                Text(L("현재 받아쓰기에서는 편집 강도를 사용하지 않습니다.", "Editing strength is not used with Current dictation."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Button(L("현재 방식으로 되돌리기", "Restore current dictation")) {
                guard controlsEnabled else { return }
                expression = .init()
            }
            .disabled(!controlsEnabled || expression == .init())
        }
        .sheet(item: $exampleStyle) { style in
            DictationExpressionExamplesView(expression: editableExpression, initialStyle: style)
        }
        .onChange(of: controlsEnabled) { _, enabled in
            if !enabled { exampleStyle = nil }
        }
    }

    private var controlsEnabled: Bool { isEditable && !outputLanguage.isTranslation && !isFastDictation }

    private var expressionHelp: String {
        L("현재 받아쓰기를 기본으로 유지합니다. 원하는 표현 방식을 선택하고 AI가 편집하는 정도를 조절하세요.", "Current dictation remains the default. Choose a wording direction and how much AI should edit.")
        + "\n\n" + expression.style.detail
        + "\n\n" + L("숫자·이름·조건·부정과 말한 의도를 지키며 표현만 바꿉니다. 요약은 줄이는 방향, 자세하게는 풀어 쓰는 방향입니다.", "Changes wording while retaining numbers, names, conditions, negation and intent. Summary makes it shorter; more detailed makes it fuller.")
        + "\n\n" + L("말한 언어를 유지하며 AI로 정리하는 받아쓰기에만 적용하고 다음 녹음부터 사용합니다. 번역·선택 문장 수정·빠른 로컬 받아쓰기에는 적용하지 않습니다. 적용되지 않는 동안에도 선택은 보관되며 AI 정리 받아쓰기로 돌아오면 다시 적용됩니다.", "Applies to AI-cleaned dictation that keeps the spoken language, starting with your next recording. Translation, selected-text editing and quick on-device dictation do not apply these settings. Your choices are kept while inactive and apply again when you return to AI-cleaned dictation.")
        + "\n\n" + L("예시 비교는 고정 예시를 보여 주며 직접 적용하기 전에는 설정을 바꾸지 않습니다.", "Compare examples shows fixed examples and does not change settings until you explicitly apply a choice.")
    }

    private var strengthHelp: String {
        L("선택한 표현 방향 안에서 AI가 문장을 바꾸는 정도입니다. 음성 인식 정확도나 모델을 바꾸는 값은 아닙니다. 강도가 높아도 숫자·이름·조건·부정과 말한 의도를 유지하는 원칙은 같습니다.", "Controls how much AI changes wording within the chosen direction. It does not change speech recognition accuracy or the model. Numbers, names, conditions, negation and intent must still be retained at higher strength.")
        + "\n\n" + L("강도가 0이거나 ‘현재 받아쓰기’이면 기존 문장 정리 방식 그대로 처리합니다. AI 문장 정리 자체를 끄는 설정은 아닙니다. 다른 표현을 처음 선택하고 강도가 0이면 40으로 시작하며, 직접 조절할 수 있습니다.", "At zero strength or Current dictation, text processing works exactly as before. This does not turn off AI text cleanup. Choosing another direction at zero strength starts at 40, which you can adjust.")
    }

    private var editableExpression: Binding<DictationExpression> {
        Binding(get: { expression }, set: { value in
            guard controlsEnabled else { return }
            expression = value
        })
    }

    private var styleBinding: Binding<DictationExpressionStyle> {
        Binding(get: { expression.style }, set: { style in
            guard controlsEnabled else { return }
            expression.style = style
            if style == .faithful { expression.strength = 0 }
            else if expression.strength == 0 { expression.strength = 40 }
        })
    }

    private var strengthBinding: Binding<Double> {
        Binding(get: { Double(expression.strength) }, set: { value in
            guard controlsEnabled else { return }
            expression.strength = Int(value.rounded())
        })
    }

    private var strengthDescription: String {
        guard expression.isActive else { return L("현재 그대로 · 0", "As today · 0") }
        let level = expression.strength <= 33 ? L("가볍게", "Light")
            : expression.strength <= 66 ? L("적당히", "Balanced") : L("적극적으로", "Substantial")
        return "\(level) · \(expression.strength)"
    }

}
