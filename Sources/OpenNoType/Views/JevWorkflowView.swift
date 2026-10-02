import SwiftUI
import OpenNoTypeCore

struct JevImprovementView: View {
    @Bindable var model: AppModel
    let target: JevReviewTarget
    @State private var confirms = false
    @State private var connection = ""
    private var identity: String {
        "\(target.id)|\(model.preferences.effectiveTextProvider.rawValue)|\(model.preferences.improvementModel)|\(model.preferences.decisionProvider.rawValue)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(L("개선안 비교", "Compare an alternative")).font(.system(size: 12, weight: .semibold))
            Text(L("원문을 바탕으로 개선안 한 개를 만들고 Jev로 다시 검토합니다. 기존 결과와 비교한 뒤 원하는 쪽을 복사하세요.", "Generate one alternative from the source and review it with Jev. Compare it with the existing result, then copy the version you prefer."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button(L("개선안 만들기…", "Generate an alternative…"), systemImage: "arrow.triangle.2.circlepath") {
                connection = identity; confirms = true
            }.disabled(model.isBusy || model.jevWorkflowInProgress || model.manualDecisionReviewInProgress || model.decisionDictionaryOperationInProgress)
            Text("\(model.preferences.effectiveTextProvider.displayName) · \(model.preferences.improvementModel)")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            if let preview = model.jevImprovement, preview.target == target {
                if preview.isProcessing {
                    HStack {
                        ProgressView().controlSize(.small)
                        Button(L("개선안 취소", "Cancel alternative")) { model.cancelJevWorkflow() }
                    }
                }
                if let status = preview.status { Text(status).font(.system(size: 12)).textSelection(.enabled) }
                if let output = preview.output {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("기존 결과", "Existing result")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Text(target.output).textSelection(.enabled)
                        Text(L("개선안", "Alternative")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Text(output).textSelection(.enabled)
                    }.font(.system(size: 13)).lineSpacing(4)
                    Button(L("개선안 복사", "Copy alternative"), systemImage: "doc.on.doc") {
                        Task { await model.copyJevImprovement(preview.id) }
                    }.disabled(preview.isProcessing || output.isEmpty)
                    Text(L("복사 후 직접 붙여넣으세요. 기록이나 다른 앱의 문장을 자동으로 덮어쓰지 않습니다.", "Paste the copied text yourself. History and text in other apps are never overwritten automatically."))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog(L("개선안을 만들고 검토할까요?", "Generate and review an alternative?"), isPresented: $confirms, titleVisibility: .visible) {
            Button(L("개선안 생성 및 검토", "Generate and review")) {
                guard connection == identity else { return }
                model.createJevImprovement(for: target)
            }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("\(model.preferences.effectiveTextProvider.displayName) · \(model.preferences.improvementModel)에 원문·기존 결과·개인 사전 힌트를 보내 생성 1회, 선택한 Jev 연결로 원문·개선안 검토 1회를 요청합니다. 번역은 목표 언어, 선택 수정은 당시 선택 원문·수정 지시를 포함합니다. 추가 API 비용이 발생할 수 있습니다. 녹음과 주변 문맥은 보내지 않습니다.", "Sends the source, existing result and dictionary hints to \(model.preferences.effectiveTextProvider.displayName) · \(model.preferences.improvementModel) for one generation, then the source and alternative to your selected Jev connection for one review. Translation includes the target language; editing includes the original selection and edit instruction. Additional API charges may apply. Audio and surrounding context are not sent."))
        }
        .onChange(of: identity) { _, _ in confirms = false }
    }
}

struct JevCorrectionReviewView: View {
    @Bindable var model: AppModel
    let candidate: LearningCandidate
    @State private var confirmsReview = false
    @State private var confirmsSave = false
    @State private var provider: DecisionProvider = .openRouter
    @State private var expectedPrevious: DictionaryEntry?
    @State private var reviewID: UUID?

    var body: some View {
        if let entry = CorrectionLearner.reviewProposal(original: candidate.originalText, edited: candidate.editedText) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(entry.spoken) → \(entry.written)").font(.system(size: 12, weight: .medium))
                Button(L("Jev로 표기 검토…", "Review spelling with Jev…"), systemImage: "checkmark.bubble") {
                    provider = model.preferences.decisionProvider; confirmsReview = true
                }.disabled(model.isBusy || model.jevWorkflowInProgress || model.manualDecisionReviewInProgress || model.decisionDictionaryOperationInProgress)
                if let review = model.jevCorrectionReview, review.candidate == candidate {
                    if review.isProcessing {
                        HStack {
                            ProgressView().controlSize(.small)
                            Button(L("검토 취소", "Cancel review")) { model.cancelJevWorkflow() }
                        }
                    }
                    if let status = review.status { Text(status).font(.system(size: 12)).textSelection(.enabled) }
                    if review.canSave {
                        Button(L("확인한 교정 저장…", "Save confirmed correction…")) {
                            expectedPrevious = model.dictionary.first { $0.spoken.caseInsensitiveCompare(entry.spoken) == .orderedSame }
                            reviewID = review.id; confirmsSave = true
                        }.disabled(model.decisionDictionaryOperationInProgress || model.isBusy)
                    }
                }
            }
            .confirmationDialog(L("이 교정을 Jev로 검토할까요?", "Review this correction with Jev?"), isPresented: $confirmsReview, titleVisibility: .visible) {
                Button(L("전송하고 검토", "Send for review")) {
                    guard provider == model.preferences.decisionProvider else { return }
                    model.reviewLearningCandidate(candidate)
                }
                Button(L("취소", "Cancel"), role: .cancel) {}
            } message: {
                Text(L("\(provider.displayName)에 위의 교정 전·후 문장과 표기 후보 한 쌍을 보냅니다. API 비용이 발생할 수 있습니다. 사전 저장은 검토 후 별도로 확인합니다.", "Sends the original and edited sentences above and one spelling pair to \(provider.displayName). API charges may apply. Saving to the dictionary requires a separate confirmation after review."))
            }
            .confirmationDialog(L("이 표기를 사전에 저장할까요?", "Save this spelling to your dictionary?"), isPresented: $confirmsSave, titleVisibility: .visible) {
                Button(L("사전에 저장", "Save to dictionary")) {
                    guard let reviewID else { return }
                    Task { await model.saveReviewedCorrection(reviewID, replacing: expectedPrevious) }
                }
                Button(L("취소", "Cancel"), role: .cancel) {}
            } message: {
                Text(L("\(entry.spoken) → \(entry.written)\n\nJev의 제안은 정확성을 보장하지 않습니다. 같은 인식 표기가 있으면 교체하며 마지막 저장은 되돌릴 수 있습니다.", "\(entry.spoken) → \(entry.written)\n\nJev's suggestion does not guarantee correctness. An existing mapping for the same spelling will be replaced. You can undo the last save."))
            }
            .onChange(of: candidate.id) { _, _ in confirmsReview = false; confirmsSave = false }
            .onChange(of: model.preferences.decisionProvider) { _, _ in confirmsReview = false; confirmsSave = false }
        }
    }
}
