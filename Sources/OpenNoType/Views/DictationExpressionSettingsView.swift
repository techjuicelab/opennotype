import SwiftUI
import OpenNoTypeCore

struct DictationExpressionSettingsView: View {
    @Binding var expression: DictationExpression
    @State private var exampleStyle: DictationExpressionStyle?

    var body: some View {
        Surface(L("받아쓰기 표현", "Dictation expression")) {
            Text(L("현재 받아쓰기를 기본으로 유지합니다. 원하는 표현 방식을 선택하고 AI가 편집하는 정도를 조절하세요.", "Current dictation remains the default. Choose a wording direction and how much AI should edit."))
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Picker(L("표현 방식", "Wording direction"), selection: styleBinding) {
                    ForEach(DictationExpressionStyle.allCases) { Text($0.title).tag($0) }
                }
                Button(L("예시 비교…", "Compare examples…"), systemImage: "rectangle.on.rectangle") {
                    exampleStyle = expression.style
                }
                .help(L("설정을 바꾸기 전에 모든 표현 방식의 예시를 비교합니다.", "Compare all wording examples before changing your setting."))
            }
            Text(expression.style.detail).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Text(L("AI 편집 강도", "AI editing strength"))
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
            .disabled(expression.style == .faithful)
            .accessibilityValue(strengthDescription)
            Text(expression.isActive
                 ? L("숫자·이름·조건·부정과 말한 의도를 지키며 표현만 바꿉니다. 요약은 줄이는 방향, 자세하게는 풀어 쓰는 방향입니다.", "Changes wording while retaining numbers, names, conditions, negation and intent. Summary makes it shorter; more detailed makes it fuller.")
                 : L("강도가 0이거나 ‘현재 받아쓰기’이면 기존 문장 정리 방식 그대로 처리합니다.", "At zero strength or Current dictation, text processing works exactly as before."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Text(L("받아쓰기에만 적용하며, 변경한 설정은 다음 녹음부터 사용합니다. 번역과 선택 문장 수정에는 적용하지 않습니다.", "Applies only to dictation, starting with your next recording. Translation and selected-text editing are unchanged."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Button(L("현재 방식으로 되돌리기", "Restore current dictation")) { expression = .init() }
                .disabled(expression == .init())
        }
        .sheet(item: $exampleStyle) { style in
            DictationExpressionExamplesView(expression: $expression, initialStyle: style)
        }
    }

    private var styleBinding: Binding<DictationExpressionStyle> {
        Binding(get: { expression.style }, set: { style in
            expression.style = style
            if style == .faithful { expression.strength = 0 }
            else if expression.strength == 0 { expression.strength = 40 }
        })
    }

    private var strengthBinding: Binding<Double> {
        Binding(get: { Double(expression.strength) }, set: { expression.strength = Int($0.rounded()) })
    }

    private var strengthDescription: String {
        guard expression.isActive else { return L("현재 그대로 · 0", "As today · 0") }
        let level = expression.strength <= 33 ? L("가볍게", "Light")
            : expression.strength <= 66 ? L("적당히", "Balanced") : L("적극적으로", "Substantial")
        return "\(level) · \(expression.strength)"
    }

}
