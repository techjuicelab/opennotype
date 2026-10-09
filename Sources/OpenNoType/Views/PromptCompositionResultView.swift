import AppKit
import OpenNoTypeCore
import SwiftUI

struct PromptCompositionResultView: View {
    let composition: PromptCompositionPresentation
    let isBusy: Bool
    let regenerationSettings: String?
    let onRegenerate: ((UUID, String, String) -> Void)?
    @State private var copied = false
    @State private var transcriptExpanded: Bool
    @State private var recognizedTranscriptExpanded: Bool
    @State private var draftExpanded: Bool
    @State private var candidateExpanded: Bool
    @State private var sourceEditorExpanded = false
    @State private var reviewExpanded = false
    @State private var editedTranscript: String

    init(composition: PromptCompositionPresentation, isBusy: Bool = false,
         regenerationSettings: String? = nil, onRegenerate: ((UUID, String, String) -> Void)? = nil) {
        self.composition = composition
        self.isBusy = isBusy
        self.regenerationSettings = regenerationSettings
        self.onRegenerate = onRegenerate
        _transcriptExpanded = State(initialValue: composition.held)
        _recognizedTranscriptExpanded = State(initialValue: composition.held)
        _draftExpanded = State(initialValue: composition.held)
        _candidateExpanded = State(initialValue: composition.held)
        _editedTranscript = State(initialValue: composition.transcript)
    }

    var body: some View {
        Surface(composition.title) {
            if isBusy && !composition.isProcessing {
                Text(L("새 작업을 진행 중입니다. 아래는 이전 프롬프트입니다.", "A new task is in progress. The prompt below is from the previous task."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 10) {
                if composition.isProcessing { ProgressView().controlSize(.small) }
                else {
                    Image(systemName: composition.held ? "exclamationmark.circle" : composition.needsReview ? "info.circle" : "doc.text")
                        .foregroundStyle(composition.held || composition.needsReview ? AppTheme.warm : AppTheme.accentForeground)
                }
                Text(composition.status).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let explanation = composition.interruptionDescription {
                Text(explanation).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let output = composition.output, composition.canCopyOutput {
                Text(output).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                Button(copied ? L("복사됨", "Copied") : L("프롬프트 복사", "Copy prompt"), systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(output, forType: .string)
                }.buttonStyle(.borderedProminent)
            }
            if composition.held {
                Text(composition.inspectionDescription)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text(L("이 화면의 내용은 새 녹음을 처리하거나 앱을 종료하면 사라집니다. 보관된 실패 녹음은 ‘다시 처리’에서 확인하세요.", "This screen's content clears when a new recording is processed or the app quits. Saved failed recordings are available in Recovery."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let original = composition.originalTranscript, !original.isEmpty {
                DisclosureGroup(L("처음 인식된 원문 보기", "View original recognition"), isExpanded: $recognizedTranscriptExpanded) {
                    Text(original).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled).padding(.top, 8)
                }.font(.system(size: 12))
            }
            if !composition.transcript.isEmpty {
                DisclosureGroup(composition.transcriptTitle, isExpanded: $transcriptExpanded) {
                    Text(composition.transcript).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled).padding(.top, 8)
                }.font(.system(size: 12))
            }
            if let onRegenerate { sourceEditor(onRegenerate) }
            if composition.held, let candidate = composition.finalCandidate, !candidate.isEmpty {
                DisclosureGroup(L("최종 검토 후보 보기", "View final review candidate"), isExpanded: $candidateExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(candidate == composition.draft
                             ? L("초안을 그대로 최종 검토했습니다. 이 후보는 최종 검토를 통과한 결과가 아닙니다.", "The draft itself was reviewed as the final candidate. This candidate is not an approved result.")
                             : L("최종 검토에 사용한 후보이며, 검토를 통과한 프롬프트가 아닙니다.", "This is the candidate used for the final review; it is not a prompt that passed review."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(candidate).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                    }.padding(.top, 8)
                }.font(.system(size: 12))
            }
            if let draft = composition.draft, !draft.isEmpty, draft != composition.output,
               !composition.held || draft != composition.finalCandidate {
                DisclosureGroup(L("중간 초안 보기", "View intermediate draft"), isExpanded: $draftExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("중간 초안은 최종 검토를 통과한 프롬프트가 아닙니다.", "This intermediate draft has not passed the final review."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(draft).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                    }.padding(.top, 8)
                }.font(.system(size: 12))
            }
            if let review = composition.finalReview ?? composition.draftReview {
                DisclosureGroup(L("품질 검토 참고", "Quality review reference"), isExpanded: $reviewExpanded) {
                    reviewDetails(review, isFinal: composition.finalReview != nil).padding(.top, 8)
                }.font(.system(size: 12))
            }
        }
        .onChange(of: composition.id) { _, _ in
            copied = false
            editedTranscript = composition.transcript
            sourceEditorExpanded = false
            reviewExpanded = false
            transcriptExpanded = composition.held
            recognizedTranscriptExpanded = composition.held
            draftExpanded = composition.held
            candidateExpanded = composition.held
        }
        .onChange(of: composition.output) { _, _ in copied = false }
        .onChange(of: composition.held) { _, held in
            if held {
                transcriptExpanded = true; recognizedTranscriptExpanded = true
                draftExpanded = true; candidateExpanded = true
            }
        }
    }

    private func sourceEditor(_ regenerate: @escaping (UUID, String, String) -> Void) -> some View {
        DisclosureGroup(L("원문 수정·다시 만들기", "Edit source and try again"), isExpanded: $sourceEditorExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("잘못 인식된 부분을 직접 고치거나 같은 원문으로 다시 만들 수 있어요.", "Correct recognition mistakes or create a prompt again from the same source."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(L("다시 만든 결과는 미리보기로 표시하며 자동 입력하지 않습니다. 필요한 결과를 복사해 사용하세요.", "Regenerated results appear as previews and are not typed automatically. Copy the result you want to use."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                TextEditor(text: $editedTranscript)
                    .font(.system(size: 13)).frame(minHeight: 100, maxHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(6).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.12), lineWidth: 1))
                    .accessibilityLabel(L("다시 만들 원문", "Source for the new prompt"))
                    .accessibilityIdentifier("prompt-source-editor")
                    .disabled(isBusy || composition.isProcessing)
                if let settings = regenerationSettings {
                    Text(settings).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(L("버튼을 누르면 이 원문으로 생성 1~2회·Jev 검토 2회를 실행하며 추가 API 비용이 생길 수 있어요. 필요할 때만 한 번 다듬고, 오류가 나면 해당 단계에서 멈춥니다. 음성을 다시 전송하지 않습니다.", "The button runs one or two generations and two Jev reviews from this source, which may incur additional API costs. Polishing runs once only when needed, and an error stops the process at that stage. Audio is not sent again."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(L("이 화면의 원문과 편집 내용은 다음 프롬프트 처리나 앱 종료 시 사라집니다. 다시 만들기는 저장된 기록의 원문이나 보관된 실패 녹음을 덮어쓰지 않습니다.", "The source and edits shown here clear when the next prompt is processed or the app quits. Regeneration does not overwrite existing history source text or saved failed recordings."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let failure = PromptCompositionPresentation.sourceValidationFailure(editedTranscript) {
                    Text(failure.localizedDescription).font(.system(size: 11)).foregroundStyle(AppTheme.warm)
                }
                Button(L("이 원문으로 다시 만들기", "Create prompt from this source"), systemImage: "arrow.clockwise") {
                    guard !isBusy, composition.canRegenerate(with: editedTranscript) else { return }
                    regenerate(composition.id, composition.transcript, editedTranscript)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("prompt-regenerate")
                .disabled(isBusy || !composition.canRegenerate(with: editedTranscript))
            }.padding(.top, 8)
        }.font(.system(size: 12))
    }

    private func reviewDetails(_ review: PromptCompositionReviewResult, isFinal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isFinal ? L("최종 검토 항목", "Final review") : L("초안 검토 항목", "Draft review"))
                .font(.system(size: 12, weight: .medium))
            ForEach(PromptCompositionIssue.allCases, id: \.self) { issue in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(issueTitle(issue)).font(.system(size: 12, weight: .medium))
                        Spacer()
                        if let assessment = review.assessments[issue] {
                            Text(assessment.accepted ? L("통과", "Passed") : L("확인 필요", "Needs attention"))
                                .foregroundStyle(assessment.accepted ? AppTheme.accentForeground : AppTheme.warm)
                        } else {
                            Text(L("검토 정보 없음", "Review unavailable")).foregroundStyle(.secondary)
                        }
                    }.font(.system(size: 11))
                    if let assessment = review.assessments[issue] {
                        Text(assessmentDetail(assessment))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text(L("검토 신호와 확신은 모델의 참고 판단이며 정확도를 뜻하지 않습니다.", "Review signals and confidence are advisory model judgments, not accuracy."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func issueTitle(_ issue: PromptCompositionIssue) -> String {
        switch issue {
        case .intent: L("의도 보존", "Intent preservation")
        case .unsupportedAdditions: L("근거 없는 추가", "Unsupported additions")
        case .omissions: L("중요 내용 누락", "Essential omissions")
        case .harnessBoundary: L("기존 지침 존중", "Existing instruction boundaries")
        }
    }

    private func assessmentDetail(_ assessment: PromptCompositionReviewAssessment) -> String {
        guard assessment.isValid else { return L("검토 응답 형식을 확인하지 못했습니다.", "The review response could not be verified.") }
        let choice: String
        switch assessment.choice {
        case .pass: choice = L("통과", "Pass")
        case .fail: choice = L("문제 있음", "Fail")
        case .uncertain: choice = L("판단 보류", "Uncertain")
        }
        let signal = PromptCompositionReviewFormatting.percentage(assessment.probabilities[.pass] ?? 0)
        let confidence = PromptCompositionReviewFormatting.percentage(assessment.confidence)
        let criteria = assessment.choice == .pass && !assessment.accepted
            ? L(" · 참고 기준 미달", " · Below review criteria") : ""
        return L("모델 선택: \(choice) · 통과 신호 \(signal) · 모델 확신 \(confidence)\(criteria)",
                 "Model choice: \(choice) · Pass signal \(signal) · Model confidence \(confidence)\(criteria)")
    }

}

struct PromptCompositionReviewSummaryView: View {
    let summary: PromptCompositionReviewSummary?

    var body: some View {
        switch summary?.deliveryDisposition {
        case .needsReview:
            Label(PromptCompositionPresentation.qualityReviewNotice, systemImage: "info.circle")
                .font(.system(size: 11)).foregroundStyle(AppTheme.warm)
                .fixedSize(horizontal: false, vertical: true)
        case .blocked:
            Label(L("기존 지침 관련 검토에서 제공을 보류한 결과입니다.", "This result was held by the instruction boundary review."), systemImage: "exclamationmark.circle")
                .font(.system(size: 11)).foregroundStyle(AppTheme.warm)
        case .ready:
            EmptyView()
        case nil:
            Text(L("당시 품질 검토 정보는 보관되지 않았습니다.", "Quality review details were not saved for this result."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

enum PromptCompositionReviewFormatting {
    static func percentage(_ value: Double) -> String {
        guard value.isFinite, (0...1).contains(value) else { return "—" }
        if value < 0.001 { return "0%" }
        guard let decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else { return "—" }
        // A below-threshold value must never round up to the delivery threshold.
        // Decimal conversion also keeps values such as 0.29 from displaying as 28.9%.
        var percentage = decimal * 100
        var displayed = Decimal()
        NSDecimalRound(&displayed, &percentage, 1, .down)
        return NSDecimalNumber(decimal: displayed).stringValue + "%"
    }
}
