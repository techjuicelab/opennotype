import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OpenNoTypeCore

enum JevRepairPresentation {
    static func modeDetail(_ mode: DecisionReviewMode) -> String {
        switch mode {
        case .off:
            L("자동 검토·교정을 실행하지 않습니다. 직접 요청하는 검토와 사전 기능은 사용할 수 있습니다.", "Automatic review and repair are off. Explicit reviews and dictionary features remain available.")
        case .observe:
            L("음성 재인식을 끈 상태에서는 먼저 입력한 뒤 검토합니다. 강한 오류 신호가 있으면 뒤에서 교정안 한 개를 만들고 재검토합니다. 이미 입력한 글은 바꾸지 않으며, 아래 학습을 켜면 재검토를 통과한 오류 유형을 다음 문장 정리에 반영합니다.", "With audio re-recognition off, types first, then reviews. A strong concern triggers one background repair and recheck. Text already entered is never changed. With learning enabled below, resolved categories that pass recheck are reflected in future cleanup requests.")
        case .protect:
            L("입력 전에 최대 \(Int(DecisionClient.timeout))초 검토하며, 응답이 오면 즉시 진행합니다. 강한 의미 변경 신호가 있으면 입력을 보류합니다. 자동으로 교정하지는 않습니다. 검토 실패·시간 초과에는 기존 결과를 입력하고 검토 미완료를 표시합니다.", "Reviews for up to \(Int(DecisionClient.timeout)) seconds before typing and continues as soon as the response arrives. A strong meaning-change signal holds input. It does not repair automatically. If review fails or times out, types the existing result and marks review incomplete.")
        case .repair:
            L("입력 전에 검토하고, 강한 오류 신호가 있으면 한 번 교정한 뒤 재검토합니다. 검토·재검토는 각각 최대 \(Int(DecisionClient.timeout))초, 교정 생성은 최대 8초이며 응답이 오면 즉시 진행합니다. 기준을 통과한 결과만 입력합니다. 키 누락·실패·시간 초과 또는 미해결 오류는 자동 입력을 보류하고 결과를 보여 줍니다.", "Reviews before typing, with one repair and recheck when a strong concern is found. Review and recheck each allow up to \(Int(DecisionClient.timeout)) seconds; repair generation allows up to 8 seconds. Continues as soon as each response arrives and types only a result meeting the criteria. Missing keys, failures, timeouts or unresolved concerns hold automatic input and show the result for you to review.")
        }
    }
}

struct JevFeedbackLearningSettingsView: View {
    @Bindable var model: AppModel
    @State private var confirmsClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(L("해결한 오류 유형을 다음 문장 정리에 반영", "Use resolved error patterns in future cleanup"), isOn: $model.preferences.jevFeedbackLearningEnabled)
            Text(L("재검토를 통과한 교정에서 숫자·부정·조건 등 정해진 오류 유형만 기억합니다. 현재 문장 제공자·모델의 다음 요청에 주의사항으로 넣으며, 과거 원문이나 교정안을 저장하지 않습니다. AI 모델을 재학습하거나 오류가 반복되지 않는다고 보장하는 기능은 아닙니다.", "Remembers only predefined categories, such as numbers, negation and conditions, from repairs that pass recheck. Adds reminders to future requests for the current text provider and model. Past sources and repair candidates are not stored. This does not train the AI model or guarantee that errors will not recur."))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            if let summary = model.jevLearningSummary {
                Text(summary).font(.system(size: 12)).textSelection(.enabled)
            }
            Text(L("현재 모델에 저장된 오류 유형: \(model.jevLearnedIssues.count)개", "Saved error categories for the current model: \(model.jevLearnedIssues.count)"))
                .font(.system(size: 11, weight: .medium))
            if !model.jevLearnedIssues.isEmpty {
                Text(model.jevLearnedIssues.map(\.title).joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text(L("이 Mac에 암호화해 보관합니다. 이 옵션을 끄면 새 학습과 다음 요청의 반영을 멈추고 기존 유형은 유지합니다. 아래 지우기는 모든 모델의 오류 유형만 삭제합니다. 기록을 끄거나 모두 삭제할 때도 유형을 지웁니다. 이름 표기의 전역 매핑은 직접 확인해 개인 사전에 저장하세요.", "Encrypted on this Mac. Turning this option off stops new learning and use in future requests while retaining saved categories. Clear below removes only error categories for all models. Turning off or clearing all history also clears these categories. Confirm name-spelling mappings yourself before saving them to the dictionary."))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            Button(L("학습한 오류 유형 지우기…", "Clear learned error patterns…"), role: .destructive) {
                confirmsClear = true
            }.disabled(AppLaunch.isPreview || model.startupState != .ready)
                .controlSize(.small)
        }
        .confirmationDialog(L("학습한 오류 유형을 모두 지울까요?", "Clear all learned error patterns?"), isPresented: $confirmsClear, titleVisibility: .visible) {
            Button(L("모든 모델의 오류 유형 지우기", "Clear patterns for all models"), role: .destructive) {
                Task { await model.clearJevFeedbackLearning() }
            }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("이 Mac에 저장한 오류 유형을 지우고 다음 문장 정리에 반영하지 않습니다. 개인 사전과 문장 기록은 유지합니다.", "Removes error categories saved on this Mac so they no longer inform future cleanup. Your dictionary and text history are preserved."))
        }
    }
}

struct JevAssistanceSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        DisclosureGroup(L("추가 도움 기능", "Additional assistance")) {
            VStack(alignment: .leading, spacing: 15) {
                option(L("중요한 변경을 세부적으로 검토", "Review important changes in more detail"),
                       value: $model.preferences.jevDetailedReviewEnabled,
                       detail: L("숫자·부정·조건·요청·이름의 변화를 구분합니다. 원문과 결과를 보내는 Jev 검토에 질문이 추가되어 비용이 늘 수 있습니다.", "Separates changes to numbers, negation, conditions, intent and names. Adds questions to the Jev review of the source and result, which may increase its cost."))
                option(L("단순한 받아쓰기의 검토 비용 줄이기", "Reduce review costs for simple dictation"),
                       value: $model.preferences.jevEconomyEnabled,
                       detail: L("비어 있지 않은 원문과 결과가 완전히 같고 표기 후보가 없을 때만 자동 Jev 검토를 생략합니다. 이 Mac에서 비교하며, 생략은 검토 통과를 뜻하지 않습니다. 직접 요청한 검토는 실행합니다.", "Skips automatic Jev review only when the nonempty source and result are identical and there are no spelling candidates. The comparison runs on this Mac. A skipped review is not a passed review. Explicit review requests still run."))
                option(L("주의 신호가 있으면 개선안 한 개 준비", "Prepare one alternative when review flags a concern"),
                       value: $model.preferences.jevAutomaticImprovementEnabled,
                       detail: L("말한 언어 유지 받아쓰기의 입력 전 보호에서 주의 신호가 있을 때 보조 모델로 별도 개선안을 준비하고 Jev로 검토합니다. 입력 전 교정·입력 후 검토에서는 현재 문장 모델의 교정 흐름을 사용해 같은 작업에서 두 번 생성하지 않습니다. 번역의 입력 전 검토는 자동 개선안을 만들지 않습니다. 생성과 검토 비용이 추가되며, 별도 개선안은 확인 후 복사합니다.", "For Keep spoken language dictation, prepares a separate alternative with the alternative model when Protect before typing flags a concern, then reviews it with Jev. Repair before typing and Review after typing use the current text model's repair flow without generating twice for the same job. Translation review before typing does not prepare an automatic alternative. Generation and review cost extra. Review and copy separate alternatives yourself."))
                option(L("모호한 수정 지시를 먼저 확인", "Check unclear editing instructions first"),
                       value: $model.preferences.jevClarifyEditsEnabled,
                       detail: L("선택한 원문과 음성 수정 지시를 Jev에 추가 전송합니다. 지시가 모호하면 자동 입력을 멈추고 구체적인 지시를 받습니다. 명확히 한 뒤 만드는 수정안도 확인 후 복사하며, 추가 검토·생성 비용이 발생할 수 있습니다.", "Also sends the selected source and spoken edit instruction to Jev. If the instruction is unclear, pauses automatic typing and asks for a specific instruction. The resulting edit is available to review and copy. Extra review and generation charges may apply."))
                option(L("헷갈릴 수 있는 음성을 한 번 더 인식", "Try another transcription for potentially confusing speech"),
                       value: $model.preferences.jevReRecognitionEnabled,
                       detail: L("지원되는 받아쓰기에서 확인이 필요한 표현을 발견하면 같은 녹음을 Groq 또는 OpenAI 음성 인식에 한 번 더 보내고 두 인식문을 Jev로 비교합니다. 음성 인식·검토 비용이 추가됩니다. 더 나은 인식문인지 직접 확인하며 자동 교체하지 않습니다.", "For supported dictation, sends the same recording once more to Groq or OpenAI when a phrase needs checking, then compares both transcripts with Jev. Speech recognition and review cost extra. You decide whether the alternative is better; it never replaces the result automatically."))
                Text(L("자동 문장 검토 모드는 위에서 별도로 선택합니다. 기능을 켜도 검토 결과가 정확하다는 보장은 없으며, 각 기능에서 필요한 내용만 추가 전송합니다.", "Choose the automatic text review mode above separately. These features do not guarantee accuracy. Each sends only the additional content described here."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }.padding(.top, 10)
        }.font(.system(size: 12))
    }

    private func option(_ title: String, value: Binding<Bool>, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(title, isOn: value)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
        }
    }
}

struct JevNameCatalogView: View {
    @Bindable var model: AppModel
    @State private var name = ""
    @State private var validation: String?

    private var normalizedName: String? { Preferences.normalizedJevCatalogNames([name]).first }
    private var alreadyListed: Bool {
        guard let normalizedName else { return false }
        return model.preferences.jevNameCatalog.contains { $0.caseInsensitiveCompare(normalizedName) == .orderedSame }
    }
    private var canAdd: Bool {
        normalizedName != nil && !alreadyListed && model.preferences.jevNameCatalog.count < 64
            && model.startupState == .ready && !AppLaunch.isPreview
    }

    var body: some View {
        Surface(L("앱·프로젝트 이름 후보", "App and project name candidates")) {
            Text(L("자주 쓰는 이름의 정확한 표기를 등록하세요. 문장 검토에서 ‘이름 후보 찾기’를 실행할 때 이 목록을 참고하며, 사전 매핑은 제안을 확인한 뒤 따로 저장합니다.", "Add the exact spellings of names you use. Find name candidates in a text review uses this list. Dictionary mappings are saved separately after you confirm a suggestion."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            HStack {
                TextField(L("예: OpenRouter", "Example: OpenRouter"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if canAdd { addName() } }
                    .onChange(of: name) { _, _ in validation = nil }
                Button(L("이름 추가", "Add name"), action: addName).disabled(!canAdd)
                Button(L("앱 선택…", "Choose an app…"), action: chooseApp)
                    .disabled(AppLaunch.isPreview || model.startupState != .ready)
            }
            if let validation {
                Text(validation).font(.system(size: 11)).foregroundStyle(.secondary)
            } else if alreadyListed {
                Text(L("이미 등록된 이름입니다.", "This name is already listed.")).font(.system(size: 11)).foregroundStyle(.secondary)
            } else if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && normalizedName == nil {
                Text(L("문자·숫자를 포함한 2~100자 이름을 입력해 주세요. 공백과 . + _ - ( ) &를 사용할 수 있으며, 줄바꿈·URL은 제외해 주세요.", "Enter a 2–100 character name containing letters or numbers. Spaces and . + _ - ( ) & are allowed; line breaks and URLs are not."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(L("최대 64개 · 이름마다 2~100자. 앱 선택은 이름을 입력란에 가져올 뿐이며 ‘이름 추가’를 눌러야 등록합니다. 설치된 앱 목록을 자동 수집하거나 전송하지 않습니다.", "Up to 64 names, 2–100 characters each. Choosing an app only fills the field; select Add name to register it. The installed-app list is never collected or sent automatically."))
                .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            if !model.preferences.jevNameCatalog.isEmpty {
                DisclosureGroup(L("등록된 이름 \(model.preferences.jevNameCatalog.count)개", "\(model.preferences.jevNameCatalog.count) registered names")) {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(model.preferences.jevNameCatalog, id: \.self) { value in
                            HStack {
                                Text(value).textSelection(.enabled)
                                Spacer()
                                Button(role: .destructive) { model.removeJevCatalogName(value) } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(L("\(value) 이름 후보 삭제", "Remove \(value) from name candidates"))
                                .disabled(AppLaunch.isPreview)
                            }
                        }
                    }.padding(.top, 8)
                }.font(.system(size: 12))
            }
        }
    }

    private func addName() {
        guard canAdd, let normalizedName else { return }
        model.addJevCatalogName(normalizedName)
        if model.preferences.jevNameCatalog.contains(normalizedName) {
            name = ""; validation = L("이름 후보를 추가했습니다. 문장 검토에서 사용할 수 있습니다.", "Name added. It is available when you review text.")
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = L("이름 후보로 등록할 앱 선택", "Choose an app name to register")
        panel.prompt = L("이름 가져오기", "Use name")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        name = url.deletingPathExtension().lastPathComponent
        validation = L("표기를 확인한 뒤 ‘이름 추가’를 누르세요.", "Check the spelling, then select Add name.")
    }
}

struct JevNameDiscoveryButton: View {
    @Bindable var model: AppModel
    let target: JevReviewTarget
    @State private var confirms = false
    @State private var approvedIdentity = ""
    private var identity: String {
        "\(target.id)|\(model.preferences.decisionProvider.rawValue)|\(model.preferences.jevNameCatalog.joined(separator: "\n"))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(model.jevNameDiscoveryInProgress ? L("이름 후보 확인 중…", "Checking name candidates…") : L("등록한 이름에서 표기 찾기…", "Find spellings among registered names…"), systemImage: "character.magnify") {
                approvedIdentity = identity; confirms = true
            }
            .disabled(model.preferences.jevNameCatalog.isEmpty || model.isBusy || model.manualDecisionReviewInProgress
                      || model.jevNameDiscoveryInProgress || model.jevWorkflowInProgress || model.decisionDictionaryOperationInProgress)
            if model.preferences.jevNameCatalog.isEmpty {
                Button(L("앱·프로젝트 이름 후보 등록", "Add app and project name candidates")) { model.page = .dictionary }
                    .buttonStyle(.borderless)
            }
            if model.decisionReviewTarget?.id == target.id, let status = model.jevNameDiscoveryStatus {
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .confirmationDialog(L("이 문장의 이름 표기를 찾을까요?", "Find name spellings in this text?"), isPresented: $confirms, titleVisibility: .visible) {
            Button(L("전송하고 이름 찾기", "Send and find names")) {
                guard approvedIdentity == identity else { return }
                model.discoverJevNames(for: target)
            }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("이 문장의 원문과 결과, 직접 등록한 이름 후보를 \(model.preferences.decisionProvider.displayName)에 보내 문맥에 맞는 표기를 검토합니다. API 비용이 발생할 수 있습니다. 제안은 자동 적용하거나 사전에 자동 저장하지 않습니다.", "Sends this text's source and result, with name candidates you registered, to \(model.preferences.decisionProvider.displayName) to review spellings in context. API charges may apply. Suggestions are neither applied nor saved to the dictionary automatically."))
        }
        .onChange(of: identity) { _, _ in confirms = false }
    }
}

struct JevAssistanceResultsView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let clarification = model.jevEditClarification {
            JevEditClarificationView(model: model).id(clarification.id)
        }
        if let recognition = model.jevReRecognition {
            JevReRecognitionView(model: model).id(recognition.id)
        }
    }
}

private struct JevEditClarificationView: View {
    @Bindable var model: AppModel
    @State private var instruction = ""
    @State private var confirms = false
    @State private var approvedInstruction = ""
    @State private var approvedConnection = ""
    private var connection: String { "\(model.jevEditClarification?.id.uuidString ?? "")|\(model.preferences.effectiveTextProvider.rawValue)|\(model.preferences.textModel)|\(model.preferences.decisionProvider.rawValue)" }

    var body: some View {
        if let value = model.jevEditClarification {
            Surface(L("수정 지시를 확인해 주세요", "Clarify your editing instruction")) {
                Text(L("선택한 글을 바로 바꾸지 않았습니다. 바꿀 부분과 원하는 결과를 구체적으로 알려 주세요.", "The selected text has not been replaced. Describe what to change and the result you want."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                DisclosureGroup(L("원문과 처음 지시 보기", "View the source and initial instruction")) {
                    assistanceText(L("선택한 원문", "Selected source"), value.original)
                    assistanceText(L("처음 수정 지시", "Initial editing instruction"), value.instruction)
                }.font(.system(size: 12))
                if let assessment = value.assessment {
                    Text(JevAssistancePresentation.editAssessment(assessment.choice))
                        .font(.system(size: 12, weight: .medium))
                }
                TextField(L("예: 날짜는 그대로 두고 마지막 문장만 짧게 바꿔 주세요", "Example: Keep the dates and shorten only the last sentence"), text: $instruction, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...5)
                    .disabled(value.isProcessing)
                Text(L("새 지시와 선택한 원문을 현재 문장 제공자와 Jev 검토에 전송합니다. API 비용이 추가될 수 있습니다. 만든 수정안은 확인한 뒤 직접 복사합니다.", "Sends the new instruction and selected source to your current text provider and Jev review. Additional API charges may apply. Review the resulting edit and copy it yourself."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                HStack {
                    if value.isProcessing { ProgressView().controlSize(.small) }
                    Button(L("수정안 만들기…", "Create an edit…")) {
                        approvedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                        approvedConnection = connection; confirms = true
                    }.disabled(value.isProcessing || model.isBusy || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(value.isProcessing ? L("취소", "Cancel") : L("닫기", "Dismiss")) { model.dismissJevEditClarification() }
                }
                if let status = value.status { Text(status).font(.system(size: 12)).textSelection(.enabled) }
                if let output = value.output {
                    assistanceText(L("새 수정안", "New edit"), output)
                    Button(L("수정안 복사", "Copy edit"), systemImage: "doc.on.doc") { model.copyJevClarifiedEdit() }
                        .disabled(value.isProcessing || output.isEmpty)
                }
            }
            .onAppear { instruction = value.instruction }
            .confirmationDialog(L("이 지시로 수정안을 만들까요?", "Create an edit with this instruction?"), isPresented: $confirms, titleVisibility: .visible) {
                Button(L("전송하고 수정안 만들기", "Send and create edit")) {
                    guard approvedConnection == connection else { return }
                    model.resolveJevEditClarification(instruction: approvedInstruction)
                }
                Button(L("취소", "Cancel"), role: .cancel) {}
            } message: {
                Text(L("지시: \(approvedInstruction)\n\n원문과 이 지시를 \(model.preferences.effectiveTextProvider.displayName) 및 \(model.preferences.decisionProvider.displayName)에 전송합니다. 추가 비용이 발생할 수 있으며 자동 입력하지 않습니다.", "Instruction: \(approvedInstruction)\n\nSends the source and this instruction to \(model.preferences.effectiveTextProvider.displayName) and \(model.preferences.decisionProvider.displayName). Extra charges may apply. No text is entered automatically."))
            }
            .onChange(of: connection) { _, _ in confirms = false }
        }
    }
}

private struct JevReRecognitionView: View {
    @Bindable var model: AppModel
    @State private var confirms = false
    @State private var approvedConnection = ""
    private var connection: String { "\(model.jevReRecognition?.id.uuidString ?? "")|\(model.preferences.effectiveTextProvider.rawValue)|\(model.preferences.textModel)|\(model.preferences.decisionProvider.rawValue)" }

    var body: some View {
        if let value = model.jevReRecognition {
            Surface(L("두 인식문을 비교해 주세요", "Compare both transcripts")) {
                Text(L("다른 음성 인식 결과가 더 정확하다는 뜻은 아닙니다. 실제로 말한 내용과 비교한 뒤 사용할 결과를 선택하세요.", "A second transcription is not necessarily more accurate. Compare it with what you said before choosing a result."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                assistanceText(L("처음 인식한 내용", "Original transcript"), value.original)
                if let alternative = value.alternative { assistanceText(L("다시 인식한 내용", "Alternative transcript"), alternative) }
                if let assessment = value.assessment {
                    Text(JevAssistancePresentation.transcriptAssessment(assessment.choice))
                        .font(.system(size: 12, weight: .medium))
                }
                if let status = value.status { Text(status).font(.system(size: 12)).textSelection(.enabled) }
                HStack {
                    if value.isProcessing { ProgressView().controlSize(.small) }
                    Button(L("다른 인식으로 문장 정리…", "Clean up the alternative transcript…")) {
                        approvedConnection = connection; confirms = true
                    }.disabled(value.isProcessing || model.isBusy || value.alternative?.isEmpty != false)
                    Button(value.isProcessing ? L("취소", "Cancel") : L("닫기", "Dismiss")) { model.dismissJevReRecognition() }
                }
                if let output = value.output { assistanceText(L("다른 인식의 정리 결과", "Cleaned alternative"), output) }
                Button(value.output == nil ? L("다른 인식문 복사", "Copy alternative transcript") : L("다른 인식의 정리 결과 복사", "Copy cleaned alternative"), systemImage: "doc.on.doc") {
                    model.copyJevTranscriptAlternative()
                }.disabled(value.isProcessing || (value.output ?? value.alternative ?? "").isEmpty)
                Text(L("처음 문장 정리 결과는 ‘최근 결과’에서 복사할 수 있습니다. 다른 인식으로 문장 정리를 요청하면 해당 글을 현재 문장 제공자와 Jev에 전송하며 비용이 추가될 수 있습니다. 결과는 자동 교체하지 않습니다.", "Copy the original cleaned text from Latest result. Cleaning up the alternative sends its text to your current text provider and Jev and may cost extra. It never replaces the original result automatically."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
            .confirmationDialog(L("다른 인식문을 정리할까요?", "Clean up the alternative transcript?"), isPresented: $confirms, titleVisibility: .visible) {
                Button(L("전송하고 문장 정리", "Send and clean up")) {
                    guard approvedConnection == connection else { return }
                    model.processJevTranscriptAlternative()
                }
                Button(L("취소", "Cancel"), role: .cancel) {}
            } message: {
                Text(L("다시 인식한 내용과 사전 힌트를 \(model.preferences.effectiveTextProvider.displayName)에 보내 정리하고 \(model.preferences.decisionProvider.displayName)에서 검토합니다. 추가 비용이 발생할 수 있으며 확인한 결과만 직접 복사합니다.", "Sends the alternative transcript and dictionary hints to \(model.preferences.effectiveTextProvider.displayName) for cleanup and reviews it with \(model.preferences.decisionProvider.displayName). Extra charges may apply. Review the result and copy it yourself."))
            }
            .onChange(of: connection) { _, _ in confirms = false }
        }
    }
}

private func assistanceText(_ title: String, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        Text(text).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled)
    }.frame(maxWidth: .infinity, alignment: .leading)
}

enum JevAssistancePresentation {
    static func editAssessment(_ choice: DecisionEditChoice) -> String {
        switch choice {
        case .clear: L("지시가 구체적으로 보입니다. 수정안을 확인해 주세요.", "The instruction appears specific. Review the resulting edit.")
        case .ambiguous: L("바꿀 부분이나 원하는 결과가 모호합니다.", "What to change or the intended result is unclear.")
        case .noApplicableEdit: L("원문에 적용할 수정 지시를 찾지 못했습니다.", "No applicable editing instruction was found for this source.")
        }
    }

    static func transcriptAssessment(_ choice: DecisionTranscriptChoice) -> String {
        switch choice {
        case .equivalent: L("두 인식문은 비슷한 뜻으로 보입니다.", "The transcripts appear to have similar meanings.")
        case .meaningfulDifference: L("뜻이 달라질 수 있는 차이가 있습니다. 실제 발화를 확인해 주세요.", "A difference may change the meaning. Compare it with what you said.")
        case .uncertain: L("어느 인식문을 사용할지 직접 확인이 필요합니다.", "Review both transcripts to decide which one to use.")
        }
    }
}
