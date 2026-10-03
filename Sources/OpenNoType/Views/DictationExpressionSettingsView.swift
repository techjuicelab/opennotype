import SwiftUI
import OpenNoTypeCore

struct DictationExpressionSettingsView: View {
    @Binding var expression: DictationExpression

    var body: some View {
        Surface(L("받아쓰기 표현", "Dictation expression")) {
            Text(L("현재 받아쓰기를 기본으로 유지합니다. 원하는 표현 방식을 선택하고 AI가 편집하는 정도를 조절하세요.", "Current dictation remains the default. Choose a wording direction and how much AI should edit."))
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            Picker(L("표현 방식", "Wording direction"), selection: styleBinding) {
                ForEach(DictationExpressionStyle.allCases) { Text($0.title).tag($0) }
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
            DisclosureGroup(L("표현 방향 예시 보기", "See an example of this wording direction")) {
                VStack(alignment: .leading, spacing: 10) {
                    exampleText(L("말한 내용 · 합성 예시", "Spoken text · Synthetic example"), text: L("OpenNoType으로 음, 녹음한 말을 정리하고 싶어요. 정리하고 싶은데요. 그런데 반복되는 말이 있어서 읽기 어렵거든요. 설정을 내일 오후 3시까지 확인해 주세요.", "I want to, um, clean up my recorded speech with OpenNoType. I want to clean it up. But the repeated words make it hard to read. Please check the settings by 3 PM tomorrow."))
                    exampleText(L("\(previewStyle.title) 방향 예시", "\(previewStyle.title) example"), text: previewText)
                    Text(L("방향을 비교하기 위해 미리 작성한 고정 예시입니다. AI 호출이 없으며, 현재 강도나 실제 녹음의 결과를 보장하지 않습니다.", "This fixed, prewritten example illustrates the wording direction. No AI is called; it does not promise the output at your current strength or for an actual recording."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(.top, 10)
            }.font(.system(size: 12))
            Button(L("현재 방식으로 되돌리기", "Restore current dictation")) { expression = .init() }
                .disabled(expression == .init())
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

    private var previewStyle: DictationExpressionStyle { expression.isActive ? expression.style : .faithful }

    private var previewText: String {
        switch previewStyle {
        case .faithful:
            L("OpenNoType으로 녹음한 말을 정리하고 싶어요. 그런데 반복되는 말이 있어서 읽기 어렵거든요. 설정을 내일 오후 3시까지 확인해 주세요.", "I want to clean up my recorded speech with OpenNoType. The repeated words make it hard to read. Please check the settings by 3 PM tomorrow.")
        case .concise:
            L("반복되는 말 때문에 읽기 어려운 녹음을 OpenNoType으로 정리하고 싶어요. 설정을 내일 오후 3시까지 확인해 주세요.", "I want to use OpenNoType to clean up recordings that are hard to read because of repeated words. Please check the settings by 3 PM tomorrow.")
        case .summary:
            L("반복 때문에 읽기 어려운 녹음을 OpenNoType으로 정리하고 싶어요. 내일 오후 3시까지 설정을 확인해 주세요.", "I want OpenNoType to clean up recordings made hard to read by repetition. Please check its settings by 3 PM tomorrow.")
        case .clear:
            L("녹음한 말은 반복 때문에 읽기 어려워요. 그래서 OpenNoType으로 정리하고 싶어요. 설정을 내일 오후 3시까지 확인해 주세요.", "Repetition makes my recorded speech hard to read, so I want to clean it up with OpenNoType. Please check the settings by 3 PM tomorrow.")
        case .expanded:
            L("녹음한 말에는 반복되는 표현이 있어 읽기가 어려워요. 이 내용을 읽기 편하게 정리하려고 OpenNoType을 사용하고 싶어요. 설정 확인은 내일 오후 3시까지 해 주세요.", "My recorded speech contains repeated words, which makes it difficult to read. I want to use OpenNoType to organize that speech so it is easier to read. Please finish checking the settings by 3 PM tomorrow.")
        case .creative:
            L("반복되는 말로 읽기 어려운 녹음을 OpenNoType으로 다듬고 싶어요. 내일 오후 3시까지 설정을 확인해 주세요.", "I want to polish my recorded speech with OpenNoType so its repeated words are easier to read. Please check the settings by 3 PM tomorrow.")
        }
    }

    private func exampleText(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12)).lineSpacing(4).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
