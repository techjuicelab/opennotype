import OpenNoTypeCore
import SwiftUI

struct TranslationRefinementResultView: View {
    let refinement: TranslationRefinementPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if refinement.isProcessing { ProgressView().controlSize(.small) }
                Text(refinement.status)
                    .font(.system(size: 12)).lineSpacing(3).textSelection(.enabled)
                    .foregroundStyle(refinement.held ? AppTheme.warm : Color.secondary)
            }
            DisclosureGroup(L("번역 다듬기 과정", "Translation refinement details")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("번역 초안", "Draft translation"))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text(refinement.draft).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                    if let output = refinement.output {
                        Divider()
                        Text(L("다듬은 번역안", "Refined translation candidate"))
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        Text(output).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                        if output == refinement.draft {
                            Text(L("초안과 같은 결과입니다.", "The result is the same as the draft."))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Text(L("다듬기 완료는 Jev 검토 완료나 정확성 보장을 뜻하지 않습니다. 검토와 입력 여부는 각 상태 안내를 확인해 주세요. 초안과 처리 과정은 이번 결과에서만 표시하며 별도로 보관하지 않습니다.", "Completed refinement does not mean Jev review is complete or accuracy is guaranteed. Check the separate review and typing status. The draft and processing details are shown for this result only and are not saved separately."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(.top, 8)
            }.font(.system(size: 12))
        }
    }
}
