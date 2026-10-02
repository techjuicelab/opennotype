import OpenNoTypeCore
import SwiftUI

/// Explicit review consent is scoped to the visible result and selected connection.
struct JevReviewRequestButton: View {
    @Bindable var model: AppModel
    let title: String
    let targetTitle: String
    let requestIdentity: String
    var disabled = false
    let action: () -> Void
    @State private var confirmsReview = false
    @State private var confirmation: ReviewConfirmation?

    private struct ReviewConfirmation {
        let provider: DecisionProvider
        let requestIdentity: String
        let targetTitle: String
    }

    var body: some View {
        Button(title, systemImage: "checkmark.bubble") {
            confirmation = ReviewConfirmation(provider: model.preferences.decisionProvider,
                                              requestIdentity: requestIdentity, targetTitle: targetTitle)
            confirmsReview = true
        }
        .disabled(disabled || model.isBusy || model.manualDecisionReviewInProgress
                  || model.decisionDictionaryOperationInProgress || model.startupState != .ready)
        .confirmationDialog(L("이 결과를 Jev로 검토할까요?", "Review this result with Jev?"),
                            isPresented: $confirmsReview, titleVisibility: .visible, presenting: confirmation) { request in
            Button(L("전송하고 검토", "Send for review")) {
                guard request.provider == model.preferences.decisionProvider,
                      request.requestIdentity == requestIdentity else { return }
                action()
            }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: { request in
            Text(confirmationMessage(request))
        }
        .onChange(of: requestIdentity) { _, _ in confirmsReview = false }
        .onChange(of: model.preferences.decisionProvider) { _, _ in confirmsReview = false }
    }

    private func confirmationMessage(_ request: ReviewConfirmation) -> String {
        let route = request.provider == .typeSafe
            ? L("TypeSafe의 Jev API에 직접", "directly to TypeSafe’s Jev API")
            : L("OpenRouter를 통해 TypeSafe의 Jev 모델에", "to TypeSafe’s Jev model through OpenRouter")
        return L("대상: \(request.targetTitle)\n\n이 결과의 인식 원문·정리 결과·관련 표기 후보를 \(route) 보냅니다. API 사용 비용이 발생할 수 있습니다. 녹음과 다른 앱의 주변 문맥은 보내지 않습니다.\n\n검토만 실행하며 결과나 다른 앱의 입력을 바꾸지 않습니다. 자동 검토 설정도 유지합니다.",
                 "Reviewing: \(request.targetTitle)\n\nSends this result’s transcript, cleaned text and relevant spelling candidates \(route). API charges may apply. Audio and surrounding text from other apps are not sent.\n\nThis only reviews the text. It does not change the result, type into another app or change your automatic review setting.")
    }
}

/// The caller only displays this view beside the result identified by `target`.
struct JevReviewView: View {
    @Bindable var model: AppModel
    let target: JevReviewTarget
    @State private var confirmsDictionarySave = false
    @State private var dictionaryConfirmation: DictionaryConfirmation?

    private struct DictionaryConfirmation {
        let proposal: JevSpellingProposal
        let existing: DictionaryEntry?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(target.title, systemImage: "checkmark.bubble")
                .font(.system(size: 12, weight: .semibold))
            if model.manualDecisionReviewInProgress {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(L("Jev가 이 결과를 검토하고 있어요…", "Jev is reviewing this result…"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("검토 취소", "Cancel review")) { model.cancelManualDecisionReview() }
                        .buttonStyle(.borderless)
                }
            }
            if let status = model.manualDecisionReviewStatus, status != model.decisionReviewSummary {
                Text(status).font(.system(size: 12)).lineSpacing(3).textSelection(.enabled)
            }
            if let summary = model.decisionReviewSummary {
                Text(summary).font(.system(size: 12)).lineSpacing(3).textSelection(.enabled)
            }
            if !model.decisionRiskSignals.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.decisionRiskSignals) { signal in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: signal.isHigh ? "exclamationmark.circle" : "circle")
                                .foregroundStyle(signal.isHigh ? Color.orange : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(signal.title).font(.system(size: 12, weight: .medium))
                                Text(signal.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(signal.isHigh ? L("확인 필요", "Review needed") : L("강한 신호 없음", "No strong signal"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(signal.isHigh ? Color.orange : Color.secondary)
                        }.accessibilityElement(children: .combine)
                    }
                }
                Text(L("모델의 검토 신호이며, 의미가 정확히 보존되었다는 보장은 아닙니다.", "These are model review signals, not a guarantee that meaning was preserved."))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if !model.decisionProposals.isEmpty {
                Divider()
                Text(L("확인할 영문 표기", "English spellings to review")).font(.system(size: 12, weight: .medium))
                ForEach(model.decisionProposals) { proposal in
                    proposalRow(proposal)
                }
                Text(L("제안은 현재 결과를 바꾸지 않습니다. 직접 저장한 표기만 다음 음성 인식과 문장 정리에 참고합니다.", "Suggestions leave this result unchanged. Spellings you choose to save can guide future speech recognition and text cleanup."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                Button(L("개인 사전 열기", "Open dictionary")) { model.page = .dictionary }
            }
            JevDictionaryUndoView(model: model)
            Text(L("검토 결과는 메모리에만 있으며 새 작업이나 기록 삭제 시 지워집니다.", "Review results stay in memory and are cleared when a new job starts or history is deleted."))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .confirmationDialog(L("이 표기를 개인 사전에 저장할까요?", "Save this spelling to your dictionary?"),
                            isPresented: $confirmsDictionarySave, titleVisibility: .visible, presenting: dictionaryConfirmation) { request in
            Button(request.existing == nil ? L("사전에 등록", "Add to dictionary") : L("기존 표기 바꾸기", "Replace saved spelling")) {
                Task { await model.saveDecisionProposal(request.proposal, replacing: request.existing) }
            }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: { request in
            Text(dictionaryMessage(request))
        }
        .onChange(of: target.id) { _, _ in confirmsDictionarySave = false }
        .onChange(of: model.decisionReviewTarget?.id) { _, _ in confirmsDictionarySave = false }
    }

    private func proposalRow(_ proposal: JevSpellingProposal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(proposal.title).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
            if proposal.choice == .useCandidate {
                if let existing = existingEntry(for: proposal), existing.written == proposal.candidate {
                    Label(L("이미 사전에 등록된 표기입니다.", "Already in your dictionary."), systemImage: "checkmark.circle")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else if proposal.canSave {
                    Button(L("표기 확인하고 저장…", "Review and save spelling…"), systemImage: "character.book.closed") {
                        dictionaryConfirmation = DictionaryConfirmation(proposal: proposal, existing: existingEntry(for: proposal))
                        confirmsDictionarySave = true
                    }
                    .disabled(!model.canSaveDecisionProposal(proposal) || model.decisionDictionaryOperationInProgress)
                }
            } else if proposal.choice == .keepOriginal {
                Text(L("이 문장에서 원문 표기를 유지하자는 제안입니다. 전체 사전에 역방향으로 등록하지 않습니다.", "A suggestion to keep the original spelling in this sentence. It is not saved as a reverse dictionary rule."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func existingEntry(for proposal: JevSpellingProposal) -> DictionaryEntry? {
        model.dictionary.first { $0.spoken.caseInsensitiveCompare(proposal.original) == .orderedSame }
    }

    private func dictionaryMessage(_ request: DictionaryConfirmation) -> String {
        let mapping = L("말하거나 인식된 표기: \(request.proposal.original)\n저장할 표기: \(request.proposal.candidate)",
                        "Spoken or recognized spelling: \(request.proposal.original)\nSpelling to save: \(request.proposal.candidate)")
        let replacement = request.existing.map {
            L("\n\n현재 등록된 ‘\($0.written)’ 표기를 바꿉니다.", "\n\nReplaces the currently saved spelling ‘\($0.written)’.")
        } ?? ""
        return mapping + replacement + L("\n\n다음 음성 인식과 문장 정리에 참고합니다. 추가 API 호출은 없으며, 현재 결과와 다른 앱의 글은 바꾸지 않습니다. 저장 후 마지막 변경을 되돌릴 수 있습니다.",
                                           "\n\nGuides future speech recognition and text cleanup. No additional API request is made, and this result and text in other apps stay unchanged. You can undo the last saved change.")
    }
}

/// Kept separate from automatic-learning undo and also reachable from the dictionary.
struct JevDictionaryUndoView: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.decisionProposalStatus != nil || model.canUndoDecisionDictionarySave {
            VStack(alignment: .leading, spacing: 9) {
                if let status = model.decisionProposalStatus {
                    Text(status).font(.system(size: 12)).lineSpacing(3).textSelection(.enabled)
                }
                if model.canUndoDecisionDictionarySave {
                    Button(L("마지막 Jev 사전 저장 되돌리기", "Undo last dictionary save from Jev"), systemImage: "arrow.uturn.backward") {
                        Task { await model.undoDecisionDictionarySave() }
                    }.disabled(model.decisionDictionaryOperationInProgress)
                }
            }
        }
    }
}
