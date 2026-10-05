import SwiftUI
import OpenNoTypeCore

/// Language choices remain local until the explicit apply action commits the setting.
struct DictationTranslationExamplesView: View {
    @Binding var outputLanguage: DictationOutputLanguage
    var onApply: (DictationOutputLanguage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguage: DictationOutputLanguage

    init(outputLanguage: Binding<DictationOutputLanguage>, onApply: @escaping (DictationOutputLanguage) -> Void = { _ in }) {
        _outputLanguage = outputLanguage
        self.onApply = onApply
        _selectedLanguage = State(initialValue: outputLanguage.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("말한 내용을 자연스러운 다른 언어로", "Your speech in natural wording"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(L("닫기", "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Text(L("같은 한국어 발화를 각 언어로 어떻게 전달하는지 확인하세요. 언어를 둘러봐도 설정은 바뀌지 않습니다.", "Compare how the same Korean speech comes across in each language. Browsing does not change your setting."))
                .font(.callout).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("미리 볼 출력 언어", "Preview an output language"))
                        .font(.caption).foregroundStyle(.secondary).padding(.bottom, 4)
                    ForEach(DictationOutputLanguage.allCases) { language in
                        languageButton(language)
                    }
                    Spacer(minLength: 0)
                }.frame(width: 178, alignment: .leading)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        exampleBlock(L("말한 내용 · 한국어", "Spoken text · Korean"), text: DictationTranslationExamples.source)
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedLanguage.title).font(.headline)
                            Text(selectedLanguage.detail).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        exampleBlock(L("입력 결과 예시", "Example text to type"), text: DictationTranslationExamples.result(for: selectedLanguage), highlighted: true)
                        Text(L("완곡한 요청과 ‘오늘 안’, 12개 항목, 승인 전 공유 금지를 그대로 전달합니다. 문장 순서와 표현은 각 언어에 맞게 다듬습니다.", "The polite request, today's deadline, all 12 items, and the restriction on sharing before approval are preserved. Wording and sentence structure fit each language."))
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("방향을 보여 주는 고정 합성 예시입니다. AI 호출·녹음·전송 없이 표시하며, 실제 결과는 발화와 선택한 AI 모델에 따라 달라집니다.", "Fixed synthetic examples illustrate the approach. No AI call, recording, or transmission occurs. Actual results depend on your speech and chosen AI model."))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("적용할 출력 언어: \(selectedLanguage.title)", "Output language on apply: \(selectedLanguage.title)"))
                        .font(.callout)
                    Text(L("다음 받아쓰기 녹음부터 적용됩니다.", "Applies to your next dictation recording."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("취소", "Cancel")) { dismiss() }
                Button(L("\(selectedLanguage.title) 적용", "Use \(selectedLanguage.title)")) {
                    outputLanguage = selectedLanguage
                    onApply(selectedLanguage)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(outputLanguage == selectedLanguage)
            }
        }
        .padding(24)
        .frame(width: 760, height: 610)
    }

    private func languageButton(_ language: DictationOutputLanguage) -> some View {
        Button {
            selectedLanguage = language
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedLanguage == language ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedLanguage == language ? AppTheme.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.title).font(.system(size: 13, weight: .medium))
                    if outputLanguage == language {
                        Text(L("현재 설정", "Current setting"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedLanguage == language ? AppTheme.accent.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("\(language.title) 예시 미리 보기", "Preview \(language.title) example"))
        .accessibilityValue(outputLanguage == language ? L("현재 설정", "Current setting") : "")
        .accessibilityAddTraits(selectedLanguage == language ? [.isSelected] : [])
    }

    private func exampleBlock(_ title: String, text: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Text(text).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(highlighted ? AppTheme.accent.opacity(0.08) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}
