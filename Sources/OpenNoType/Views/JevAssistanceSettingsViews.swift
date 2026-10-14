import AppKit
import SwiftUI
import OpenNoTypeCore

struct JevFeedbackLearningSettingsView: View {
    @Bindable var model: AppModel
    var isEditable: Bool = true
    @State private var confirmsClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(L("해결한 오류 유형 기억", "Remember resolved error patterns"), help: learningHelp,
                        state: model.preferences.jevFeedbackLearningEnabled
                        ? (learningInactive
                           ? L("현재 미적용 · 원래 언어·AI 정리·기록 필요", "Paused · Requires spoken language, cleanup and history")
                           : L("다음 문장 요청에 포함 · 별도 요청 없음", "Included in future text requests · No separate request")) : nil) {
                Toggle(L("해결한 오류 유형 기억", "Remember resolved error patterns"), isOn: $model.preferences.jevFeedbackLearningEnabled)
                    .labelsHidden().toggleStyle(.switch).disabled(!isEditable)
            }
            SettingsRow(L("현재 모델에 저장된 유형", "Categories for the current model")) {
                Text(L("\(model.jevLearnedIssues.count)개", "\(model.jevLearnedIssues.count) categories")).font(AppTypography.caption)
            }
            if let summary = model.jevLearningSummary { Text(summary).font(AppTypography.caption).textSelection(.enabled) }
            if !model.jevLearnedIssues.isEmpty {
                Text(model.jevLearnedIssues.map(\.title).joined(separator: " · "))
                    .font(AppTypography.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            SettingsRow(L("모든 모델의 오류 유형", "Categories for all models"), help: learningHelp) {
                Button(L("지우기…", "Clear…"), role: .destructive) {
                    guard canClear else { return }; confirmsClear = true
                }.disabled(!canClear)
            }
        }
        .confirmationDialog(L("학습한 오류 유형을 모두 지울까요?", "Clear all learned error patterns?"), isPresented: $confirmsClear, titleVisibility: .visible) {
            Button(L("모든 모델의 오류 유형 지우기", "Clear patterns for all models"), role: .destructive) {
                guard canClear else { return }
                Task { await model.clearJevFeedbackLearning() }
            }
            .disabled(!canClear)
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("이 Mac에 저장한 오류 유형을 지우고 다음 문장 정리에 반영하지 않습니다. 개인 사전과 문장 기록은 유지합니다.", "Removes error categories saved on this Mac so they no longer inform future cleanup. Your dictionary and text history are preserved."))
        }
    }

    private var canClear: Bool { isEditable && !AppLaunch.isPreview && model.startupState == .ready }
    private var learningInactive: Bool {
        model.preferences.usesFastDictation || model.preferences.dictationOutputLanguage.isTranslation || !model.preferences.historyEnabled
    }

    private var learningHelp: String {
        L("재검토를 통과한 교정에서 숫자·부정·조건 등 정해진 오류 유형만 기억합니다. 현재 문장 제공자·모델의 다음 요청에 주의사항으로 넣으며, 과거 원문이나 교정안을 저장하지 않습니다. AI 모델을 재학습하거나 오류가 반복되지 않는다고 보장하는 기능은 아닙니다.", "Remembers only predefined categories, such as numbers, negation and conditions, from repairs that pass recheck. Adds reminders to future requests for the current text provider and model. Past sources and repair candidates are not stored. This does not train the AI model or guarantee that errors will not recur.")
        + "\n\n" + L("이 Mac에 암호화해 보관합니다. 이 옵션을 끄면 새 학습과 다음 요청의 반영을 멈추고 기존 유형은 유지합니다. 지우기는 모든 모델의 오류 유형만 삭제합니다. 기록을 끄거나 모두 삭제할 때도 유형을 지웁니다. 이름 표기의 전역 매핑은 직접 확인해 개인 사전에 저장하세요.", "Encrypted on this Mac. Turning this option off stops new learning and use in future requests while retaining saved categories. Clear removes only error categories for all models. Turning off or clearing all history also clears these categories. Confirm name-spelling mappings yourself before saving them to the dictionary.")
    }
}

struct JevAssistanceSettingsView: View {
    @Bindable var model: AppModel
    var isEditable: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
                option(L("중요한 변경을 세부적으로 검토", "Review important changes in more detail"),
                       value: $model.preferences.jevDetailedReviewEnabled,
                       detail: L("숫자·부정·조건·요청·이름의 변화를 구분합니다. 원문과 결과를 보내는 Jev 검토에 질문이 추가되어 비용이 늘 수 있습니다.", "Separates changes to numbers, negation, conditions, intent and names. Adds questions to the Jev review of the source and result, which may increase its cost."),
                       status: L("검토 질문 추가 · 비용 증가 가능", "Extra review questions · May increase cost"))
                option(L("단순한 받아쓰기의 검토 비용 줄이기", "Reduce review costs for simple dictation"),
                       value: $model.preferences.jevEconomyEnabled,
                       detail: L("비어 있지 않은 원문과 결과가 완전히 같고 표기 후보가 없을 때만 자동 Jev 검토를 생략합니다. 이 Mac에서 비교하며, 생략은 검토 통과를 뜻하지 않습니다. 직접 요청한 검토는 실행합니다.", "Skips automatic Jev review only when the nonempty source and result are identical and there are no spelling candidates. The comparison runs on this Mac. A skipped review is not a passed review. Explicit review requests still run."),
                       status: model.preferences.decisionReviewMode == .repair
                           ? L("현재 미적용 · 입력 전 교정은 검토 유지", "Not applied · Repair before typing keeps review")
                           : L("조건에 맞으면 자동 검토 생략 · 직접 검토 유지", "Skips automatic review when eligible · Explicit reviews remain"))
                option(L("주의 신호가 있으면 개선안 한 개 준비", "Prepare one alternative when review flags a concern"),
                       value: $model.preferences.jevAutomaticImprovementEnabled,
                       detail: L("말한 언어 유지 받아쓰기의 입력 전 보호에서 주의 신호가 있을 때 보조 모델로 별도 개선안을 준비하고 Jev로 검토합니다. 입력 전 교정·입력 후 검토에서는 현재 문장 모델의 교정 흐름을 사용해 같은 작업에서 두 번 생성하지 않습니다. 번역의 입력 전 검토는 자동 개선안을 만들지 않습니다. 생성과 검토 비용이 추가되며, 별도 개선안은 확인 후 복사합니다.", "For Keep spoken language dictation, prepares a separate alternative with the alternative model when Protect before typing flags a concern, then reviews it with Jev. Repair before typing and Review after typing use the current text model's repair flow without generating twice for the same job. Translation review before typing does not prepare an automatic alternative. Generation and review cost extra. Review and copy separate alternatives yourself."),
                       status: alternativeStatus)
                option(L("모호한 수정 지시를 먼저 확인", "Check unclear editing instructions first"),
                       value: $model.preferences.jevClarifyEditsEnabled,
                       detail: L("선택한 원문과 음성 수정 지시를 Jev에 추가 전송합니다. 지시가 모호하면 자동 입력을 멈추고 구체적인 지시를 받습니다. 명확히 한 뒤 만드는 수정안도 확인 후 복사하며, 추가 검토·생성 비용이 발생할 수 있습니다.", "Also sends the selected source and spoken edit instruction to Jev. If the instruction is unclear, pauses automatic typing and asks for a specific instruction. The resulting edit is available to review and copy. Extra review and generation charges may apply."),
                       status: L("원문·수정 지시 추가 전송 · 비용 발생 가능", "Extra source and edit-instruction requests · May add charges"))
                option(L("헷갈릴 수 있는 음성을 한 번 더 인식", "Try another transcription for potentially confusing speech"),
                       value: $model.preferences.jevReRecognitionEnabled,
                       detail: L("지원되는 받아쓰기에서 확인이 필요한 표현을 발견하면 같은 녹음을 Groq 또는 OpenAI 음성 인식에 한 번 더 보내고 두 인식문을 Jev로 비교합니다. 음성 인식·검토 비용이 추가됩니다. 더 나은 인식문인지 직접 확인하며 자동 교체하지 않습니다.", "For supported dictation, sends the same recording once more to Groq or OpenAI when a phrase needs checking, then compares both transcripts with Jev. Speech recognition and review cost extra. You decide whether the alternative is better; it never replaces the result automatically."),
                       status: L("조건에 따라 녹음 재전송·추가 요청 · 자동 교체 없음", "May resend audio and add requests · No automatic replacement"))
        }
    }

    private var enabledCount: Int {
        [model.preferences.jevDetailedReviewEnabled, model.preferences.jevEconomyEnabled,
         model.preferences.jevAutomaticImprovementEnabled, model.preferences.jevClarifyEditsEnabled,
         model.preferences.jevReRecognitionEnabled].filter { $0 }.count
    }

    private var enabledSummary: String {
        guard enabledCount > 0 else { return L("사용 안 함", "Off") }
        if model.preferences.jevAutomaticImprovementEnabled || model.preferences.jevClarifyEditsEnabled || model.preferences.jevReRecognitionEnabled {
            return L("켜짐 \(enabledCount)개 · 추가 요청 가능", "\(enabledCount) enabled · May add requests")
        }
        if model.preferences.jevDetailedReviewEnabled {
            return L("켜짐 \(enabledCount)개 · 검토 비용 증가 가능", "\(enabledCount) enabled · Review may cost more")
        }
        return L("켜짐 \(enabledCount)개", "\(enabledCount) enabled")
    }

    private var alternativeStatus: String {
        if model.preferences.usesFastDictation || model.preferences.dictationOutputLanguage.isTranslation {
            return L("현재 미적용 · 말한 언어 유지·AI 정리에서 사용", "Paused · Requires Keep spoken language with AI cleanup")
        }
        if model.preferences.decisionReviewMode != .protect {
            return L("현재 미적용 · 입력 전 보호에서 사용", "Paused · Requires Protect before typing")
        }
        return L("생성·검토 추가 요청 · 비용 발생 가능 · 확인 후 복사", "Extra generation and review requests · May add charges · Review and copy")
    }

    private func option(_ title: String, value: Binding<Bool>, detail: String, status: String) -> some View {
        SettingsRow(title, help: detail + "\n\n" + L("자동 검토 모드는 별도로 선택합니다. 정확성을 보장하지 않으며 각 기능에 필요한 내용만 추가 전송합니다.", "Choose the automatic review mode separately. Accuracy is not guaranteed; each feature sends only the content described."), state: value.wrappedValue ? status : nil) {
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).disabled(!isEditable)
        }
    }
}
