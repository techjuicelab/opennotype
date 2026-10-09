import OpenNoTypeCore
import SwiftUI

/// Explicit review consent is scoped to the visible result and selected connection.
struct JevReviewRequestButton: View {
    @Bindable var model: AppModel
    let title: String
    let targetTitle: String
    let requestIdentity: String
    var purpose: DecisionReviewPurpose = .dictation
    var disabled = false
    let action: () -> Void
    @State private var confirmsReview = false
    @State private var confirmation: ReviewConfirmation?

    private struct ReviewConfirmation {
        let provider: DecisionProvider
        let requestIdentity: String
        let targetTitle: String
        let purpose: DecisionReviewPurpose
    }

    var body: some View {
        Button(title, systemImage: "checkmark.bubble") {
            confirmation = ReviewConfirmation(provider: model.preferences.decisionProvider,
                                              requestIdentity: requestIdentity, targetTitle: targetTitle, purpose: purpose)
            confirmsReview = true
        }
        .disabled(disabled || model.isBusy || model.manualDecisionReviewInProgress
                  || model.decisionDictionaryOperationInProgress || model.startupState != .ready)
        .confirmationDialog(L("이 결과를 Jev로 검토할까요?", "Review this result with Jev?"),
                            isPresented: $confirmsReview, titleVisibility: .visible, presenting: confirmation) { request in
            Button(L("전송하고 검토", "Send for review")) {
                guard request.provider == model.preferences.decisionProvider,
                      request.requestIdentity == requestIdentity, request.purpose == purpose else { return }
                action()
            }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: { request in
            Text(confirmationMessage(request))
        }
        .onChange(of: requestIdentity) { _, _ in confirmsReview = false }
        .onChange(of: purpose) { _, _ in confirmsReview = false }
        .onChange(of: model.preferences.decisionProvider) { _, _ in confirmsReview = false }
    }

    private func confirmationMessage(_ request: ReviewConfirmation) -> String {
        let route = request.provider == .typeSafe
            ? L("TypeSafe의 Jev API에 직접", "directly to TypeSafe’s Jev API")
            : L("OpenRouter를 통해 TypeSafe의 Jev 모델에", "to TypeSafe’s Jev model through OpenRouter")
        let content: String
        switch request.purpose {
        case .dictation:
            content = L("인식 원문·정리 결과·관련 표기 후보", "the transcript, cleaned text and relevant spelling candidates")
        case .translation(let language):
            content = L("인식 원문·번역 결과·당시 목표 언어(\(language))", "the source transcript, translation and captured target language (\(language))")
        case .rewrite:
            content = L("당시 선택한 원문·음성 수정 지시·수정 결과", "the selected source text, spoken editing instruction and edited result")
        case .promptComposition:
            content = L("인식 원문·작업 프롬프트", "the transcript and task prompt")
        }
        return L("대상: \(request.targetTitle)\n\n전송 내용: \(content)\n\(route) 보냅니다. API 사용 비용이 발생할 수 있습니다. 녹음과 선택 영역 밖의 주변 문맥은 보내지 않습니다.\n\n검토만 실행하며 결과나 다른 앱의 입력을 바꾸지 않습니다. 자동 검토 설정도 유지합니다.",
                 "Reviewing: \(request.targetTitle)\n\nSends \(content) \(route). API charges may apply. Audio and surrounding text outside the captured selection are not sent.\n\nThis only reviews the text. It does not change the result, type into another app or change your automatic review setting.")
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
            JevComparisonView(target: target)
            if target.mode == .dictation {
                JevNameDiscoveryButton(model: model, target: target)
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
            if target.mode != .prompt {
                JevImprovementView(model: model, target: target)
            }
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
            Label(proposal.evidence.title, systemImage: proposal.evidence == .candidatePreferred ? "text.magnifyingglass" : "questionmark.circle")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text(proposal.evidence.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
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
        let evidence = "\n\n" + request.proposal.evidence.title + ": " + request.proposal.evidence.detail
        return mapping + replacement + evidence + L("\n\n다음 음성 인식과 문장 정리에 참고합니다. 추가 API 호출은 없으며, 현재 결과와 다른 앱의 글은 바꾸지 않습니다. 저장 후 마지막 변경을 되돌릴 수 있습니다.",
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

/// Highlight exact local differences without implying that every change is an error.
private struct JevComparisonView: View {
    let target: JevReviewTarget
    private var comparison: JevTextComparison { .init(source: target.comparisonSource, result: target.output) }

    var body: some View {
        let value = comparison
        DisclosureGroup(L("원문과 결과의 표현 차이", "Wording differences from the source")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("이 Mac에서 표현을 비교한 결과입니다. 번역·요청한 수정·표기 정리로 생긴 차이일 수 있으며, 오류 판정이 아닙니다.", "Compared locally on this Mac. Differences may come from translation, requested edits or spelling cleanup; they are not error judgments."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                if case .translation(let language) = target.purpose {
                    Text(L("목표 언어: \(language)", "Target language: \(language)"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if case .rewrite = target.purpose {
                    comparisonText(L("음성으로 말한 수정 지시", "Spoken editing instruction"), value: target.transcript)
                }
                if value.numbersDiffer {
                    Text(L("숫자 표기가 달라졌습니다. 의도한 변환인지 확인해 주세요.", "Number notation differs. Check whether this was intended."))
                        .font(.system(size: 11, weight: .medium))
                    tokenLine(L("원문의 숫자", "Source numbers"), values: value.sourceNumbers)
                    tokenLine(L("결과의 숫자", "Result numbers"), values: value.resultNumbers)
                }
                if value.hasDifferences {
                    tokenLine(L("원문 쪽 표현", "Source wording"), values: value.sourceOnly)
                    tokenLine(L("결과 쪽 표현", "Result wording"), values: value.resultOnly)
                } else {
                    Text(L("비교한 범위에서 표현 차이가 없습니다.", "No wording differences in the compared range."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if value.truncated {
                    Text(L("긴 문장은 앞부분과 일부 변경만 표시합니다. 전체 원문도 확인해 주세요.", "Long text shows only the beginning and some changes. Check the full source too."))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                comparisonText(target.sourceTitle, value: target.comparisonSource)
                comparisonText(target.outputTitle, value: target.output)
            }.padding(.top, 8)
        }.font(.system(size: 12))
    }

    private func tokenLine(_ title: String, values: [String]) -> some View {
        Text(title + ": " + (values.isEmpty ? L("없음", "None") : values.joined(separator: " · ")))
            .font(.system(size: 11)).textSelection(.enabled)
    }

    private func comparisonText(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .medium))
            Text(String(value.prefix(6_000)) + (value.count > 6_000 ? "…" : ""))
                .font(.system(size: 12)).textSelection(.enabled).lineSpacing(3)
        }
    }
}
