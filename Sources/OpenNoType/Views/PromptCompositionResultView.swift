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
                    .font(AppTypography.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                if composition.isProcessing { ProgressView().controlSize(.small) }
                else {
                    Image(systemName: composition.held ? "exclamationmark.circle" : composition.needsReview ? "info.circle" : "doc.text")
                        .foregroundStyle(composition.held || composition.needsReview ? AppTheme.warm : AppTheme.accentForeground)
                }
                Text(composition.status).font(AppTypography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if composition.isProcessing {
                HStack(spacing: 8) {
                    Text(progressTitle).font(AppTypography.body)
                    Spacer()
                    Text(L("생성 1~2회·검토 2회 · 추가 비용", "1–2 generations · 2 reviews · Additional cost"))
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
            }
            if let explanation = composition.interruptionDescription {
                Text(explanation).font(AppTypography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let output = composition.output, composition.canCopyOutput {
                Text(output).font(AppTypography.body).lineSpacing(5).textSelection(.enabled)
                Button(copied ? L("복사됨", "Copied") : L("프롬프트 복사", "Copy prompt"), systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(output, forType: .string)
                }.buttonStyle(AppActionButtonStyle(primary: true))
            }
            if composition.held {
                Text(composition.inspectionDescription)
                    .font(AppTypography.caption).foregroundStyle(.secondary)
                OptionHelpLabel(L("보류된 내용의 보관", "Held content retention"), help: L("이 화면의 내용은 새 녹음을 처리하거나 앱을 종료하면 사라집니다. 실제 보관된 실패 녹음만 ‘녹음 복구’에서 확인할 수 있습니다.", "This screen clears when a new recording is processed or the app quits. Only failed recordings that were successfully saved are available in Recording Recovery."))
            }
            if let original = composition.originalTranscript, !original.isEmpty {
                DisclosureGroup(L("처음 인식된 원문 보기", "View original recognition"), isExpanded: $recognizedTranscriptExpanded) {
                    Text(original).font(AppTypography.body).lineSpacing(4).textSelection(.enabled).padding(.top, 8)
                }.font(AppTypography.caption)
            }
            if !composition.transcript.isEmpty {
                DisclosureGroup(composition.transcriptTitle, isExpanded: $transcriptExpanded) {
                    Text(composition.transcript).font(AppTypography.body).lineSpacing(4).textSelection(.enabled).padding(.top, 8)
                }.font(AppTypography.caption)
            }
            if let onRegenerate { sourceEditor(onRegenerate) }
            if composition.held, let candidate = composition.finalCandidate, !candidate.isEmpty {
                DisclosureGroup(L("최종 검토 후보 보기", "View final review candidate"), isExpanded: $candidateExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(candidate == composition.draft
                             ? L("초안을 그대로 최종 검토했습니다. 이 후보는 최종 검토를 통과한 결과가 아닙니다.", "The draft itself was reviewed as the final candidate. This candidate is not an approved result.")
                             : L("최종 검토에 사용한 후보이며, 검토를 통과한 프롬프트가 아닙니다.", "This is the candidate used for the final review; it is not a prompt that passed review."))
                            .font(AppTypography.caption).foregroundStyle(.secondary)
                        Text(candidate).font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
                    }.padding(.top, 8)
                }.font(AppTypography.caption)
            }
            if let draft = composition.draft, !draft.isEmpty, draft != composition.output,
               !composition.held || draft != composition.finalCandidate {
                DisclosureGroup(L("중간 초안 보기", "View intermediate draft"), isExpanded: $draftExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("중간 초안은 최종 검토를 통과한 프롬프트가 아닙니다.", "This intermediate draft has not passed the final review."))
                            .font(AppTypography.caption).foregroundStyle(.secondary)
                        Text(draft).font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
                    }.padding(.top, 8)
                }.font(AppTypography.caption)
            }
            if let review = composition.finalReview ?? composition.draftReview {
                DisclosureGroup(L("품질 검토 참고", "Quality review reference"), isExpanded: $reviewExpanded) {
                    reviewDetails(review, isFinal: composition.finalReview != nil).padding(.top, 8)
                }.font(AppTypography.caption)
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

    private var progressTitle: String {
        switch composition.stage {
        case .drafting: L("초안 만들기", "Drafting")
        case .reviewingDraft: L("초안 검토", "Reviewing draft")
        case .polishing: L("한 번 다듬기", "Polishing once")
        case .reviewingFinal: L("최종 검토", "Final review")
        }
    }

    private func sourceEditor(_ regenerate: @escaping (UUID, String, String) -> Void) -> some View {
        HStack(spacing: 4) {
            Button(L("원문 수정·다시 만들기…", "Edit source and try again…"), systemImage: "square.and.pencil") {
                sourceEditorExpanded = true
            }
            .disabled(isBusy || composition.isProcessing)
            OptionHelp(title: L("원문 수정·다시 만들기", "Edit source and try again"), message: regenerationHelp)
        }
        .sheet(isPresented: $sourceEditorExpanded) {
            VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
                AppPageHeader(L("원문 수정·다시 만들기", "Edit source and try again"), help: regenerationHelp)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $editedTranscript)
                            .font(AppTypography.body).frame(height: 200)
                            .scrollContentBackground(.hidden)
                            .padding(8).background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.separator, lineWidth: 1))
                            .accessibilityLabel(L("다시 만들 원문", "Source for the new prompt"))
                            .accessibilityIdentifier("prompt-source-editor")
                            .disabled(isBusy || composition.isProcessing)
                        if let settings = regenerationSettings {
                            Text(settings).font(AppTypography.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let failure = PromptCompositionPresentation.sourceValidationFailure(editedTranscript) {
                            Text(failure.localizedDescription).font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                Text(L("생성 1~2회·Jev 검토 2회 · 추가 API 비용 · 자동 입력 없음", "1–2 generations · 2 Jev reviews · Additional API cost · No automatic typing"))
                    .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(L("취소", "Cancel")) { sourceEditorExpanded = false }.keyboardShortcut(.cancelAction)
                    Button(L("이 원문으로 다시 만들기", "Create prompt from this source"), systemImage: "arrow.clockwise") {
                        guard !isBusy, composition.canRegenerate(with: editedTranscript) else { return }
                        regenerate(composition.id, composition.transcript, editedTranscript)
                        sourceEditorExpanded = false
                    }
                    .buttonStyle(AppActionButtonStyle(primary: true))
                    .accessibilityIdentifier("prompt-regenerate")
                    .disabled(isBusy || !composition.canRegenerate(with: editedTranscript))
                }
            }
            .padding(AppLayout.pageInset).frame(width: 560, height: 520)
            .background(AppTheme.pageBackground)
            .buttonStyle(AppActionButtonStyle())
        }
    }

    private var regenerationHelp: String {
        L("잘못 인식된 부분을 고치거나 같은 원문으로 다시 만들 수 있습니다. 현재 원문으로 생성 1~2회와 Jev 검토 2회를 실행하며, 필요한 경우에만 한 번 다듬습니다. 오류는 해당 단계에서 멈추고 음성을 다시 전송하지 않습니다.\n\n결과는 복사용 미리보기이며 자동 입력하지 않습니다. 원문과 편집 내용은 다음 프롬프트 처리나 앱 종료 때 사라지며 저장된 기록의 원문과 실패 녹음을 덮어쓰지 않습니다.", "Correct recognition mistakes or regenerate from the same source. This runs one or two generations and two Jev reviews, polishing once only when needed. Errors stop at the current stage and audio is not sent again.\n\nThe result is a preview to copy, never typed automatically. Source edits clear with the next prompt or app exit and do not overwrite stored history or failed recordings.")
    }

    private func reviewDetails(_ review: PromptCompositionReviewResult, isFinal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isFinal ? L("최종 검토 항목", "Final review") : L("초안 검토 항목", "Draft review"))
                .font(AppTypography.caption.weight(.medium))
            ForEach(PromptCompositionIssue.allCases, id: \.self) { issue in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(issueTitle(issue)).font(AppTypography.caption.weight(.medium))
                        Spacer()
                        if let assessment = review.assessments[issue] {
                            Text(assessment.accepted ? L("통과", "Passed") : L("확인 필요", "Needs attention"))
                                .foregroundStyle(assessment.accepted ? AppTheme.accentForeground : AppTheme.warm)
                        } else {
                            Text(L("검토 정보 없음", "Review unavailable")).foregroundStyle(.secondary)
                        }
                    }.font(AppTypography.caption)
                    if let assessment = review.assessments[issue] {
                        Text(assessmentDetail(assessment))
                            .font(AppTypography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            OptionHelpLabel(L("검토 신호 읽기", "Reading review signals"), help: L("검토 신호와 확신은 모델의 참고 판단이며 정확도를 뜻하지 않습니다.", "Review signals and confidence are advisory model judgments, not accuracy."))
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
                .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                .fixedSize(horizontal: false, vertical: true)
        case .blocked:
            Label(L("기존 지침 관련 검토에서 제공을 보류한 결과입니다.", "This result was held by the instruction boundary review."), systemImage: "exclamationmark.circle")
                .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
        case .ready:
            EmptyView()
        case nil:
            Text(L("당시 품질 검토 정보는 보관되지 않았습니다.", "Quality review details were not saved for this result."))
                .font(AppTypography.caption).foregroundStyle(.secondary)
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
