import SwiftUI
import OpenNoTypeCore

/// Language choices remain local until the explicit apply action commits the setting.
struct DictationTranslationExamplesView: View {
    @Binding var outputLanguage: DictationOutputLanguage
    var isEditable: Bool
    var onApply: (DictationOutputLanguage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguage: DictationOutputLanguage

    init(outputLanguage: Binding<DictationOutputLanguage>, isEditable: Bool = true, onApply: @escaping (DictationOutputLanguage) -> Void = { _ in }) {
        _outputLanguage = outputLanguage
        self.isEditable = isEditable
        self.onApply = onApply
        _selectedLanguage = State(initialValue: outputLanguage.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            HStack(alignment: .top) {
                AppPageHeader(L("출력 언어 예시", "Output language examples"), help: L("같은 발화의 고정 합성 예시입니다. AI 호출·녹음·전송 없이 표시하며 실제 결과는 발화와 모델에 따라 다릅니다. 숫자·조건·부정·말투의 보존을 확인하세요. 예시를 둘러봐도 설정은 바뀌지 않으며 직접 적용한 뒤 다음 녹음부터 사용합니다.", "Fixed synthetic examples of the same speech. No AI call, recording, or transmission occurs. Actual results depend on speech and model. Check numbers, conditions, negation, and tone. Browsing keeps your setting; applying uses it from the next recording."))
                Spacer()
                Button(L("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            SettingsRow(L("미리 볼 언어", "Preview language"), help: selectedLanguage.detail) {
                Picker(L("미리 볼 언어", "Preview language"), selection: $selectedLanguage) {
                    ForEach(DictationOutputLanguage.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 240)
            }
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    exampleBlock(L("말한 내용", "Spoken text"), text: DictationTranslationExamples.source)
                    exampleBlock(L("입력 결과 예시", "Example result"), text: DictationTranslationExamples.result(for: selectedLanguage), highlighted: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 8) {
                Text(L("현재: \(outputLanguage.title)", "Current: \(outputLanguage.title)")).font(AppTypography.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("취소", "Cancel")) { dismiss() }
                Button(L("선택 언어 적용", "Apply language")) {
                    guard isEditable else { return }
                    outputLanguage = selectedLanguage
                    onApply(selectedLanguage)
                    dismiss()
                }.buttonStyle(AppActionButtonStyle(primary: true))
                    .disabled(!isEditable || outputLanguage == selectedLanguage)
            }
        }
        .padding(AppLayout.pageInset)
        .frame(width: 720, height: 520)
        .controlSize(.regular)
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
            Text(text).font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppLayout.panelInset)
        .background(highlighted ? AppTheme.accent.opacity(0.08) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}
