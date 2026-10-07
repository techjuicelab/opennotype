import AppKit
import OpenNoTypeCore
import SwiftUI

struct PromptCompositionResultView: View {
    let composition: PromptCompositionPresentation
    @State private var copied = false

    var body: some View {
        Surface(L("만든 프롬프트", "Your prompt")) {
            HStack(alignment: .top, spacing: 10) {
                if composition.isProcessing { ProgressView().controlSize(.small) }
                else {
                    Image(systemName: composition.held ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(composition.held ? AppTheme.warm : AppTheme.accentForeground)
                }
                Text(composition.status).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let output = composition.output, !output.isEmpty, !composition.held, !composition.isProcessing {
                Text(output).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                Button(copied ? L("복사됨", "Copied") : L("프롬프트 복사", "Copy prompt"), systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(output, forType: .string)
                    copied = true
                }.buttonStyle(.borderedProminent)
            }
            if !composition.transcript.isEmpty {
                DisclosureGroup(L("말한 내용 보기", "View transcript")) {
                    Text(composition.transcript).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled).padding(.top, 8)
                }.font(.system(size: 12))
            }
            if let draft = composition.draft, !draft.isEmpty, draft != composition.output {
                DisclosureGroup(L("중간 초안 보기", "View intermediate draft")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("중간 초안은 최종 검토를 통과한 프롬프트가 아닙니다.", "This intermediate draft has not passed the final review."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(draft).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                    }.padding(.top, 8)
                }.font(.system(size: 12))
            }
        }
        .onChange(of: composition.output) { _, _ in copied = false }
    }
}
