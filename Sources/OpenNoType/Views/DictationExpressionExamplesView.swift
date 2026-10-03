import SwiftUI
import OpenNoTypeCore

/// Browsing changes only local selection; the explicit apply action commits a setting.
struct DictationExpressionExamplesView: View {
    @Binding var expression: DictationExpression
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStyle: DictationExpressionStyle

    init(expression: Binding<DictationExpression>, initialStyle: DictationExpressionStyle) {
        _expression = expression
        _selectedStyle = State(initialValue: initialStyle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("표현 방식 예시 비교", "Compare wording examples"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(L("닫기", "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Text(L("같은 발화를 어떻게 정리하는지 비교해 보세요. 예시를 둘러봐도 설정은 바뀌지 않습니다.", "Compare how each direction handles the same speech. Browsing does not change your setting."))
                .font(.callout).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("미리 볼 방식", "Preview a direction"))
                        .font(.caption).foregroundStyle(.secondary).padding(.bottom, 4)
                    ForEach(DictationExpressionStyle.allCases) { style in
                        styleButton(style)
                    }
                    Spacer(minLength: 0)
                }.frame(width: 178, alignment: .leading)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        exampleBlock(L("말한 내용", "Spoken text"), text: DictationExpressionExamples.source)
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedStyle.title).font(.headline)
                            Text(selectedStyle.detail).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        exampleBlock(L("정리 결과 예시", "Example result"), text: DictationExpressionExamples.result(for: selectedStyle), highlighted: true)
                        Text(L("방향을 보여 주는 고정 합성 예시입니다. AI 호출·녹음·전송 없이 표시하며, 실제 결과는 발화와 편집 강도에 따라 달라집니다.", "Fixed synthetic examples illustrate each direction. No AI call, recording or transmission occurs. Actual results depend on your speech and editing strength."))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("적용할 편집 강도: \(proposedExpression.strength)", "Editing strength on apply: \(proposedExpression.strength)"))
                        .font(.callout).monospacedDigit()
                    Text(L("다음 받아쓰기부터 적용됩니다.", "Applies to your next dictation."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("\(selectedStyle.title) 적용", "Use \(selectedStyle.title)")) {
                    expression = proposedExpression
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(expression == proposedExpression)
            }
        }
        .padding(24)
        .frame(width: 760, height: 610)
    }

    private var proposedExpression: DictationExpression {
        .init(style: selectedStyle,
              strength: selectedStyle == .faithful ? 0 : expression.strength == 0 ? 40 : expression.strength)
    }

    private func styleButton(_ style: DictationExpressionStyle) -> some View {
        Button {
            selectedStyle = style
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedStyle == style ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedStyle == style ? AppTheme.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.title).font(.system(size: 13, weight: .medium))
                    if expression.style == style {
                        Text(L("현재 설정", "Current setting"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedStyle == style ? AppTheme.accent.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("\(style.title) 예시 미리 보기", "Preview \(style.title) example"))
        .accessibilityValue(expression.style == style ? L("현재 설정", "Current setting") : "")
        .accessibilityAddTraits(selectedStyle == style ? [.isSelected] : [])
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
