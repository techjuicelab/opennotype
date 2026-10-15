import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OpenNoTypeCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var recordingHotkey: Int?
    @State private var eventMonitor: Any?
    @State private var writingProfileApps: [WritingProfileApp] = []
    @State private var detailHistory: [SettingsDetail] = []
    @State private var returningToDetail = false
    private var isEditable: Bool { !model.preferencesRecoveryRequired && !AppLaunch.isPreview }
    private var connectionsEditable: Bool { isEditable && model.startupState != .loading }
    private var canStartInputTest: Bool { isEditable && model.startupState == .ready && model.accessibilityAllowed && !model.isBusy }
    private var inputTestState: String? {
        if model.inputTestArmed { return L("입력창에서 받아쓰기 단축키를 누르세요", "Press the dictation shortcut in a text field") }
        if model.startupState == .loading { return L("앱 준비 중 · 잠시 기다려 주세요", "Preparing the app · Please wait") }
        if model.startupState == .failed { return L("앱 준비를 다시 시도한 뒤 실행하세요", "Retry app setup before testing") }
        if !model.accessibilityAllowed { return L("손쉬운 사용 권한 필요", "Accessibility permission needed") }
        return nil
    }
    private var reviewStatus: String {
        if model.preferences.usesFastDictation {
            return L("현재 미적용 · 바로 입력은 자동 검토를 생략합니다.", "Not applied · Direct input skips automatic review.")
        }
        if model.preferences.dictationOutputLanguage.isTranslation {
            return L("일반 받아쓰기 검토는 현재 미적용 · 번역 검토는 아래에서 별도로 설정합니다.", "Dictation review is not applied · Translation review is configured separately below.")
        }
        switch model.preferences.decisionReviewMode {
        case .off: return L("자동 검토 꺼짐", "Automatic review is off")
        case .observe: return model.jevReviewMayDelayInput
            ? L("재인식 설정으로 입력 전 대기 · 이후 검토는 입력한 글을 바꾸지 않습니다.", "Re-recognition may delay typing · Later review leaves typed text unchanged.")
            : L("입력 후 검토 · 이미 입력한 글은 바꾸지 않습니다.", "Review after typing · Text already entered stays unchanged.")
        case .protect: return L("위험 신호 시 보류 · 검토 실패·시간 초과 시 기존 결과 입력", "Concern holds input · Review failure or timeout uses the existing result")
        case .repair: return L("검토한 결과만 입력 · 검토 실패·미해결 오류 시 보류", "Only reviewed results are typed · Failed review or unresolved concerns hold input")
        }
    }
    private var shortcutActivationSummary: String {
        switch model.preferences.shortcutActivation {
        case .toggle: L("한 번 눌러 시작하고, 다시 눌러 종료합니다.", "Press once to start and again to stop.")
        case .hold: L("누르는 동안 녹음하고, 키를 떼면 종료합니다.", "Hold to record; release to stop.")
        case .holdOrToggle: L("짧게 누르면 계속 녹음하고, 길게 누르면 키를 뗄 때 종료합니다.", "Tap to keep recording, or hold and release to stop.")
        }
    }
    private var shortcutHelp: String {
        shortcutActivationSummary + "\n\n" + L("Option·Control·Command를 포함한 조합을 사용하세요. 다른 앱에서 프롬프트 단축키로 녹음하면 완성된 결과를 원래 입력창에 자동 입력합니다. 입력할 수 없으면 결과를 복사할 수 있습니다. 홈 녹음은 복사해 사용하고 재처리·원문 수정은 미리보기만 표시하며 자동 입력하지 않습니다. 프롬프트에는 받아쓰기 출력 언어와 앱별 작성 방식을 적용하지 않습니다.", "Use a combination that includes Option, Control, or Command. Recording with the prompt shortcut in another app types the finished result into the original text field; if typing is unavailable, you can copy it. Home recordings produce results to copy. Reprocessing and source edits show previews without automatic input. Dictation output language and app writing styles do not apply to prompts.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            AppPageHeader(model.settingsSection.title)
            Picker(L("설정 분류", "Settings category"), selection: Binding(get: { model.settingsSection }, set: { model.openSettings($0) })) {
                ForEach(SettingsSection.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            sectionContent
        }
        .onChange(of: model.settingsSection) { _, _ in stopHotkeyRecording() }
        .onChange(of: model.preferencesRecoveryRequired) { _, required in if required { stopHotkeyRecording() } }
        .onDisappear { stopHotkeyRecording() }
        .onChange(of: model.settingsDetail) { previous, current in
            if current == nil { detailHistory = []; returningToDetail = false }
            else if returningToDetail { returningToDetail = false }
            else if let previous, previous != current { detailHistory.append(previous) }
        }
        .sheet(item: $model.settingsDetail) { selected in
            if selected == .comparison {
                JevModelComparisonView(model: model)
            } else {
                SettingsDetailSheet(selected.title, backAction: detailHistory.isEmpty ? nil : returnToPreviousDetail) { detailContent(selected) }
            }
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch model.settingsSection {
        case .dictation: dictationSection
        case .input:
            VoiceInputOptionsView(model: model, showsProcessing: false)
            hotkeysSection
        case .connection: connectionSection
        case .privacy:
            retentionSection
            SettingsPanel(L("전송과 문맥", "Transmission and context")) {
                SettingsRow(L("현재 받아쓰기 전송", "Current dictation transfer"), help: transmissionHelp) {
                    Text(model.preferences.usesFastDictation ? L("외부 전송 없음", "No external transfer")
                         : model.preferences.needsLocalForDictation ? L("인식문 전송", "Transcript sent") : L("녹음·인식문 전송", "Audio and transcript sent"))
                        .font(AppTypography.caption)
                }
                SettingsRow(L("앱별 주변 문맥", "Context by app"), help: contextHelp,
                            state: model.preferences.allowedContextApps.isEmpty ? nil : L("허용한 앱의 주변 글 추가 전송", "Also sends context from allowed apps")) {
                    Text(L("\(model.preferences.allowedContextApps.count)개 앱", "\(model.preferences.allowedContextApps.count) apps")).font(AppTypography.caption)
                    Button(L("설정…", "Settings…")) { model.openSettings(SettingsDetail.context) }
                }
                SettingsRow(L("문장 검토의 추가 전송", "Additional text-review transfers"), help: reviewHelp,
                            state: model.preferences.decisionReviewMode == .off ? nil : reviewStatus) {
                    Button(L("검토 설정…", "Review settings…")) { model.openSettings(SettingsDetail.jev) }
                }
                SettingsRow(L("번역 다듬기의 추가 전송", "Additional translation-refinement transfers"), help: transmissionHelp,
                            state: model.preferences.translationRefinementEnabled ? L("추가 요청 1회 · 실패 시 보류", "1 extra request · Holds on failure") : nil) {
                    Button(L("받아쓰기 설정…", "Dictation settings…")) { model.openSettings(SettingsSection.dictation) }
                }
            }
            SettingsPanel(L("학습과 통계", "Learning and usage")) {
                learningRows
                SettingsRow(L("검토 오류 유형 학습", "Review error-pattern learning"), help: L("개인 사전과 별개로 해결한 오류 유형만 모델별로 암호화해 보관합니다. 과거 문장은 보관하지 않습니다.", "Stores only resolved error categories encrypted by model, independently of your dictionary. Past sentences are not retained.")) {
                    Button(L("학습 설정…", "Learning settings…")) { model.openSettings(SettingsDetail.learning) }
                }
                usagePrivacyRows
            }
        case .general:
            inputReadinessSection
            generalSection
            UpdateSettingsView(updater: .shared, isEditable: isEditable)
            SettingsPanel(L("정보", "Information")) {
                SettingsRow(L("모델·오픈소스 고지", "Models and open-source notices")) {
                    Button(L("라이선스", "Licenses")) { model.openSettings(SettingsDetail.licenses) }
                }
            }
        case .advanced: advancedSection
        }
    }

    private var dictationSection: some View {
        SettingsPanel {
            SettingsGroupHeading(L("입력 방식", "Input behavior"))
            VoiceInputOptionsView(model: model, showsRecording: false, embedded: true)
            DictationTranslationSettingsView(outputLanguage: $model.preferences.dictationOutputLanguage,
                                             isEditable: isEditable, embedded: true)
            SettingsRow(L("로컬 모델", "On-device model"), help: L("모델 선택·파일 다운로드·메모리 준비는 별개입니다. 다운로드만으로 인식 방식이 바뀌지 않습니다.", "Model selection, downloaded files, and memory readiness are separate. Downloading does not change the speech processing method.")) {
                Text(model.preferences.localSpeechModel.displayName).font(AppTypography.caption).lineLimit(1).truncationMode(.middle)
                Button(L("모델 보기", "View models")) { model.settingsDetail = nil; model.page = .voice }
            }
            Divider()
            SettingsGroupHeading(L("문장과 말투", "Wording and tone"))
            DictationExpressionSettingsView(expression: $model.preferences.dictationExpression,
                outputLanguage: model.preferences.dictationOutputLanguage, isFastDictation: model.preferences.usesFastDictation,
                isEditable: isEditable, embedded: true)
            SettingsRow(L("앱별 작성 방식", "Writing style by app"), help: profilesHelp,
                        state: model.preferences.usesFastDictation ? L("현재 미적용 · 빠른 로컬", "Paused · Quick dictation")
                        : model.preferences.dictationOutputLanguage.isTranslation ? L("앱별 말투만 번역에 적용", "Only app tone applies to translation") : nil) {
                Button(L("설정…", "Settings…")) { model.openSettings(SettingsDetail.profiles) }
            }
            Divider()
            SettingsGroupHeading(L("번역과 검토", "Translation and review"))
            translationRow
            TranslationRefinementSettingsView(isEnabled: $model.preferences.translationRefinementEnabled,
                reviewsBeforeTyping: model.preferences.translationProtectionEnabled && model.preferences.decisionReviewMode == .protect,
                isEditable: isEditable && model.startupState == .ready, embedded: true)
            SettingsRow(L("자동 문장 검토", "Automatic text review"), help: reviewHelp,
                        state: model.preferences.decisionReviewMode == .off && !model.preferences.usesFastDictation && !model.preferences.dictationOutputLanguage.isTranslation ? nil : reviewStatus) {
                Text(model.preferences.decisionReviewMode.title).font(AppTypography.caption).lineLimit(1)
                Button(L("설정…", "Settings…")) { model.openSettings(SettingsDetail.jev) }
            }
        }
    }

    private var translationRow: some View {
        SettingsRow(L("번역 단축키 언어", "Translation shortcut language"), help: L("별도 번역 단축키의 출력 언어입니다. 평소 받아쓰기의 출력 언어와 독립적으로 저장됩니다.", "Output language for the separate translation shortcut. Saved independently of your usual dictation language.")) {
            Picker(L("번역 단축키 언어", "Translation shortcut language"), selection: $model.preferences.targetLanguage) {
                Text(L("영어 · 미국식", "English · US")).tag("English (United States)")
                Text(L("영어 · 영국식", "English · UK")).tag("English (United Kingdom)")
                Text(L("한국어", "Korean")).tag("Korean")
                Text(L("일본어", "Japanese")).tag("Japanese")
                Text(L("중국어 · 간체", "Chinese · Simplified")).tag("Chinese (Simplified)")
                Text(L("중국어 · 번체", "Chinese · Traditional")).tag("Chinese (Traditional)")
            }.labelsHidden().frame(width: 240).disabled(!isEditable)
        }
    }

    private var hotkeysSection: some View {
        SettingsPanel(L("작업별 단축키", "Shortcuts by task")) {
            ForEach(Array(InputMode.allCases.enumerated()), id: \.element.id) { index, mode in
                SettingsRow(mode.title, help: shortcutHelp,
                            state: recordingHotkey == index ? L("새 조합을 누르세요 · Esc로 취소", "Press a new combination · Esc cancels") : nil) {
                    Button(recordingHotkey == index ? L("입력 대기…", "Waiting…") : model.hotkeyLabel(index: index)) { recordHotkey(index) }
                        .font(AppTypography.utility).frame(width: 240)
                        .accessibilityLabel(L("\(mode.title) 단축키 변경", "Change \(mode.title) shortcut"))
                        .accessibilityValue(model.hotkeyLabel(index: index)).disabled(!isEditable)
                }
            }
            ForEach(model.hotkeyConflicts, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").font(AppTypography.caption).foregroundStyle(.orange)
            }
            SettingsRow(L("다른 앱과 충돌", "Conflicts with other apps"), help: shortcutActivationSummary) {
                Button(L("충돌 확인", "Check conflicts")) { model.refreshHotkeyConflicts() }.disabled(!isEditable)
            }
        }.onAppear { model.refreshHotkeyConflicts() }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            SettingsPanel(L("음성 인식", "Speech recognition")) {
                SettingsRow(L("제공자", "Provider"), help: speechConnectionHelp,
                            state: model.preferences.usesFastDictation ? L("현재 받아쓰기는 빠른 로컬 · 연결 선택 유지", "Current dictation is quick on-device · Connection choice kept") : nil) {
                    Text(model.preferences.needsLocal ? L("이 Mac", "This Mac") : model.preferences.provider.displayName).font(AppTypography.body)
                }
                SettingsRow(L("키·모델", "Key and model"), help: keyHelp) {
                    connectionSummary(key: model.preferences.needsLocal ? model.localState.label : speechKeyState ?? L("API 키 저장됨", "API key saved"),
                                      modelName: model.preferences.needsLocal ? model.preferences.localSpeechModel.displayName : model.preferences.transcriptionModel)
                }
                SettingsRow(L("연결 설정", "Connection settings"), help: speechConnectionHelp) {
                    Button(L("연결 설정…", "Connection settings…")) { model.openSettings(SettingsDetail.speech) }
                }
            }
            SettingsPanel(L("문장 처리", "Text processing")) {
                SettingsRow(L("제공자", "Provider"), help: textConnectionHelp,
                            state: model.preferences.usesFastDictation ? L("현재 받아쓰기에는 미적용", "Not applied to current dictation") : nil) {
                    Text(model.preferences.effectiveTextProvider.displayName).font(AppTypography.body)
                }
                SettingsRow(L("키·모델", "Key and model"), help: keyHelp) {
                    connectionSummary(key: textKeyState ?? ((!model.preferences.needsLocal && model.preferences.effectiveTextProvider == model.preferences.provider)
                        ? L("음성 키 공유", "Shares speech key") : L("API 키 저장됨", "API key saved")), modelName: model.preferences.textModel)
                }
                SettingsRow(L("연결 설정", "Connection settings"), help: textConnectionHelp) {
                    Button(L("연결 설정…", "Connection settings…")) { model.openSettings(SettingsDetail.text) }
                }
            }
            SettingsPanel(L("문장 검토 · Jev", "Text review · Jev")) {
                SettingsRow(L("제공자", "Provider"), help: reviewConnectionHelp) {
                    Text(model.preferences.decisionProvider.displayName).font(AppTypography.body)
                }
                SettingsRow(L("키·모델", "Key and model"), help: keyHelp) {
                    connectionSummary(key: reviewConnectionKeySummary, modelName: model.preferences.decisionProvider.model)
                }
                SettingsRow(L("연결 설정", "Connection settings"), help: reviewConnectionHelp) {
                    Button(L("연결 설정…", "Connection settings…")) { model.openSettings(SettingsDetail.reviewConnection) }
                }
            }
        }
    }

    private func connectionSummary(key: String, modelName: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(key).font(AppTypography.caption).foregroundStyle(.secondary).lineLimit(2)
            Text(modelName).font(AppTypography.utility).lineLimit(1).truncationMode(.middle)
        }.accessibilityElement(children: .combine)
    }

    private var reviewConnectionKeySummary: String {
        if model.preferences.decisionProvider == .typeSafe { return decisionKeyState ?? L("API 키 저장됨", "API key saved") }
        if model.preferences.effectiveTextProvider != .openRouter { return L("문장 제공자 OpenRouter 필요", "Requires OpenRouter text provider") }
        return textKeyState ?? L("문장 OpenRouter 키 공유", "Shares the text OpenRouter key")
    }

    private var speechConnectionHelp: String { L("음성을 인식할 위치·제공자·API 키·모델을 설정합니다. 로컬 인식과 AI 문장 처리는 독립입니다. Anthropic은 로컬 인식이 필요하며, 빠른 로컬 받아쓰기의 적용 여부는 받아쓰기 설정에서 결정합니다. 로컬 모델 파일과 메모리는 음성 모델 화면에서 관리합니다.", "Configure the speech location, provider, API key, and model. Local speech and AI text processing are independent. Anthropic requires local speech. Quick dictation is selected in Dictation settings. Manage local model files and memory in Speech models.") }
    private var textConnectionHelp: String { L("받아쓰기 정리·번역·선택 수정의 제공자·API 키·모델을 설정합니다. 기존 키 공유 조건과 제공자별 모델 선택을 유지합니다. OpenRouter는 실제 공급자로 요청을 전달할 수 있으며 앱 구독과 API 비용은 별개입니다.", "Configure the provider, key, and model for cleanup, translation, and selected-text edits. Existing key-sharing rules and per-provider models are retained. OpenRouter may forward to a host, and app subscriptions are separate from API charges.") }
    private var reviewConnectionHelp: String { L("Jev 검토 서비스의 제공자·API 키·고정 검토 모델을 확인하고 연결을 시험합니다. 자동 검토 방식·번역 보호·보조 모델·도움 옵션은 받아쓰기 설정에서 따로 관리합니다. 검토 모델과 문장 개선안용 보조 모델은 서로 다릅니다.", "Configure the Jev service provider and key, inspect its fixed review model, and test the connection. Automatic review, translation protection, alternative models, and assistance are managed separately in Dictation settings. The review model differs from the model used to generate alternatives.") }

    private var speechKeyState: String? {
        if model.transcriptionKeyOperationInProgress { return L("Keychain 확인 중", "Checking Keychain") }
        if model.keyDraftIsChanged { return L("변경한 키 저장 필요", "Save the changed key") }
        return model.keySaved ? nil : L("API 키 저장 필요", "Save an API key")
    }
    private var textKeyState: String? {
        if !model.preferences.needsLocal && model.preferences.effectiveTextProvider == model.preferences.provider { return speechKeyState }
        if model.textKeyOperationInProgress { return L("Keychain 확인 중", "Checking Keychain") }
        if model.textKeyDraftIsChanged { return L("변경한 키 저장 필요", "Save the changed key") }
        return model.textKeySaved ? nil : L("API 키 저장 필요", "Save an API key")
    }

    private var speechConnection: some View {
        SettingsPanel(L("음성 인식 설정", "Speech connection settings")) {
            SettingsRow(L("인식 위치", "Speech processing"), help: speechConnectionHelp) {
                Picker(L("인식 위치", "Speech processing"), selection: Binding(get: { model.preferences.needsLocal }, set: { value in
                    guard connectionsEditable, model.preferences.provider != .anthropic else { return }
                    model.preferences.useLocalTranscription = value
                })) {
                    Text(L("온라인으로 인식", "Online recognition")).tag(false)
                    Text(L("이 Mac에서 인식", "On this Mac")).tag(true)
                }.labelsHidden().frame(width: 240).disabled(!connectionsEditable || model.preferences.provider == .anthropic)
                    .onChange(of: model.preferences.useLocalTranscription) { _, local in if !local { model.loadKey() } }
            }
            SettingsRow(L("제공자", "Provider"), help: speechConnectionHelp,
                        state: model.preferences.provider == .anthropic ? L("음성 인식은 이 Mac에서 처리", "Speech runs on this Mac") : nil) {
                Picker(L("음성 제공자", "Speech provider"), selection: $model.preferences.provider) {
                    ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
                }.labelsHidden().frame(width: 240).disabled(!connectionsEditable)
                    .onChange(of: model.preferences.provider) { _, _ in model.loadKey(); model.loadTextKey() }
            }
            if model.preferences.needsLocal {
                SettingsRow(L("로컬 모델", "On-device model"), help: speechConnectionHelp, state: model.localState.label) {
                    Button(L("모델 관리…", "Manage models…")) { model.settingsDetail = nil; model.page = .voice }
                }
            } else {
                SettingsRow(L("API 키", "API key"), help: keyHelp, state: speechKeyState) {
                    SecureField(L("음성 API 키", "Speech API key"), text: $model.apiKeyDraft).textFieldStyle(.roundedBorder)
                        .frame(width: 240).disabled(!connectionsEditable || model.transcriptionKeyOperationInProgress)
                }
                SettingsRow(L("키 적용", "Apply key"), help: keyHelp) {
                    Button(model.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.keySaved ? L("저장된 키 삭제", "Delete saved key") : L("Keychain에 저장", "Save to Keychain")) { model.saveKey() }
                        .disabled(!connectionsEditable || model.transcriptionKeyOperationInProgress || (model.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.keySaved))
                }
                if model.preferences.provider == .groq {
                    ProviderModelPicker(L("음성 모델", "Speech model"), selection: transcriptionModelBinding,
                                        choices: GroqModelChoices.transcription, isEnabled: connectionsEditable)
                    SettingsRow(L("Groq 연결 안내", "Groq setup guide")) {
                        Link(L("공식 안내", "Official guide"), destination: URL(string: "https://console.groq.com/docs/quickstart")!)
                    }
                } else {
                    SettingsRow(L("음성 모델", "Speech model"), help: L("모델 ID를 지정합니다. 제공자별 기존 값을 유지합니다.", "Set a model ID, keeping existing values by provider.")) {
                        TextField(L("모델 ID", "Model ID"), text: transcriptionModelBinding).textFieldStyle(.roundedBorder).frame(width: 240).disabled(!connectionsEditable)
                    }
                }
                SettingsRow(L("녹음 전송", "Audio transfer"), help: transmissionHelp) { Text(model.preferences.provider.displayName).font(AppTypography.caption) }
            }
        }
    }

    private var textConnection: some View {
        SettingsPanel(L("문장 처리 설정", "Text connection settings")) {
            SettingsRow(L("제공자", "Provider"), help: textConnectionHelp) {
                Picker(L("문장 제공자", "Text provider"), selection: textProviderBinding) {
                    ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
                }.labelsHidden().frame(width: 240).disabled(!connectionsEditable)
            }
            if model.preferences.needsLocal || model.preferences.effectiveTextProvider != model.preferences.provider {
                SettingsRow(L("API 키", "API key"), help: keyHelp, state: textKeyState) {
                    SecureField(L("문장 API 키", "Text API key"), text: $model.textAPIKeyDraft).textFieldStyle(.roundedBorder)
                        .frame(width: 240).disabled(!connectionsEditable || model.textKeyOperationInProgress)
                }
                SettingsRow(L("키 적용", "Apply key"), help: keyHelp) {
                    Button(model.textAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.textKeySaved ? L("저장된 키 삭제", "Delete saved key") : L("Keychain에 저장", "Save to Keychain")) { model.saveTextKey() }
                        .disabled(!connectionsEditable || model.textKeyOperationInProgress || (model.textAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.textKeySaved))
                }
            } else {
                SettingsRow(L("API 키", "API key"), help: keyHelp, state: speechKeyState) {
                    Button(L("공유 키 설정…", "Shared key settings…")) { model.openSettings(SettingsDetail.speech) }
                }
            }
            if model.preferences.effectiveTextProvider == .groq || model.preferences.effectiveTextProvider == .openRouter {
                ProviderModelPicker(L("문장 모델", "Text model"), selection: textModelBinding,
                    choices: ProviderModelChoice.textChoices(for: model.preferences.effectiveTextProvider), isEnabled: connectionsEditable)
                    .id(model.preferences.effectiveTextProvider.rawValue)
            } else {
                SettingsRow(L("문장 모델", "Text model"), help: L("모델 ID를 지정합니다. 변경값은 자동 저장되며 API 키 저장과 별개입니다.", "Set a model ID. Changes save automatically, separately from API keys.")) {
                    TextField(L("모델 ID", "Model ID"), text: textModelBinding).textFieldStyle(.roundedBorder).frame(width: 240).disabled(!connectionsEditable)
                }
            }
            SettingsRow(L("인식문·수정 요청 전송", "Transcript and edit requests"), help: transmissionHelp) { Text(model.preferences.effectiveTextProvider.displayName).font(AppTypography.caption) }
        }
    }

    private var reviewConnection: some View {
        SettingsPanel(L("문장 검토 연결", "Text review connection")) {
            SettingsRow(L("제공자", "Provider"), help: reviewConnectionHelp) {
                Picker(L("검토 서비스", "Review service"), selection: $model.preferences.decisionProvider) {
                    Text(L("OpenRouter 키 재사용", "Reuse OpenRouter key")).tag(DecisionProvider.openRouter)
                    Text(L("Jev API 직접 연결", "Direct Jev API")).tag(DecisionProvider.typeSafe)
                }.labelsHidden().frame(width: 240).disabled(!connectionsEditable)
                    .onChange(of: model.preferences.decisionProvider) { _, provider in if provider == .typeSafe { model.loadDecisionKey() } }
            }
            if model.preferences.decisionProvider == .typeSafe {
                SettingsRow(L("Jev API 키", "Jev API key"), help: keyHelp, state: decisionKeyState) {
                    SecureField(L("Jev API 키 · TypeSafe", "Jev API key · TypeSafe"), text: $model.decisionAPIKeyDraft)
                        .textFieldStyle(.roundedBorder).frame(width: 240).disabled(!connectionsEditable || model.decisionKeyOperationInProgress)
                }
                SettingsRow(L("키 적용", "Apply key"), help: keyHelp) {
                    Button(model.decisionAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.decisionKeySaved ? L("저장된 키 삭제", "Delete saved key") : L("Keychain에 저장", "Save to Keychain")) { model.saveDecisionKey() }
                        .disabled(!connectionsEditable || model.decisionKeyOperationInProgress || (model.decisionAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.decisionKeySaved))
                }
                SettingsRow(L("저장된 키 다시 확인", "Reload saved key"), help: keyHelp) {
                    Button(L("다시 확인", "Reload")) { model.loadDecisionKey(force: true) }.disabled(!connectionsEditable || model.decisionKeyOperationInProgress)
                }
            } else {
                SettingsRow(L("검토 API 키", "Review API key"), help: keyHelp,
                            state: model.preferences.effectiveTextProvider != .openRouter ? L("문장 제공자 OpenRouter 필요", "Requires OpenRouter text provider") : textKeyState) {
                    Button(L("공유 키 설정…", "Shared key settings…")) { model.openSettings(SettingsDetail.text) }
                }
            }
            SettingsRow(L("검토 모델", "Review model"), help: reviewConnectionHelp) {
                Text(model.preferences.decisionProvider.model).font(AppTypography.utility)
            }
            connectionTestRow
        }.onAppear {
            if !AppLaunch.isPreview && model.preferences.decisionProvider == .typeSafe { model.loadDecisionKey() }
        }
    }

    private var reviewPolicySection: some View {
        SettingsPanel(L("검토 방식", "Review behavior")) {
            SettingsRow(L("자동 검토", "Automatic review"), help: reviewHelp, state: reviewPolicyState) {
                Picker(L("자동 검토", "Automatic review"), selection: $model.preferences.decisionReviewMode) {
                    ForEach(DecisionReviewMode.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 240)
                    .disabled(!connectionsEditable || (model.preferences.decisionProvider == .openRouter && model.preferences.effectiveTextProvider != .openRouter))
            }
            if model.preferences.decisionProvider == .openRouter && model.preferences.effectiveTextProvider != .openRouter {
                SettingsRow(L("검토 연결 준비", "Prepare review connection"), help: reviewConnectionHelp) {
                    Button(L("연결 설정…", "Connection settings…")) { model.openSettings(SettingsDetail.reviewConnection) }
                }
            }
            SettingsRow(L("번역도 입력 전 검토", "Review translations before typing"), help: translationReviewHelp,
                        state: model.preferences.decisionReviewMode != .protect ? L("현재 미적용 · 입력 전 보호에서 사용", "Paused · Protect before typing only") : model.preferences.translationProtectionEnabled ? L("추가 전송·비용 · 검토 실패 시 보류", "Extra transfer and charges · Holds on review failure") : nil) {
                Toggle(L("번역도 입력 전 검토", "Review translations before typing"), isOn: $model.preferences.translationProtectionEnabled)
                    .labelsHidden().toggleStyle(.switch).disabled(!connectionsEditable || model.preferences.decisionReviewMode != .protect)
            }
            SettingsRow(L("오류 유형 학습", "Error-pattern learning"), help: L("정해진 오류 유형만 모델별로 암호화 저장하며 개인 사전과 별개입니다.", "Stores only predefined error categories encrypted by model, independently of the dictionary.")) {
                Text(model.preferences.jevFeedbackLearningEnabled ? L("켜짐", "On") : L("꺼짐", "Off")).font(AppTypography.caption)
                Button(L("학습 설정…", "Learning settings…")) { model.openSettings(SettingsDetail.learning) }
            }
        }
    }

    private var reviewPolicyState: String? {
        if model.preferences.decisionProvider == .openRouter && model.preferences.effectiveTextProvider != .openRouter {
            return L("검토 연결 설정 필요 · 문장 제공자 OpenRouter 필요", "Review connection setup required · Text provider must be OpenRouter")
        }
        return model.preferences.decisionReviewMode == .off && !model.preferences.usesFastDictation && !model.preferences.dictationOutputLanguage.isTranslation ? nil : reviewStatus
    }

    private var decisionKeyState: String? {
        if model.decisionKeyOperationInProgress { return L("TypeSafe 키 준비 중 · 필요 시 Keychain 승인", "Loading TypeSafe key · Approve Keychain if prompted") }
        if let status = model.decisionKeyStatus { return status }
        if model.decisionKeyDraftIsChanged { return L("변경한 키 저장 필요", "Save the changed key") }
        return model.decisionKeySaved ? nil : L("키 필요 · 입력 전 교정·번역 보호는 미준비 시 보류", "Key needed · Repair and translation protection hold without it")
    }

    private var decisionTools: some View {
        SettingsPanel(L("검토 도움 설정", "Review assistance settings")) {
            ProviderModelPicker(L("보조 모델", "Alternative model"), selection: Binding(get: { model.preferences.improvementModel }, set: {
                if connectionsEditable { model.preferences.improvementModels[model.preferences.effectiveTextProvider.rawValue] = $0 }
            }), choices: ProviderModelChoice.textChoices(for: model.preferences.effectiveTextProvider), isEnabled: connectionsEditable)
            SettingsRow(L("보조 모델 기본값", "Alternative model default"), help: L("직접 개선안과 입력 전 보호의 별도 개선안에 사용합니다. 입력 전 교정·입력 후 검토는 현재 문장 모델을 사용합니다. 제공자별 값을 지우면 현재 문장 모델을 재사용합니다.", "Used for explicit alternatives and separate alternatives in Protect. Repair and Observe use the current text model. Clearing this provider's override reuses the current text model.")) {
                Button(L("현재 문장 모델과 같게", "Use current text model")) { model.preferences.improvementModels.removeValue(forKey: model.preferences.effectiveTextProvider.rawValue) }.disabled(!connectionsEditable)
            }
            SettingsRow(L("추가 도움 기능", "Additional assistance"), help: reviewHelp) { Button(L("설정…", "Settings…")) { model.openSettings(SettingsDetail.assistance) } }
        }
    }

    private var connectionTestRow: some View {
        SettingsRow(L("Jev 연결 테스트", "Test Jev connection"), help: L("고정 합성 문장으로 연결과 저장된 키를 확인합니다. 녹음·자동 입력·문장 기록 저장 없이 API 비용과 사용량 기록이 발생할 수 있습니다. 자동 검토 OFF에서도 실행할 수 있습니다.", "Tests the connection and saved key with fixed synthetic text. No audio, automatic typing, or text history. API charges and usage records may apply, even with automatic review off."), state: model.decisionConnectionTestStatus ?? L("실행 시 추가 요청·비용", "Running adds a request and charges")) {
            Button(model.decisionConnectionTestInProgress ? L("확인 중…", "Testing…") : L("연결 테스트", "Test connection")) { model.testDecisionConnection() }
                .disabled(!connectionsEditable || model.isBusy || model.keyOperationInProgress)
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            SettingsPanel(L("실험 기능", "Experiments")) {
                LocalPreviewSettingsRow(model: model)
                SettingsRow(L("내 목소리 구분", "Recognize my voice"), help: LocalSpeakerRecognizer.limitation,
                            state: L("실험 · 실사용 성능 미검증", "Experimental · Real-world performance unverified")) {
                    Button(L("설정…", "Settings…")) { model.openSettings(SettingsDetail.speaker) }
                }
            }
            SettingsPanel(L("모델 비교", "Model comparison")) {
                SettingsRow(L("음성 모델 비교", "Speech model comparison"), help: L("내려받은 로컬 모델로 같은 음성을 순차 비교합니다. API 요청이나 새 모델 다운로드는 하지 않습니다.", "Sequentially compares the same audio with downloaded local models, without API requests or new downloads.")) {
                    Button(L("비교 도구 열기…", "Open comparison tool…")) { model.openSettings(SettingsDetail.speechComparison) }
                }
                SettingsRow(L("문장 모델 비교", "Text model comparison"), help: L("승인한 문장으로 비교하며 전송·비용 확인과 직접 모델 적용을 유지합니다.", "Compares approved text with transfer and cost confirmation and manual model application."),
                            state: L("실행 시 추가 API 요청·비용", "Running adds API requests and charges")) {
                    Button(L("비교 도구 열기…", "Open comparison tool…")) { model.openSettings(SettingsDetail.comparison) }.disabled(!connectionsEditable)
                }
            }
            SettingsPanel(L("진단", "Diagnostics")) {
                SettingsRow(L("최근 처리 진단", "Recent processing diagnostics"), help: L("최근 입력 확인 로그와 처리 단계 시간만 조회합니다. 실제 입력 테스트는 앱 설정에서 따로 실행합니다.", "Reads the recent input verification log and processing times. Run the typing test separately in App settings.")) {
                    Button(L("진단 보기…", "View diagnostics…")) { model.openSettings(SettingsDetail.diagnostics) }
                }
            }
        }
    }

    private var retentionSection: some View {
        SettingsPanel(L("기록과 보관", "History and retention")) {
            SettingsRow(L("처리 결과 기록", "Save processing history"), help: L("받아쓰기·번역·선택 수정과 제공한 프롬프트를 암호화 저장합니다. 중간 초안·차단/오류 프롬프트는 저장하지 않습니다. 끄면 진행 중 Jev 검토·진단·학습한 오류 유형을 지우며 기존 텍스트 기록은 보관 기간을 따릅니다. 개인 사전은 유지됩니다.", "Encrypts dictation, translation, edits, and delivered prompts. Does not save intermediate, blocked, or failed prompts. Turning off clears pending Jev reviews, diagnostics, and learned error categories; existing text follows retention. Keeps the dictionary."), state: !model.preferences.historyEnabled ? L("새 결과 저장 안 함 · 기존 기록은 보관 정책 유지", "No new results saved · Existing history follows retention") : nil) {
                Toggle(L("처리 결과 기록", "Save processing history"), isOn: $model.preferences.historyEnabled).labelsHidden().toggleStyle(.switch).disabled(!isEditable)
            }
            SettingsRow(L("텍스트 보관 기간", "Keep text history"), help: L("만료된 기록은 실행 중 또는 다음 실행 때 정리합니다. 성공한 원음은 삭제하며 실패 원음의 24시간 복구 정책과 독립입니다.", "Expired history is removed while running or on next launch. Successful audio is deleted; failed audio has a separate 24-hour recovery policy.")) {
                Picker(L("텍스트 보관 기간", "Keep text history"), selection: $model.preferences.retentionDays) {
                    Text(L("1일", "1 day")).tag(1); Text(L("7일", "7 days")).tag(7); Text(L("30일", "30 days")).tag(30); Text(L("90일", "90 days")).tag(90); Text(L("계속 보관", "Forever")).tag(-1)
                }.labelsHidden().frame(width: 240).disabled(!isEditable)
                    .onChange(of: model.preferences.retentionDays) { _, _ in Task { await model.refreshData() } }
            }
            SettingsRow(L("실패 녹음", "Failed recordings"), help: L("실패 녹음만 암호화해 최대24시간 보관합니다. 텍스트 기록과 별도이며 성공·만료 시 삭제합니다.", "Encrypts only failed audio for up to 24 hours, independently of text history. Deleted on success or expiry.")) {
                Button(L("24시간 복구", "24-hour recovery")) { model.page = .recovery }
            }
        }
    }

    @ViewBuilder private var learningRows: some View {
        SettingsRow(L("고친 표기 자동 학습", "Learn corrected spellings"), help: L("입력 직후 같은 입력창에서 고친 표기 중 확실한 이름·대소문자 교정만 사전에 반영합니다. 숫자·날짜·버전·문장 전체는 자동 등록하지 않습니다. 끄면 새 학습만 멈추며 기존 사전은 유지합니다.", "Learns only clear name and case corrections made in the same field just after input. Does not automatically learn numbers, dates, versions, or whole sentences. Off stops new learning and keeps the dictionary.")) {
            Toggle(L("고친 표기 자동 학습", "Learn corrected spellings"), isOn: $model.preferences.automaticLearningEnabled).labelsHidden().toggleStyle(.switch).disabled(!isEditable)
        }
        SettingsRow(L("개인 사전과 후보", "Dictionary and candidates")) {
            Button(L("교정 학습 보기", "View learned corrections")) { model.dictionarySection = .learning; model.page = .dictionary }.disabled(!isEditable)
        }
        if model.canUndoLastLearning {
            SettingsRow(L("최근 자동 학습", "Latest automatic learning")) { Button(L("되돌리기", "Undo")) { Task { await model.undoLastLearning() } }.disabled(!isEditable) }
        }
    }
    @ViewBuilder private var usagePrivacyRows: some View {
        SettingsRow(L("사용량 기록", "Record usage"), help: L("모델·요청·토큰·음성길이·처리 시간만 암호화해 최대10,000건 보관하며 문장과 원음은 포함하지 않습니다. 끄면 신규 수집을 멈추고 기존 통계를 유지합니다. 이미 저장 중인 기록은 늦게 반영될 수 있습니다.", "Encrypts up to 10,000 usage records with model, requests, tokens, audio duration, and timings, excluding text and audio. Off stops new collection and keeps statistics. Records already saving may appear later.")) {
            Toggle(L("사용량 기록", "Record usage"), isOn: $model.preferences.usageTrackingEnabled).labelsHidden().toggleStyle(.switch).disabled(!isEditable)
        }
        SettingsRow(L("보관한 통계", "Saved statistics")) { Button(L("사용량·비용 보기", "View usage and cost")) { model.page = .usage }.disabled(!isEditable) }
    }

    private var contextSection: some View {
        SettingsPanel(L("허용된 앱", "Allowed apps")) {
            if model.preferences.allowedContextApps.isEmpty { Text(L("허용한 앱 없음", "No allowed apps")).font(AppTypography.body).foregroundStyle(.secondary) }
            ForEach(model.preferences.allowedContextApps.sorted(), id: \.self) { bundle in
                SettingsRow(appName(bundle), help: contextHelp, state: L("주변 글 추가 전송", "Also sends surrounding text")) {
                    Button(L("허용 해제", "Remove access")) { model.preferences.allowedContextApps.remove(bundle) }.disabled(!isEditable)
                }
            }
            SettingsRow(L("앱별 허용", "Allow by app"), help: contextHelp) { Button(L("앱 추가…", "Add apps…")) { addContextApp() }.disabled(!isEditable) }
        }
    }

    private var inputReadinessSection: some View {
        SettingsPanel(L("입력 준비", "Input readiness")) {
            SettingsRow(L("Mac 접근 권한", "Mac permissions"), help: L("마이크와 손쉬운 사용 권한은 기본 입력 준비에 필요합니다. 실제 허용 상태를 확인하며 권한 허용만으로 외부 앱 입력 성공이 보장되지는 않습니다.", "Microphone and Accessibility are basic input requirements. Check actual permission status; permission alone does not guarantee insertion."),
                        state: L("마이크 \(model.microphoneAllowed ? "허용" : "필요") · 손쉬운 사용 \(model.accessibilityAllowed ? "허용" : "필요")", "Microphone \(model.microphoneAllowed ? "allowed" : "needed") · Accessibility \(model.accessibilityAllowed ? "allowed" : "needed")")) {
                Button(L("권한 설정…", "Permission settings…")) { model.openSettings(SettingsDetail.permissions) }
            }
            SettingsRow(L("다른 앱에 입력 확인", "Verify typing in another app"), help: L("준비한 테스트 문구를 대상 입력창에 실제 입력합니다. 녹음·API 요청·메시지 전송은 하지 않습니다.", "Types a prepared test sentence in the target field, without recording, API requests, or message sending.")) {
                Button(L("입력 테스트…", "Typing test…")) { model.openSettings(SettingsDetail.typingTest) }
            }
        }
    }

    private var generalSection: some View {
        SettingsPanel(L("앱과 화면", "App and appearance")) {
            SettingsRow(L("앱 언어", "App language"), help: L("인터페이스 언어만 즉시 바뀝니다. 인식·받아쓰기 출력·번역 언어는 바뀌지 않습니다.", "Changes only the interface language immediately, keeping speech and output languages.")) {
                Picker(L("앱 언어", "App language"), selection: $model.preferences.interfaceLanguage) {
                    Text(AppLanguage.english.title).tag(AppLanguage.english); Text(AppLanguage.korean.title).tag(AppLanguage.korean)
                }.labelsHidden().frame(width: 240).disabled(!isEditable)
            }
            SettingsRow(L("화면 모드", "Appearance"), help: L("일반 옵션은 자동 저장하며 API 키는 명시적으로 저장해야 적용됩니다.", "General options save automatically. API keys apply only after explicitly saving.")) {
                Picker(L("화면 모드", "Appearance"), selection: $model.preferences.appearance) {
                    Text(L("시스템에 맞춤", "System")).tag("system"); Text(L("라이트", "Light")).tag("light"); Text(L("다크", "Dark")).tag("dark")
                }.labelsHidden().frame(width: 240).disabled(!isEditable)
            }
            SettingsRow(L("로그인할 때 실행", "Open at login"), help: L("창 없이 메뉴바에서 대기합니다. 실제 로그인 항목 등록 결과를 사용합니다.", "Starts in the menu bar without a window, using the actual login-item registration state."), state: model.loginItemStatusText) {
                Toggle(L("로그인할 때 실행", "Open at login"), isOn: Binding(get: { model.launchAtLoginEnabled }, set: { if isEditable { model.setLaunchAtLogin($0) } })).labelsHidden().toggleStyle(.switch).disabled(!isEditable)
            }
            SettingsRow(L("로그인 항목 관리", "Manage login items")) { Button(L("시스템 설정", "System Settings")) { model.openLoginItemSettings() }.disabled(!isEditable) }
        }
    }

    private var typingTestSection: some View {
        SettingsPanel(L("녹음 없이 입력 확인", "Test typing without recording")) {
            SettingsRow(L("단축키로 테스트", "Test with shortcut"), help: L("준비한 뒤 대상 입력창에서 받아쓰기 단축키를 누르면 테스트 문구를 실제 입력합니다. 녹음·API 호출·메시지 전송은 하지 않습니다.", "After arming, press the dictation shortcut in the target field to type a test sentence. No recording, API request, or message sending."), state: inputTestState) {
                Button(L("테스트 준비", "Arm typing test")) { model.armInputTest() }.disabled(!canStartInputTest || model.inputTestArmed)
            }
            SettingsRow(L("예약 테스트", "Scheduled test"), help: L("5초 뒤 테스트 문구를 입력합니다. 준비 중에는 취소할 수 있습니다.", "Types the test sentence in five seconds. Cancel while armed.")) {
                Button(L("5초 뒤 시작", "Start in 5 seconds")) { model.scheduleInputTest() }.disabled(!canStartInputTest)
                if model.inputTestArmed { Button(L("취소", "Cancel")) { model.cancelInputTest() }.disabled(!isEditable) }
            }
            if !model.accessibilityAllowed {
                SettingsRow(L("Mac 접근 권한", "Mac permissions"), state: L("입력 테스트에 손쉬운 사용 권한 필요", "Typing tests require Accessibility permission")) {
                    Button(L("권한 설정…", "Permission settings…")) { model.openSettings(SettingsDetail.permissions) }
                }
            }
            if !model.inputDiagnostics.isEmpty {
                Text(model.inputDiagnostics).font(AppTypography.utility).textSelection(.enabled)
            }
        }
    }
    private var inputDiagnosticsSection: some View {
        SettingsPanel(L("최근 입력 확인", "Latest input verification")) {
            if model.inputDiagnostics.isEmpty {
                Text(L("아직 입력 진단이 없습니다", "No input diagnostics yet")).font(AppTypography.body).foregroundStyle(.secondary)
            } else {
                Text(model.inputDiagnostics).font(AppTypography.utility).textSelection(.enabled)
            }
        }
    }
    private var timingSection: some View {
        SettingsPanel(L("최근 처리 시간", "Latest processing times")) {
            SettingsRow(L("측정 범위", "Measurement scope"), help: L("음성 인식·정리·검토·입력의 실제 단계 시간을 표시합니다. 붙여넣기 뒤 확인 대기는 화면에 글이 나타난 시각과 다를 수 있습니다.", "Shows measured speech, cleanup, review, and insertion stages. Verification after pasting may differ from when text appears.")) { Text(model.lastProcessingTimings == nil ? L("측정 전", "Not measured") : L("최근 작업", "Latest job")).font(AppTypography.caption) }
            if let timings = model.lastProcessingTimings { Text(timings).font(AppTypography.utility).textSelection(.enabled) }
        }
    }
    private var permissionsSection: some View {
        SettingsPanel(L("권한 상태", "Permission status")) {
            SettingsRow(L("마이크", "Microphone"), help: L("직접 시작한 녹음에 사용합니다. 거부된 권한은 시스템 설정에서 허용합니다.", "Used for recordings you start. Allow denied access in System Settings."), state: model.microphoneAllowed ? L("허용됨", "Allowed") : L("허용 필요", "Access needed")) {
                if !model.microphoneAllowed && !model.microphonePermissionNeedsSettings {
                    Button(L("사용 요청", "Request")) { Task { await model.requestMicrophone() } }.disabled(!isEditable)
                }
                Button(L("시스템 설정", "System Settings")) { model.openMicrophoneSettings() }.disabled(!isEditable)
            }
            SettingsRow(L("손쉬운 사용", "Accessibility"), help: L("선택 문장을 읽고 다른 앱의 커서에 입력합니다. 허용 상태가 실제 입력 성공을 보장하지 않으므로 대상 앱에서 확인하세요.", "Reads selected text and types into another app's cursor. Permission does not guarantee insertion; test in the target app."), state: model.accessibilityAllowed ? L("허용됨", "Allowed") : L("허용 필요", "Access needed")) {
                Button(L("시스템 설정", "System Settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                }.disabled(!isEditable)
            }
            SettingsRow(L("현재 상태", "Current status"), help: L("앱이 활성화되면 권한을 다시 확인합니다.", "Permissions refresh when the app becomes active.")) { Button(L("다시 확인", "Refresh")) { model.refreshPermissions() }.disabled(!isEditable) }
            SettingsRow(L("연결부터 실제 입력까지", "Connections through typing")) { Button(L("처음부터 확인", "Check from the start")) { model.settingsDetail = nil; model.page = .home }.disabled(!isEditable) }
        }.onAppear { model.refreshPermissions() }
    }

    private var writingProfilesSection: some View {
        SettingsPanel(L("앱별 작성 규칙", "Writing rules by app")) {
            ForEach(writingProfileApps) { app in
                SettingsRow(app.name, help: profilesHelp, state: model.preferences.writingProfiles[app.id] == nil ? nil : L("사용자 설정", "Custom")) {
                    Picker(L("\(app.name) 작성 형식", "\(app.name) writing style"), selection: profileKindBinding(app.id)) {
                        ForEach(WritingProfileKind.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 80).disabled(!isEditable)
                    Picker(L("\(app.name) 말투", "\(app.name) tone"), selection: profileToneBinding(app.id)) {
                        ForEach(WritingTone.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 112).disabled(!isEditable)
                    Button { model.preferences.writingProfiles.removeValue(forKey: app.id); refreshWritingProfileApps() } label: { Image(systemName: "arrow.counterclockwise") }
                        .frame(width: 28).disabled(!isEditable || model.preferences.writingProfiles[app.id] == nil)
                        .help(L("기본값 복원", "Restore default")).accessibilityLabel(L("\(app.name) 기본값 복원", "Reset \(app.name) to defaults"))
                }
            }
            SettingsRow(L("앱 추가", "Add app"), help: profilesHelp) { Button(L("앱 선택…", "Choose apps…")) { addWritingProfileApp() }.disabled(!isEditable) }
        }.onAppear { refreshWritingProfileApps() }
    }

    @ViewBuilder private func detailContent(_ selected: SettingsDetail) -> some View {
        switch selected {
        case .speech: speechConnection
        case .text: textConnection
        case .reviewConnection: reviewConnection
        case .jev: reviewPolicySection; decisionTools
        case .assistance: SettingsPanel { JevAssistanceSettingsView(model: model, isEditable: connectionsEditable) }
        case .learning: SettingsPanel { JevFeedbackLearningSettingsView(model: model, isEditable: connectionsEditable) }
        case .profiles: writingProfilesSection
        case .context: contextSection
        case .typingTest: typingTestSection
        case .diagnostics: inputDiagnosticsSection; timingSection
        case .permissions: permissionsSection
        case .speechComparison:
            SpeechComparisonLabView(lab: model.speechLab, preferences: model.preferences,
                appBusy: model.phase != .idle || model.startupState == .loading || model.decisionConnectionTestInProgress,
                isEditable: isEditable && model.startupState == .ready, showsHeader: false)
        case .speaker: SpeakerSettingsContent(model: model)
        case .licenses: ModelLicenseSettingsView()
        case .comparison: EmptyView()
        }
    }

    private func returnToPreviousDetail() {
        guard let previous = detailHistory.popLast() else { return }
        returningToDetail = true
        model.openSettings(previous)
    }

    private var keyHelp: String { L("서비스별 API 키는 Keychain에 명시 저장합니다. 저장됨과 연결 성공은 다릅니다. 제공자를 바꿔도 다른 키·모델을 지우거나 복사하지 않습니다. 빈 입력에서 저장된 키 삭제를 직접 선택하면 해당 키를 지웁니다. 앱 구독과 API 비용은 별개입니다.", "Explicitly saves each service's API key in Keychain. Saved is not connected. Switching providers neither deletes nor copies other keys or models. Choosing Delete saved key with an empty field deletes that key. App subscriptions and API charges are separate.") }
    private var reviewHelp: String { JevRepairPresentation.modeDetail(model.preferences.decisionReviewMode) + "\n\n" + L("원문·결과·표기 후보를 Jev에 추가 전송하며 비용이 추가됩니다. 입력 후 검토는 이미 입력한 글을 바꾸지 않습니다. 입력 전 보호는 검토 실패·시간 초과에 기존 결과를 입력하지만, 입력 전 교정은 검토 실패·미해결 시 보류합니다. 교정은 현재 문장 모델로 최대 한 번 생성·재검토하며 참고 단가로 추가비용 US$0.05 한도를 유지합니다. 정확성을 보장하지 않습니다. 재인식 ON이면 observe도 입력 전 대기가 생길 수 있습니다. fast는 자동 검토를 생략하고 번역 검토는 별도 옵션입니다.", "Also sends source, output, and spelling candidates to Jev with extra charges. Observe never changes typed text. Protect uses existing text on review failure or timeout; Repair holds on failed review or unresolved concerns. Repair uses the current text model at most once with recheck and the existing US$0.05 reference-price extra-cost limit. Accuracy is not guaranteed. Re-recognition may delay typing even in Observe. Quick dictation skips automatic review; translation review is a separate option.") }
    private var translationReviewHelp: String { L("입력 전 보호와 함께 켜야 유효합니다. 원문·번역·목표 언어·말투를 추가 전송합니다. 일반 입력 전 보호와 달리 위험 신호뿐 아니라 검토 실패·미확인에도 입력을 보류하며 번역을 자동 교정하지 않습니다. 번역 다듬기도 켜면 다듬은 결과를 검토합니다. 비활성일 때 선택값은 유지됩니다.", "Requires Protect before typing. Also sends source, translation, target language, and tone. Unlike ordinary Protect, it holds not only on concern but on failed or unverifiable review, without automatic translation repair. If refinement is on, reviews the refined result. Keeps your choice while inactive.") }
    private var profilesHelp: String { L("녹음 시작 앱에 맞는 작성 형식·말투입니다. 기본은 말한 반말·존댓말 유지이며 지정한 앱만 변경합니다. 웹사이트·대화 상대 판단이나 주변 글 읽기는 하지 않습니다. fast에는 미적용, 번역에는 앱별 말투만 적용하며 프롬프트에는 미적용입니다.", "Uses the app at recording start to select format and tone. Preserves spoken tone unless changed for that app. Does not identify websites or recipients or read context. Not applied to quick dictation or prompts; app tone alone applies to translation.") }
    private var contextHelp: String { L("명시적으로 허용한 앱에서만 커서 앞 최대1,000자를 AI에 함께 보냅니다. 보안 입력란은 제외하고 문맥은 보관하지 않습니다. 앱별 작성 방식과 별개이며 웹사이트·대화 상대별 허용이 아닙니다.", "Only explicitly allowed apps send up to 1,000 characters before the cursor to AI. Excludes secure fields and does not retain context. Independent of writing style, not website- or recipient-specific.") }
    private var transmissionHelp: String { L("유효한 빠른 로컬 받아쓰기는 음성·문장을 외부 AI로 보내지 않습니다. 그 외 온라인 인식은 녹음을, 문장 정리·번역·선택 수정은 원문·요청을 선택한 서비스로 보냅니다. Jev는 원문·결과·표기 후보를, 교정은 원문·기존 결과·오류 유형을, 번역 다듬기는 원문·초안·언어·말투·사전 힌트를 추가 전송할 수 있습니다. 오류 유형은 모델별 암호화 저장하며 과거 문장은 저장하지 않습니다. OpenRouter는 실제 공급자로 전달할 수 있고 각 제공자가 비용을 청구합니다.", "Effective quick dictation sends neither audio nor text externally. Otherwise online recognition sends audio, and cleanup, translation, and edits send source and requests to the selected service. Jev may also receive source, output, and candidates; repair receives source, output, and categories; refinement receives source, draft, language, tone, and hints. Error categories are encrypted per model without past sentences. OpenRouter may forward to a host, and each provider bills its API use.") }
    private var transcriptionModelBinding: Binding<String> { Binding(get: { model.preferences.transcriptionModel }, set: { if connectionsEditable { model.preferences.transcriptionModels[model.preferences.provider.rawValue] = $0 } }) }
    private var textProviderBinding: Binding<AIProvider> { Binding(get: { model.preferences.effectiveTextProvider }, set: { value in
        guard connectionsEditable else { return }; model.preferences.textProvider = value; model.loadTextKey(); if value == model.preferences.provider { model.loadKey() }
    }) }
    private var textModelBinding: Binding<String> { Binding(get: { model.preferences.textModel }, set: { if connectionsEditable { model.preferences.textModels[model.preferences.effectiveTextProvider.rawValue] = $0 } }) }

    private func profileKindBinding(_ bundleID: String) -> Binding<WritingProfileKind> {
        Binding(get: { model.preferences.writingProfile(for: bundleID).kind }, set: { kind in
            guard isEditable else { return }
            var profile = model.preferences.writingProfile(for: bundleID)
            profile.kind = kind
            model.preferences.writingProfiles[bundleID] = profile
        })
    }

    private func profileToneBinding(_ bundleID: String) -> Binding<WritingTone> {
        Binding(get: { model.preferences.writingProfile(for: bundleID).tone }, set: { tone in
            guard isEditable else { return }
            var profile = model.preferences.writingProfile(for: bundleID)
            profile.tone = tone
            model.preferences.writingProfiles[bundleID] = profile
        })
    }

    private func refreshWritingProfileApps() {
        let identifiers = Set(WritingProfile.knownAppBundleIDs).union(model.preferences.writingProfiles.keys)
        writingProfileApps = identifiers.compactMap { identifier in
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                // Some Codex installations retain the older ChatGPT.app filename.
                let name = identifier == "com.openai.codex" ? "Codex" : url.deletingPathExtension().lastPathComponent
                return WritingProfileApp(id: identifier, name: name)
            }
            guard model.preferences.writingProfiles[identifier] != nil else { return nil }
            return WritingProfileApp(id: identifier, name: identifier)
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    private func addWritingProfileApp() {
        guard isEditable else { return }
        let panel = NSOpenPanel()
        panel.title = L("작성 방식을 지정할 앱 선택", "Choose apps to customize their writing style")
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, isEditable else { return }
        for url in panel.urls {
            guard let identifier = Bundle(url: url)?.bundleIdentifier else { continue }
            model.preferences.writingProfiles[identifier] = model.preferences.writingProfile(for: identifier)
        }
        refreshWritingProfileApps()
        model.openSettings(SettingsDetail.profiles)
    }

    private struct WritingProfileApp: Identifiable {
        let id: String
        let name: String
    }

    private func recordHotkey(_ index: Int) {
        guard isEditable else { return }
        stopHotkeyRecording(); recordingHotkey = index
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isEditable else { stopHotkeyRecording(); return nil }
            if event.keyCode == 53 { stopHotkeyRecording(); return nil }
            guard let binding = HotkeyBinding.from(event) else { return nil }
            model.updateHotkey(binding, index: index); stopHotkeyRecording(); return nil
        }
    }
    private func stopHotkeyRecording() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil; recordingHotkey = nil
    }
    private func addContextApp() {
        guard isEditable else { return }
        let panel = NSOpenPanel(); panel.title = L("문맥 사용을 허용할 앱 선택", "Choose apps allowed to provide context")
        panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, isEditable else { return }
        for url in panel.urls {
            if let identifier = Bundle(url: url)?.bundleIdentifier { model.preferences.allowedContextApps.insert(identifier) }
        }
    }
    private func appName(_ bundle: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        return url.deletingPathExtension().lastPathComponent
    }
}


/// Option rows own their vertical rhythm; the shared surface only supplies the container.
struct SettingsPanel<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content
    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    var body: some View {
        Surface(title) { VStack(alignment: .leading, spacing: 0, content: content) }
    }
}

struct SettingsDetailSheet<Content: View>: View {
    let title: String
    let backAction: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss
    init(_ title: String, backAction: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.backAction = backAction
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            HStack {
                if let backAction {
                    Button(L("뒤로", "Back"), systemImage: "chevron.backward", action: backAction)
                }
                AppPageHeader(title)
                Spacer()
                Button(L("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: AppLayout.panelSpacing, content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppLayout.pageInset).frame(width: 760, height: 640)
        .font(AppTypography.body).controlSize(.regular)
        .buttonStyle(AppActionButtonStyle())
    }
}

struct VoiceSettingsView: View {
    @Bindable var model: AppModel
    @State private var showsDetail = false
    private var isEditable: Bool { !model.preferencesRecoveryRequired && !AppLaunch.isPreview }
    private var controlsEnabled: Bool { isEditable && !model.isBusy }
    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            AppPageHeader(L("음성 모델", "Speech models"), help: L("모델 선택·파일 저장·메모리 준비를 구별합니다. 모델을 다운로드해도 인식 방식은 자동으로 바뀌지 않습니다. 모두 한국어·영어를 지원하지만 한영 혼용·고유명사 정확도를 보장하지 않으므로 같은 음성으로 비교하세요.", "Selection, downloaded files, and memory readiness are separate. Downloading does not switch speech processing. Korean and English support does not guarantee mixed-language or proper-name accuracy; compare with the same audio."))
            SettingsPanel(L("사용할 모델", "Current model")) {
                SettingsRow(L("현재 음성 인식", "Current recognition"), help: L("로컬 음성 인식에는 API 인식 비용이 없지만 이후 AI 문장 처리는 별도입니다. 유효한 빠른 로컬 받아쓰기는 음성·문장을 외부 AI로 보내지 않습니다.", "Local recognition has no speech API cost, but AI text processing is separate. Effective quick dictation sends neither audio nor text externally.")) {
                    Text(model.preferences.needsLocalForDictation ? L("이 Mac에서 인식", "On this Mac") : model.preferences.provider.displayName).font(AppTypography.caption).lineLimit(1)
                    Button(L("연결 설정…", "Connection settings…")) { model.openSettings(SettingsDetail.speech) }
                }
                SettingsRow(L("선택 모델", "Selected model")) {
                    Picker(L("선택 모델", "Selected model"), selection: $model.preferences.localSpeechModel) {
                        ForEach(LocalSpeechModel.allCases) { Text($0.displayName).tag($0) }
                    }.labelsHidden().frame(width: 240).disabled(!controlsEnabled)
                }
                SettingsRow(L("선택 모델 관리", "Manage selected model"), state: model.localState.label) {
                    Button(L("파일·메모리", "Files and memory")) { showsDetail = true }
                }
            }
            SettingsPanel(L("모델 파일", "Model files")) {
                ForEach(LocalSpeechModel.allCases) { speechModel in
                    SettingsRow(speechModel.displayName, state: cacheState(speechModel)) {
                        Button(model.preferences.localSpeechModel == speechModel ? L("선택됨", "Selected") : L("선택", "Select")) { model.preferences.localSpeechModel = speechModel }
                            .disabled(!controlsEnabled || model.preferences.localSpeechModel == speechModel)
                    }
                }
            }
            SettingsPanel(L("관련 도구", "Related tools")) {
                SettingsRow(L("내 음성으로 비교", "Compare my audio")) { Button(L("비교 도구 열기…", "Open comparison tool…")) { model.openSettings(SettingsDetail.speechComparison) } }
                SettingsRow(L("내 목소리 구분", "Recognize my voice"), state: L("실험 · 실사용 성능 미검증", "Experimental · Real-world performance unverified")) { Button(L("설정…", "Settings…")) { model.openSettings(SettingsDetail.speaker) } }
            }
        }
        .sheet(isPresented: $showsDetail) { SettingsDetailSheet(model.preferences.localSpeechModel.displayName) { LocalModelOptionsView(model: model) } }
        .task { if !AppLaunch.isPreview { await model.refreshVoiceInputOptions() } }
        .onChange(of: model.preferences.localSpeechModel) { _, _ in Task { await model.refreshVoiceInputOptions() } }
    }
    private func cacheState(_ speechModel: LocalSpeechModel) -> String {
        guard let cache = model.localModelCaches.first(where: { $0.model == speechModel }) else { return L("파일 확인 전", "Files not checked") }
        return cache.isDownloaded ? L("저장됨 · \(ByteCountFormatter.string(fromByteCount: cache.storedBytes, countStyle: .file))", "Downloaded · \(ByteCountFormatter.string(fromByteCount: cache.storedBytes, countStyle: .file))") : L("파일 준비 필요", "Files needed")
    }
}

struct SpeakerSettingsContent: View {
    @Bindable var model: AppModel
    private var isEditable: Bool { !model.preferencesRecoveryRequired && !AppLaunch.isPreview }
    private var speakerHelp: String {
        LocalSpeakerRecognizer.limitation + "\n\n" + L("조용한 곳에서 혼자10~20초 자연스럽게 말합니다. 등록 원음은 삭제하고 목소리 특징만 암호화 저장합니다. 기본은 꺼짐이며 실제 사용자·TV·겹말 환경 성능 검증 전입니다.", "Speak naturally alone in a quiet place for 10–20 seconds. Deletes enrollment audio and saves only encrypted voice features. Off by default and not yet validated with real users, TV audio, or overlapping speech.")
    }
    var body: some View {
        SettingsPanel(L("화자 모델과 등록", "Speaker model and enrollment")) {
            SettingsRow(L("실험 상태", "Experiment status"), help: speakerHelp, state: L("실사용 성능 미검증", "Real-world performance unverified")) { Text(L("실험 기능", "Experimental")).font(AppTypography.caption) }
            SettingsRow(L("화자 모델", "Speaker model"), help: L("음성 인식 모델과 별도의 약14MB 모델입니다.", "A separate model of about 14 MB, independent of speech recognition."), state: model.speakerState.label) {
                if model.speakerState.working {
                    Button(L("준비 취소", "Cancel setup")) { model.cancelSpeakerPreparation() }.disabled(!isEditable)
                } else if model.speakerState == .ready {
                    Label(L("준비됨", "Ready"), systemImage: "checkmark.circle").foregroundStyle(AppTheme.accentForeground)
                } else {
                    Button(L("다운로드·준비", "Download / prepare"), action: model.prepareSpeaker).disabled(!isEditable)
                }
            }
            if case .downloading(let progress) = model.speakerState { ProgressView(value: progress) }
            SettingsRow(L("내 목소리 등록", "Voice enrollment"), help: speakerHelp,
                        state: model.phase == .enrolling ? L("등록 녹음 중", "Enrollment recording") : model.hasSpeakerProfile ? L("등록됨", "Enrolled") : L("미등록", "Not enrolled")) {
                if model.phase == .enrolling {
                    Button(L("등록 녹음 종료", "Stop enrollment")) { model.stop() }.disabled(!isEditable)
                } else {
                    Button(model.hasSpeakerProfile ? L("다시 등록", "Enroll again") : L("등록 시작", "Start enrollment")) { Task { await model.enrollVoice() } }
                        .disabled(!isEditable || model.speakerState != .ready || model.isBusy)
                }
                if model.hasSpeakerProfile {
                    Button(L("삭제", "Delete"), role: .destructive) { Task { await model.deleteVoice() } }.disabled(!isEditable || model.isBusy)
                }
            }
            SettingsRow(L("내 목소리 필터", "Enrolled voice filter"), help: speakerHelp,
                        state: !model.hasSpeakerProfile ? L("등록 필요", "Enrollment required") : model.speakerState != .ready ? L("모델 준비 필요", "Model setup required") : model.preferences.speakerFilterEnabled && model.preferences.localPreviewEnabled ? L("미리보기 일시 미적용", "Preview temporarily paused") : nil) {
                Toggle(L("내 목소리 필터", "Enrolled voice filter"), isOn: $model.preferences.speakerFilterEnabled).labelsHidden().toggleStyle(.switch)
                    .disabled(!isEditable || !model.hasSpeakerProfile || model.speakerState != .ready)
            }
        }
    }
}

struct ModelLicenseSettingsView: View {
    var body: some View {
        SettingsPanel(L("모델과 코드", "Models and code")) {
            SettingsRow("WhisperKit / Whisper") { Text("MIT").font(AppTypography.caption) }
            SettingsRow(L("FluidAudio 코드", "FluidAudio code")) { Text("Apache-2.0").font(AppTypography.caption) }
            SettingsRow(L("화자 모델", "Speaker models"), help: "FluidInference, pyannote, WeSpeaker") { Text("CC BY 4.0").font(AppTypography.caption) }
            SettingsRow(L("음성 모델 출처", "Speech model source")) { Link("Hugging Face", destination: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!) }
            SettingsRow(L("화자 모델 출처", "Speaker model source")) { Link("Hugging Face", destination: URL(string: "https://huggingface.co/FluidInference/speaker-diarization-coreml")!) }
        }
    }
}

private extension LocalModelState {
    var working: Bool { switch self { case .downloading, .loading: true; default: false } }
}
