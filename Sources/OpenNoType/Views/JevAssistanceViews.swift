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
        Surface {
            HStack(spacing: 4) {
                Text(L("등록한 이름", "Registered names")).font(AppTypography.sectionTitle)
                OptionHelp(title: L("앱·프로젝트 이름 후보", "App and project name candidates"), message: nameHelp)
                Spacer()
                Text("\(model.preferences.jevNameCatalog.count) / 64").font(AppTypography.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField(L("예: OpenRouter", "Example: OpenRouter"), text: $name)
                    .textFieldStyle(.roundedBorder).frame(minHeight: AppLayout.controlHeight)
                    .accessibilityLabel(L("등록할 이름 후보", "Name candidate to register"))
                    .onSubmit { if canAdd { addName() } }
                    .onChange(of: name) { _, _ in validation = nil }
                Button(L("이름 추가", "Add name"), action: addName).disabled(!canAdd)
                    .buttonStyle(AppActionButtonStyle(primary: true))
                Button(L("앱 선택…", "Choose an app…"), action: chooseApp)
                    .disabled(AppLaunch.isPreview || model.startupState != .ready)
            }
            if let validation {
                Text(validation).font(AppTypography.caption).foregroundStyle(.secondary)
            } else if alreadyListed {
                Text(L("이미 등록된 이름입니다.", "This name is already listed.")).font(AppTypography.caption).foregroundStyle(.secondary)
            } else if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && normalizedName == nil {
                Text(L("문자·숫자를 포함한 2~100자 이름을 입력해 주세요. 공백과 . + _ - ( ) &를 사용할 수 있으며, 줄바꿈·URL은 제외해 주세요.", "Enter a 2–100 character name containing letters or numbers. Spaces and . + _ - ( ) & are allowed; line breaks and URLs are not."))
                    .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
            }
            if model.preferences.jevNameCatalog.isEmpty {
                Text(L("아직 등록한 이름이 없습니다.", "No registered names yet."))
                    .font(AppTypography.body).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.preferences.jevNameCatalog, id: \.self) { value in
                        HStack(spacing: 8) {
                            Text(value).font(AppTypography.body).textSelection(.enabled)
                            Spacer()
                            Button(role: .destructive) { model.removeJevCatalogName(value) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless).frame(width: AppLayout.controlHeight, height: AppLayout.controlHeight)
                            .accessibilityLabel(L("\(value) 이름 후보 삭제", "Remove \(value) from name candidates"))
                            .disabled(AppLaunch.isPreview)
                        }.frame(minHeight: AppLayout.rowHeight)
                        if value != model.preferences.jevNameCatalog.last { Divider() }
                    }
                }
            }
        }
    }

    private var nameHelp: String {
        L("자주 쓰는 이름의 정확한 표기를 등록합니다. 문장 검토에서 이름 찾기를 직접 요청할 때 이 목록을 참고하며, 제안은 확인 없이 적용하거나 사전에 저장하지 않습니다.\n\n최대 64개, 이름마다 문자·숫자를 포함한 2~100자입니다. 앱 선택은 이름을 입력란에 가져올 뿐이며 ‘이름 추가’를 눌러야 등록합니다. 설치 앱 목록을 자동 수집하거나 전송하지 않습니다. 사전의 인식 표기→원하는 표기 매핑과 별개입니다.", "Register exact spellings of frequently used names. A name search you explicitly request during a review uses this catalog; suggestions are not applied or saved to the dictionary without confirmation.\n\nUp to 64 names, each 2–100 characters containing letters or numbers. Choosing an app only fills the field; select Add name to register it. The installed-app list is never collected or sent automatically. This catalog is separate from spoken-to-written dictionary mappings.")
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Button(model.jevNameDiscoveryInProgress ? L("이름 후보 확인 중…", "Checking name candidates…") : L("등록한 이름에서 표기 찾기…", "Find spellings among registered names…"), systemImage: "character.magnify") {
                    approvedIdentity = identity; confirms = true
                }
                .disabled(model.preferences.jevNameCatalog.isEmpty || model.isBusy || model.manualDecisionReviewInProgress
                          || model.jevNameDiscoveryInProgress || model.jevWorkflowInProgress || model.decisionDictionaryOperationInProgress)
                OptionHelp(title: L("등록 이름으로 표기 찾기", "Find spellings among registered names"), message: L("현재 문장의 원문·결과와 직접 등록한 이름 후보만 확인 후 전송합니다. 설치 앱은 자동 수집하지 않으며 제안을 자동 적용하거나 사전에 자동 저장하지 않습니다.", "Sends the current source, result and manually registered name candidates after confirmation. Installed apps are not collected automatically, and suggestions are neither automatically applied nor saved."))
            }
            Text(L("원문·결과·이름 후보 전송 · 추가 API 비용", "Source, result and name candidates sent · Additional API cost"))
                .font(AppTypography.caption).foregroundStyle(.secondary)
            if model.preferences.jevNameCatalog.isEmpty {
                Button(L("앱·프로젝트 이름 후보 등록", "Add app and project name candidates")) { model.dictionarySection = .names; model.page = .dictionary }
                    .buttonStyle(.borderless)
            }
            if model.decisionReviewTarget?.id == target.id, let status = model.jevNameDiscoveryStatus {
                Text(status).font(AppTypography.caption).foregroundStyle(.secondary).textSelection(.enabled)
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
                Text(L("선택한 글을 유지했습니다. 새 수정 지시를 확인해 주세요.", "The selected text is unchanged. Confirm your new editing instruction."))
                    .font(AppTypography.caption).foregroundStyle(.secondary)
                DisclosureGroup(L("원문과 처음 지시 보기", "View the source and initial instruction")) {
                    assistanceText(L("선택한 원문", "Selected source"), value.original)
                    assistanceText(L("처음 수정 지시", "Initial editing instruction"), value.instruction)
                }.font(AppTypography.caption)
                if let assessment = value.assessment {
                    Text(JevAssistancePresentation.editAssessment(assessment.choice))
                        .font(AppTypography.caption.weight(.medium))
                }
                TextField(L("예: 날짜는 그대로 두고 마지막 문장만 짧게 바꿔 주세요", "Example: Keep the dates and shorten only the last sentence"), text: $instruction, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...5)
                    .disabled(value.isProcessing)
                HStack(spacing: 4) {
                    Text(L("원문·새 지시 추가 전송 · API 비용 · 결과는 복사용", "Source and new instruction sent · API cost · Result to copy"))
                        .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                    OptionHelp(title: L("수정안 만들기", "Create an edit"), message: L("새 지시와 선택한 원문을 현재 문장 제공자와 Jev 검토에 전송합니다. API 비용이 추가될 수 있습니다. 만든 수정안은 확인한 뒤 직접 복사하며 자동 입력하지 않습니다.", "Sends the new instruction and selected source to your current text provider and Jev review. Additional API charges may apply. Review the edit and copy it yourself; it is not typed automatically."))
                }
                HStack {
                    if value.isProcessing { ProgressView().controlSize(.small) }
                    Button(L("수정안 만들기…", "Create an edit…")) {
                        approvedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                        approvedConnection = connection; confirms = true
                    }.disabled(value.isProcessing || model.isBusy || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(value.isProcessing ? L("취소", "Cancel") : L("닫기", "Dismiss")) { model.dismissJevEditClarification() }
                }
                if let status = value.status { Text(status).font(AppTypography.caption).textSelection(.enabled) }
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
                OptionHelpLabel(L("다른 인식문 비교", "Comparing transcripts"), help: L("다른 음성 인식 결과가 더 정확하다는 뜻은 아닙니다. 실제로 말한 내용과 비교한 뒤 사용할 결과를 선택하세요.", "A second transcription is not necessarily more accurate. Compare it with what you said before choosing a result."))
                if let alternative = value.alternative {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: AppLayout.panelSpacing) {
                            assistanceText(L("처음 인식한 내용", "Original transcript"), value.original).frame(minWidth: 220)
                            assistanceText(L("다시 인식한 내용", "Alternative transcript"), alternative).frame(minWidth: 220)
                        }
                        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
                            assistanceText(L("처음 인식한 내용", "Original transcript"), value.original)
                            assistanceText(L("다시 인식한 내용", "Alternative transcript"), alternative)
                        }
                    }
                } else { assistanceText(L("처음 인식한 내용", "Original transcript"), value.original) }
                if let assessment = value.assessment {
                    Text(JevAssistancePresentation.transcriptAssessment(assessment.choice))
                        .font(AppTypography.caption.weight(.medium))
                }
                if let status = value.status { Text(status).font(AppTypography.caption).textSelection(.enabled) }
                Text(L("다른 인식문 정리 · 추가 API 비용 · 자동 교체 없음", "Alternative cleanup · Additional API cost · No automatic replacement"))
                    .font(AppTypography.caption).foregroundStyle(.secondary)
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
                OptionHelpLabel(L("다른 인식문 사용", "Using the alternative transcript"), help: L("처음 문장 정리 결과는 ‘최근 결과’에서 복사할 수 있습니다. 다른 인식으로 문장 정리를 요청하면 해당 글을 현재 문장 제공자와 Jev에 전송하며 비용이 추가될 수 있습니다. 결과는 자동 교체하지 않습니다.", "Copy the original cleaned text from Latest result. Cleaning up the alternative sends its text to your current text provider and Jev and may cost extra. It never replaces the original result automatically."))
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
        Text(title).font(AppTypography.caption.weight(.semibold)).foregroundStyle(.secondary)
        Text(text).font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
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
