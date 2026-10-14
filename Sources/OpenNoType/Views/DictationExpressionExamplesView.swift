import SwiftUI
import OpenNoTypeCore

/// Browsing changes only local selection; the explicit apply action commits a setting.
struct DictationExpressionExamplesView: View {
    @Binding var expression: DictationExpression
    var isEditable: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStyle: DictationExpressionStyle

    init(expression: Binding<DictationExpression>, initialStyle: DictationExpressionStyle, isEditable: Bool = true) {
        self.isEditable = isEditable
        _expression = expression
        _selectedStyle = State(initialValue: initialStyle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            HStack(alignment: .top) {
                AppPageHeader(L("표현 방식 예시", "Wording examples"), help: L("같은 발화의 고정 합성 예시입니다. AI 호출·녹음·전송 없이 표시하며 실제 결과는 발화와 강도에 따라 다릅니다. 새 사실·조건을 추가하는 기능이 아닙니다. 예시를 둘러봐도 설정은 바뀌지 않으며 직접 적용해야 다음 녹음부터 사용합니다.", "Fixed synthetic examples of the same speech. No AI call, recording, or transmission occurs. Actual results depend on speech and strength. This does not permit new facts or conditions. Browsing keeps your setting; explicitly apply it for the next recording."))
                Spacer()
                Button(L("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            SettingsRow(L("미리 볼 방식", "Preview direction"), help: selectedStyle.detail,
                        state: isEditable ? nil : L("현재 미적용 · 설정은 변경하지 않습니다", "Not applied · Settings remain unchanged")) {
                Picker(L("미리 볼 방식", "Preview direction"), selection: $selectedStyle) {
                    ForEach(DictationExpressionStyle.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 240)
            }
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    exampleBlock(L("말한 내용", "Spoken text"), text: DictationExpressionExamples.source)
                    exampleBlock(L("정리 결과 예시", "Example result"), text: DictationExpressionExamples.result(for: selectedStyle), highlighted: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 8) {
                Text(L("적용할 강도: \(proposedExpression.strength)", "Strength on apply: \(proposedExpression.strength)"))
                    .font(AppTypography.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button(L("취소", "Cancel")) { dismiss() }
                Button(L("선택 방식 적용", "Apply direction")) {
                    guard isEditable else { return }
                    expression = proposedExpression
                    dismiss()
                }.buttonStyle(.borderedProminent)
                    .disabled(!isEditable || expression == proposedExpression)
            }
        }
        .padding(AppLayout.pageInset)
        .frame(width: 720, height: 520)
        .controlSize(.regular)
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
            Text(text).font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppLayout.panelInset)
        .background(highlighted ? AppTheme.accent.opacity(0.08) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}
