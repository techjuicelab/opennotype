import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OpenNoTypeCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var recordingHotkey: Int?
    @State private var hotkeyRejectionHint: String?
    @State private var eventMonitor: Any?
    @State private var writingProfileApps: [WritingProfileApp] = []
    @State private var showsReviewOptions = false
    @State private var showsSpeaker = false
    @State private var showsDiagnostics = false
    private var isEditable: Bool { !model.preferencesRecoveryRequired && !AppLaunch.isPreview }
    private var connectionsEditable: Bool { isEditable && model.startupState != .loading }
    private var controlsEnabled: Bool { isEditable && !model.isBusy }
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
            return L("일반 받아쓰기 검토는 현재 미적용 · 번역 검토는 아래 옵션에서 따로 켭니다.", "Dictation review is not applied · Translation review is a separate option below.")
        }
        switch model.preferences.decisionReviewMode {
        case .off: return L("자동 검토 꺼짐 · 최근 결과에서 직접 검토할 수 있습니다.", "Automatic review is off · You can still review a result yourself.")
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
            AppPageHeader(L("설정", "Settings"), subtitle: model.settingsSection.detail)
            SettingsTabBar(selection: Binding(get: { model.settingsSection }, set: { model.openSettings($0) }))
            sectionContent
        }
        .onChange(of: model.settingsSection) { _, _ in stopHotkeyRecording() }
        .onChange(of: model.preferencesRecoveryRequired) { _, required in if required { stopHotkeyRecording() } }
        .onDisappear { stopHotkeyRecording() }
        .onChange(of: model.settingsDetail) { _, detail in reveal(detail) }
        .onAppear { reveal(model.settingsDetail) }
        .sheet(item: sheetDetail) { selected in
            if selected == .comparison {
                JevModelComparisonView(model: model)
            } else {
                SettingsDetailSheet(selected.title) { detailContent(selected) }
            }
        }
    }

    /// Only tools and long lists open as sheets; other destinations are cards on the page.
    private var sheetDetail: Binding<SettingsDetail?> {
        Binding(get: { model.settingsDetail?.opensSheet == true ? model.settingsDetail : nil },
                set: { if $0 == nil, model.settingsDetail?.opensSheet == true { model.settingsDetail = nil } })
    }

    /// Opens the collapsed group that holds an inline destination; the manager scrolls to it.
    private func reveal(_ detail: SettingsDetail?) {
        switch detail {
        case .jev, .assistance: if detail == .assistance { showsReviewOptions = true }
        case .speaker: showsSpeaker = true
        case .diagnostics: showsDiagnostics = true
        default: break
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch model.settingsSection {
        case .dictation: dictationPage
        case .recording: recordingPage
        case .aiModels: SettingsAIModelsPage(model: model)
        case .privacy: privacyPage
        case .app: appPage
        }
    }

    // MARK: - Dictation

    private var dictationPage: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            SettingsCard(icon: "waveform", title: L("받아쓰기 방식", "Dictation"),
                         subtitle: L("평소 받아쓰기 단축키로 말했을 때의 처리 방식입니다.", "How your usual dictation shortcut processes speech.")) {
                SettingsRows {
                    SettingsStackedItem(L("받아쓰기 처리", "Processing"), detail: processingDetail, help: processingHelp,
                                        state: SettingsItemState.from(processingState)) {
                        SettingsSegmentedPicker(title: L("받아쓰기 처리", "Processing"), selection: $model.preferences.dictationProcessing,
                                                options: DictationProcessingMode.allCases,
                                                label: { $0 == .aiCleanup ? L("정리해서 입력", "AI cleanup") : L("빠른 로컬", "Quick local") },
                                                isEnabled: controlsEnabled)
                    }
                    DictationTranslationSettingsView(outputLanguage: $model.preferences.dictationOutputLanguage,
                                                     isEditable: isEditable, embedded: true)
                }
            }
            SettingsCard(icon: "textformat", title: L("문장과 말투", "Wording and tone"),
                         subtitle: L("AI 정리 받아쓰기에 적용되는 표현 방향과 앱별 규칙입니다.", "Wording and per-app rules applied to AI-cleaned dictation.")) {
                SettingsRows {
                    DictationExpressionSettingsView(expression: $model.preferences.dictationExpression,
                        outputLanguage: model.preferences.dictationOutputLanguage, isFastDictation: model.preferences.usesFastDictation,
                        isEditable: isEditable, embedded: true)
                    SettingsItem(L("앱별 작성 방식", "Writing style by app"),
                                 detail: L("녹음을 시작한 앱에 맞춰 형식과 말투를 적용합니다.", "Applies a format and tone for the app where you start recording."),
                                 help: profilesHelp,
                                 state: model.preferences.usesFastDictation ? .neutral(L("현재 미적용 · 빠른 로컬", "Paused · Quick local"))
                                    : model.preferences.dictationOutputLanguage.isTranslation ? .neutral(L("앱별 말투만 번역에 적용", "Only app tone applies to translation")) : nil) {
                        Text(model.preferences.writingProfiles.isEmpty ? L("앱 기본값", "App defaults")
                             : L("사용자 지정 \(model.preferences.writingProfiles.count)개 앱", "\(model.preferences.writingProfiles.count) custom"))
                            .font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                        Button(L("편집…", "Edit…")) { model.openSettings(SettingsDetail.profiles) }
                    }
                }
            }
            SettingsCard(icon: "globe", title: L("번역", "Translation"),
                         subtitle: L("번역 단축키의 언어와 번역 품질 옵션입니다.", "Language for the translation shortcut and quality options."),
                         badge: model.preferences.translationProtectionEnabled && model.preferences.decisionReviewMode == .protect
                            ? (.accent, L("입력 전 검토 켜짐", "Reviewed before typing")) : nil) {
                SettingsRows {
                    SettingsItem(L("번역 단축키 언어", "Translation shortcut language"),
                                 detail: L("번역 단축키에만 적용되며 평소 받아쓰기 출력 언어와 별개입니다.", "Applies only to the translation shortcut, separate from your usual output language.")) {
                        Picker(L("번역 단축키 언어", "Translation shortcut language"), selection: $model.preferences.targetLanguage) {
                            Text(L("영어 · 미국식", "English · US")).tag("English (United States)")
                            Text(L("영어 · 영국식", "English · UK")).tag("English (United Kingdom)")
                            Text(L("한국어", "Korean")).tag("Korean")
                            Text(L("일본어", "Japanese")).tag("Japanese")
                            Text(L("중국어 · 간체", "Chinese · Simplified")).tag("Chinese (Simplified)")
                            Text(L("중국어 · 번체", "Chinese · Traditional")).tag("Chinese (Traditional)")
                        }.frame(minWidth: 150, maxWidth: 220).disabled(!isEditable)
                    }
                    TranslationRefinementSettingsView(isEnabled: $model.preferences.translationRefinementEnabled,
                        reviewsBeforeTyping: model.preferences.translationProtectionEnabled && model.preferences.decisionReviewMode == .protect,
                        isEditable: isEditable && model.startupState == .ready, embedded: true)
                }
            }
            reviewCard.id(SettingsDetail.jev.anchor)
        }
    }

    private var reviewCard: some View {
        SettingsCard(icon: "checkmark.shield", title: L("자동 문장 검토 (Jev)", "Automatic text review (Jev)"),
                     subtitle: L("의미 변경·누락·표기 오류를 입력 전후에 점검합니다.", "Checks for changed meaning, omissions and spelling before or after typing."),
                     help: reviewHelp) {
            SettingsRows {
                SettingsItem(L("자동 검토 방식", "Review mode"), state: .neutral(reviewStatus)) {
                    Picker(L("자동 검토 방식", "Review mode"), selection: $model.preferences.decisionReviewMode) {
                        ForEach(DecisionReviewMode.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(minWidth: 150, maxWidth: 220)
                    .disabled(!connectionsEditable)
                }
                if reviewNeedsConnection {
                    SettingsItem(L("검토 연결 준비 필요", "Review connection needed"),
                                 state: .warning(L("검토에 쓸 OpenRouter 키를 저장하거나 확인해 주세요.", "Save or check an OpenRouter key for review."))) {
                        Button(L("API 키 관리", "Manage keys")) { model.openSettings(SettingsDetail.keys) }
                    }
                }
                SettingsDisclosure(title: L("세부 검토·도움 옵션", "Review & assistance options"), summary: reviewOptionsSummary,
                                   isExpanded: $showsReviewOptions) {
                    SettingsRows {
                        SettingsRow(L("번역도 입력 전 검토", "Review translations before typing"), help: translationReviewHelp,
                                    state: model.preferences.decisionReviewMode != .protect ? L("현재 미적용 · 입력 전 보호에서 사용", "Paused · Protect before typing only") : model.preferences.translationProtectionEnabled ? L("추가 전송·비용 · 검토 실패 시 보류", "Extra transfer and charges · Holds on review failure") : nil) {
                            Toggle(L("번역도 입력 전 검토", "Review translations before typing"), isOn: $model.preferences.translationProtectionEnabled)
                                .toggleStyle(.switch).disabled(!connectionsEditable || model.preferences.decisionReviewMode != .protect)
                        }
                        JevAssistanceSettingsView(model: model, isEditable: connectionsEditable)
                    }
                }
            }
        }
    }

    /// Review can reuse any saved OpenRouter key; warn only while a mode that needs it is on.
    private var reviewNeedsConnection: Bool {
        model.preferences.decisionReviewMode != .off
            && model.preferences.decisionProvider == .openRouter
            && model.preferences.effectiveTextProvider != .openRouter
            && model.providerKeyPresence[.openRouter] != true
    }

    private var reviewOptionsSummary: String {
        let count = [model.preferences.translationProtectionEnabled, model.preferences.jevDetailedReviewEnabled, model.preferences.jevEconomyEnabled,
                     model.preferences.jevAutomaticImprovementEnabled, model.preferences.jevClarifyEditsEnabled,
                     model.preferences.jevReRecognitionEnabled].filter { $0 }.count
        return count == 0 ? L("사용 안 함", "Off") : L("\(count)개 켜짐", "\(count) on")
    }

    private var processingState: String? {
        if model.preferences.dictationProcessing == .onDeviceVerbatim && model.preferences.dictationOutputLanguage.isTranslation {
            return L("번역 중 미적용 · 빠른 로컬 선택 유지", "Paused during translation · Quick choice kept")
        }
        if model.preferences.usesFastDictation && model.localState != .ready {
            return L("로컬 모델 · \(model.localState.label)", "Local model · \(model.localState.label)")
        }
        return nil
    }

    private var processingDetail: String {
        model.preferences.dictationProcessing == .aiCleanup
            ? L("AI가 말실수·추임새를 정리합니다. 빠른 로컬은 이 Mac의 인식문을 그대로 입력하고 외부로 보내지 않습니다.", "AI cleans up slips and fillers. Quick local types this Mac's transcript as is and sends nothing out.")
            : L("이 Mac의 인식문을 AI 정리 없이 입력합니다. 말한 언어 유지일 때만 적용됩니다.", "Types this Mac's transcript without AI cleanup. Applies only when keeping the spoken language.")
    }

    private var processingHelp: String {
        L("정리해서 입력은 인식한 문장을 AI로 정리합니다. 빠른 로컬 받아쓰기는 말한 언어 유지일 때만 이 Mac의 인식문을 AI 정리·자동 Jev 없이 입력합니다. API 키는 필요 없지만 로컬 모델 준비가 필요합니다. 번역·선택 수정·프롬프트는 별도의 AI 처리를 사용합니다. 인식문이 발화를 완벽히 복제한다는 뜻은 아닙니다.", "Cleanup uses AI to edit the transcript. Quick on-device dictation applies only when keeping the spoken language and types the local transcript without AI cleanup or automatic Jev. It needs a prepared local model, not an API key. Translation, selected-text edits, and prompts use their separate AI processing. A transcript is not guaranteed to reproduce speech perfectly.")
    }

    // MARK: - Recording

    private var defaultHotkeys: [HotkeyBinding] {
        AppIdentity.current.isPromptTest ? HotkeyBinding.promptTestDefaults : HotkeyBinding.defaults
    }

    private var recordingPage: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            SettingsCard(icon: "mic", title: L("녹음", "Recording"),
                         subtitle: L("마이크 입력과 녹음 시작·종료 동작입니다.", "Microphone input and how recording starts and stops.")) {
                SettingsRows { VoiceInputOptionsView(model: model, showsProcessing: false, embedded: true) }
            }
            hotkeysCard
            SettingsCard(icon: "flask", title: L("실험적 녹음 기능", "Experimental recording"),
                         subtitle: L("실사용 검증 중인 기능입니다. 기본값은 꺼짐입니다.", "Still being validated in real use. Off by default."),
                         badge: (.info, L("실험", "Experimental"))) {
                SettingsRows {
                    LocalPreviewSettingsRow(model: model)
                    SettingsDisclosure(title: L("내 목소리 구분", "Recognize my voice"),
                                       summary: model.hasSpeakerProfile ? L("등록됨", "Enrolled") : L("미등록", "Not enrolled"),
                                       isExpanded: $showsSpeaker) {
                        SpeakerSettingsContent(model: model, embedded: true)
                    }
                }
            }
            .id(SettingsDetail.speaker.anchor)
        }
    }

    private var hotkeysCard: some View {
        SettingsCard(icon: "keyboard", title: L("작업별 단축키", "Shortcuts by task"),
                     subtitle: L("Option·Control·Command 중 하나 이상을 포함한 조합을 쓰세요.", "Use a combination with Option, Control or Command."),
                     help: shortcutHelp) {
            Button(L("충돌 확인", "Check conflicts")) { model.refreshHotkeyConflicts() }.disabled(!isEditable)
            Button(L("기본값 복원", "Restore defaults")) {
                stopHotkeyRecording()
                model.resetHotkeysToDefaults()
            }
            .disabled(!isEditable || model.preferences.hotkeys == defaultHotkeys)
        } content: {
            SettingsRows {
                ForEach(Array(InputMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    let isRecordingThis = recordingHotkey == index
                    SettingsItem(mode.title, detail: hotkeyDetail(mode),
                                 state: isRecordingThis ? .accent(hotkeyRejectionHint ?? L("새 조합을 누르세요 · Esc로 취소", "Press a new combination · Esc cancels")) : nil) {
                        Button(isRecordingThis ? L("입력 대기…", "Waiting…") : model.hotkeyLabel(index: index)) { recordHotkey(index) }
                            .font(AppTypography.utility).frame(minWidth: 120)
                            .buttonStyle(AppActionButtonStyle(primary: isRecordingThis))
                            .accessibilityLabel(L("\(mode.title) 단축키 변경", "Change \(mode.title) shortcut"))
                            .accessibilityValue(model.hotkeyLabel(index: index)).disabled(!isEditable)
                    }
                }
            }
            if !model.hotkeyConflicts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.hotkeyConflicts, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle").font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                    }
                }
                .padding(.top, 8)
            }
        }
        .onAppear { model.refreshHotkeyConflicts() }
    }

    private func hotkeyDetail(_ mode: InputMode) -> String {
        switch mode {
        case .dictation: L("말한 내용을 정리하거나 바로 입력합니다.", "Cleans up what you say, or types it directly.")
        case .translation: L("말한 내용을 번역 단축키 언어로 입력합니다.", "Types what you say in the translation language.")
        case .rewrite: L("선택한 글에 음성 수정 지시를 적용합니다.", "Applies a spoken edit to the selected text.")
        case .prompt: L("생각을 AI에게 줄 지시문으로 정리합니다.", "Turns your thoughts into an instruction for an AI.")
        }
    }

    // MARK: - Privacy

    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            SettingsCard(icon: "archivebox", title: L("기록과 보관", "History and retention"),
                         subtitle: L("모든 기록은 이 Mac에 암호화해 저장합니다.", "All history is encrypted on this Mac.")) {
                SettingsRows {
                    SettingsItem(L("처리 결과 기록", "Save processing history"),
                                 detail: L("받아쓰기·번역·수정·프롬프트 결과를 이 Mac에 보관합니다.", "Keeps dictation, translation, edit and prompt results on this Mac."),
                                 help: L("받아쓰기·번역·선택 수정과 제공한 프롬프트를 암호화 저장합니다. 중간 초안·차단/오류 프롬프트는 저장하지 않습니다. 끄면 진행 중 Jev 검토·진단·학습한 오류 유형을 지우며 기존 텍스트 기록은 보관 기간을 따릅니다. 개인 사전은 유지됩니다.", "Encrypts dictation, translation, edits, and delivered prompts. Does not save intermediate, blocked, or failed prompts. Turning off clears pending Jev reviews, diagnostics, and learned error categories; existing text follows retention. Keeps the dictionary."),
                                 state: !model.preferences.historyEnabled ? .warning(L("새 결과 저장 안 함 · 기존 기록은 보관 정책 유지", "No new results saved · Existing history follows retention")) : nil) {
                        Toggle(L("처리 결과 기록", "Save processing history"), isOn: $model.preferences.historyEnabled).toggleStyle(.switch).disabled(!isEditable)
                    }
                    SettingsItem(L("텍스트 보관 기간", "Keep text history"),
                                 detail: L("만료된 텍스트는 자동 정리하고, 성공한 녹음 원음은 바로 삭제합니다.", "Expired text is cleaned up automatically; audio from successful jobs is deleted right away.")) {
                        Picker(L("텍스트 보관 기간", "Keep text history"), selection: $model.preferences.retentionDays) {
                            Text(L("1일", "1 day")).tag(1); Text(L("7일", "7 days")).tag(7); Text(L("30일", "30 days")).tag(30); Text(L("90일", "90 days")).tag(90); Text(L("계속 보관", "Forever")).tag(-1)
                        }.frame(minWidth: 120, maxWidth: 180).disabled(!isEditable)
                            .onChange(of: model.preferences.retentionDays) { _, _ in Task { await model.refreshData() } }
                    }
                    SettingsItem(L("실패 녹음 복구", "Failed recordings"),
                                 detail: L("실패한 녹음만 암호화해 최대 24시간 보관합니다.", "Only failed audio is encrypted and kept for up to 24 hours.")) {
                        Text(L("복구 가능 \(model.failures.count)개", "\(model.failures.count) recoverable")).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                        Button(L("다시 처리 보기", "Open Recovery")) { model.page = .recovery }
                    }
                }
            }
            transferCard.id(SettingsDetail.context.anchor)
            SettingsCard(icon: "brain", title: L("학습과 통계", "Learning and usage"),
                         subtitle: L("개인 사전 자동 학습, 오류 유형 기억, 사용량 기록입니다.", "Dictionary learning, error patterns and usage records.")) {
                SettingsRows {
                    SettingsItem(L("고친 표기 자동 학습", "Learn corrected spellings"),
                                 detail: L("입력 직후 같은 입력창에서 고친 이름·대소문자만 학습합니다.", "Learns only names and capitalization you fix right after typing."),
                                 help: L("입력 직후 같은 입력창에서 고친 표기 중 확실한 이름·대소문자 교정만 사전에 반영합니다. 숫자·날짜·버전·문장 전체는 자동 등록하지 않습니다. 끄면 새 학습만 멈추며 기존 사전은 유지합니다.", "Learns only clear name and case corrections made in the same field just after input. Does not automatically learn numbers, dates, versions, or whole sentences. Off stops new learning and keeps the dictionary.")) {
                        SettingsLinkButton(L("교정 학습", "Learned words")) { model.dictionarySection = .learning; model.page = .dictionary }
                        Toggle(L("고친 표기 자동 학습", "Learn corrected spellings"), isOn: $model.preferences.automaticLearningEnabled).toggleStyle(.switch).disabled(!isEditable)
                    }
                    if model.canUndoLastLearning {
                        SettingsItem(L("최근 자동 학습", "Latest automatic learning")) { Button(L("되돌리기", "Undo")) { Task { await model.undoLastLearning() } }.disabled(!isEditable) }
                    }
                    JevFeedbackLearningSettingsView(model: model, isEditable: connectionsEditable)
                    SettingsItem(L("사용량 기록", "Record usage"),
                                 detail: L("문장·원음 없이 모델·토큰·비용만 최대 10,000건 보관합니다.", "Keeps up to 10,000 records of models, tokens and cost, without text or audio."),
                                 help: L("모델·요청·토큰·음성길이·처리 시간만 암호화해 최대10,000건 보관하며 문장과 원음은 포함하지 않습니다. 끄면 신규 수집을 멈추고 기존 통계를 유지합니다. 이미 저장 중인 기록은 늦게 반영될 수 있습니다.", "Encrypts up to 10,000 usage records with model, requests, tokens, audio duration, and timings, excluding text and audio. Off stops new collection and keeps statistics. Records already saving may appear later.")) {
                        SettingsLinkButton(L("사용량·비용", "Usage")) { model.page = .usage }
                        Toggle(L("사용량 기록", "Record usage"), isOn: $model.preferences.usageTrackingEnabled).toggleStyle(.switch).disabled(!isEditable)
                    }
                }
            }
            .id(SettingsDetail.learning.anchor)
        }
    }

    private var transferCard: some View {
        SettingsCard(icon: "paperplane", title: L("외부 전송과 주변 문맥", "Data sent to AI"),
                     subtitle: L("지금 설정에서 외부 AI로 보내는 범위와 문맥을 허용한 앱입니다.", "What your current settings send to AI services, and apps allowed to share context."),
                     help: transmissionHelp) {
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(Array(transferBadges.enumerated()), id: \.offset) { _, badge in StatusBadge(kind: badge.kind, text: badge.text) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(L("앱별 주변 문맥", "Context by app")).font(AppTypography.body)
                        OptionHelp(title: L("앱별 주변 문맥", "Context by app"), message: contextHelp)
                        Spacer(minLength: 8)
                        Button(L("앱 추가…", "Add apps…"), systemImage: "plus") { addContextApp() }.disabled(!isEditable)
                    }
                    Text(L("허용한 앱에서만 커서 앞 최대 1,000자를 함께 보냅니다. 보안 입력란은 제외합니다.", "Only allowed apps send up to 1,000 characters before the cursor. Secure fields are excluded."))
                        .font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                }
                if model.preferences.allowedContextApps.isEmpty {
                    Text(L("허용한 앱이 없습니다.", "No apps allowed."))
                        .font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(AppTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: AppLayout.nestedCornerRadius))
                } else {
                    SettingsRows {
                        ForEach(model.preferences.allowedContextApps.sorted(), id: \.self) { bundle in
                            SettingsItem(appName(bundle), state: .neutral(L("주변 글 추가 전송", "Also sends surrounding text"))) {
                                Button(L("허용 해제", "Remove")) { model.preferences.allowedContextApps.remove(bundle) }.disabled(!isEditable)
                            }
                        }
                    }
                }
            }
        }
    }

    private var transferBadges: [ModelBadge] {
        let p = model.preferences
        var badges: [ModelBadge] = []
        if p.usesFastDictation {
            badges.append(.init(kind: .accent, text: L("받아쓰기: 외부 전송 없음", "Dictation: nothing sent")))
        } else {
            badges.append(.init(kind: .neutral, text: p.needsLocal ? L("음성: 이 Mac", "Speech: this Mac") : L("음성: \(p.provider.displayName)", "Speech: \(p.provider.displayName)")))
            badges.append(.init(kind: .neutral, text: L("문장: \(p.effectiveTextProvider.displayName)", "Text: \(p.effectiveTextProvider.displayName)")))
        }
        badges.append(p.decisionReviewMode == .off ? .init(kind: .neutral, text: L("검토: 꺼짐", "Review: off"))
                      : .init(kind: .info, text: L("검토: Jev 추가 전송", "Review: also sent to Jev")))
        badges.append(p.translationRefinementEnabled ? .init(kind: .info, text: L("번역 다듬기: 추가 요청 1회", "Refinement: 1 extra request"))
                      : .init(kind: .neutral, text: L("번역 다듬기: 꺼짐", "Refinement: off")))
        if !p.allowedContextApps.isEmpty {
            badges.append(.init(kind: .info, text: L("주변 문맥: \(p.allowedContextApps.count)개 앱", "Context: \(p.allowedContextApps.count) apps")))
        }
        return badges
    }

    // MARK: - App

    private var appPage: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            permissionsCard.id(SettingsDetail.permissions.anchor)
            SettingsCard(icon: "paintpalette", title: L("앱과 화면", "App and appearance"),
                         subtitle: L("화면 모드, 앱 언어와 시작 동작을 정합니다.", "Appearance, app language and launch behavior.")) {
                SettingsRows {
                    SettingsStackedItem(L("화면 모드", "Appearance")) {
                        SettingsSegmentedPicker(title: L("화면 모드", "Appearance"),
                                                selection: Binding(get: { AppearanceChoice(rawValue: model.preferences.appearance) ?? .system },
                                                                   set: { model.preferences.appearance = $0.rawValue }),
                                                options: AppearanceChoice.allCases, label: \.title, icon: { $0.icon }, isEnabled: isEditable)
                    }
                    SettingsItem(L("앱 언어", "App language"), detail: L("메뉴와 화면 언어만 바뀝니다. 받아쓰기·번역 언어는 그대로입니다.", "Changes menus and screens only, not dictation or translation languages.")) {
                        SettingsSegmentedPicker(title: L("앱 언어", "App language"), selection: $model.preferences.interfaceLanguage,
                                                options: [AppLanguage.korean, .english], label: \.title, isEnabled: isEditable)
                            .fixedSize()
                    }
                    SettingsItem(L("로그인할 때 실행", "Open at login"), detail: L("창 없이 메뉴바에서 대기합니다.", "Waits in the menu bar without a window."),
                                 state: SettingsItemState.from(model.loginItemStatusText)) {
                        SettingsLinkButton(L("로그인 항목", "Login items"), systemImage: "arrow.up.right") { model.openLoginItemSettings() }
                        Toggle(L("로그인할 때 실행", "Open at login"), isOn: Binding(get: { model.launchAtLoginEnabled }, set: { if isEditable { model.setLaunchAtLogin($0) } })).toggleStyle(.switch).disabled(!isEditable)
                    }
                }
            }
            SettingsCard(icon: "arrow.triangle.2.circlepath", title: L("업데이트", "Updates"),
                         subtitle: L("앱 버전과 업데이트 확인 방식입니다.", "App version and how updates are checked.")) {
                UpdateSettingsView(updater: .shared, isEditable: isEditable, embedded: true)
            }
            SettingsCard(icon: "stethoscope", title: L("진단과 정보", "Diagnostics and information"),
                         subtitle: L("최근 처리 기록과 오픈소스 라이선스를 확인합니다.", "Recent processing details and open-source licenses.")) {
                SettingsRows {
                    SettingsDisclosure(title: L("최근 처리 진단", "Recent processing diagnostics"),
                                       summary: model.lastProcessingTimings == nil ? L("측정 전", "Not measured") : L("최근 작업", "Latest job"),
                                       isExpanded: $showsDiagnostics) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("최근 입력 확인", "Latest input verification")).font(AppTypography.caption.weight(.semibold)).foregroundStyle(AppTheme.textSecondary)
                            Text(model.inputDiagnostics.isEmpty ? L("아직 입력 진단이 없습니다", "No input diagnostics yet") : model.inputDiagnostics)
                                .font(AppTypography.utility).textSelection(.enabled)
                            Text(L("최근 처리 시간", "Latest processing times")).font(AppTypography.caption.weight(.semibold)).foregroundStyle(AppTheme.textSecondary)
                                .padding(.top, 4)
                            Text(model.lastProcessingTimings ?? L("측정 전", "Not measured")).font(AppTypography.utility).textSelection(.enabled)
                        }
                        .padding(.bottom, 8)
                    }
                    SettingsItem(L("모델·오픈소스 고지", "Models and open-source notices")) {
                        Button(L("라이선스 보기…", "View licenses…")) { model.openSettings(SettingsDetail.licenses) }
                    }
                }
            }
            .id(SettingsDetail.diagnostics.anchor)
        }
    }

    private var permissionsCard: some View {
        SettingsCard(icon: "hand.raised", title: L("Mac 권한과 입력 확인", "Mac permissions and typing"),
                     subtitle: L("다른 앱에 글을 입력하려면 마이크와 손쉬운 사용 권한이 필요합니다.", "Typing into other apps needs Microphone and Accessibility access.")) {
            Button(L("다시 확인", "Refresh")) { model.refreshPermissions() }.disabled(!isEditable)
        } content: {
            SettingsRows {
                SettingsItem(L("마이크", "Microphone"), detail: L("직접 시작한 녹음에만 사용합니다.", "Used only for recordings you start.")) {
                    permissionBadge(model.microphoneAllowed)
                    if !model.microphoneAllowed && !model.microphonePermissionNeedsSettings {
                        Button(L("사용 요청", "Request")) { Task { await model.requestMicrophone() } }.disabled(!isEditable)
                    }
                    Button(L("시스템 설정", "System Settings")) { model.openMicrophoneSettings() }.disabled(!isEditable)
                }
                SettingsItem(L("손쉬운 사용", "Accessibility"), detail: L("선택한 글을 읽고 커서 위치에 입력합니다.", "Reads selected text and types at the cursor."),
                             help: L("허용 상태가 실제 입력 성공을 보장하지 않으므로 대상 앱에서 확인하세요.", "Permission does not guarantee insertion; test in the target app.")) {
                    permissionBadge(model.accessibilityAllowed)
                    Button(L("시스템 설정", "System Settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                    }.disabled(!isEditable)
                }
                SettingsItem(L("다른 앱에 입력 테스트", "Typing test"),
                             detail: L("녹음·API 호출 없이 대상 입력창에 테스트 문구를 입력합니다.", "Types a test sentence in the target field, without recording or API calls."),
                             state: SettingsItemState.from(inputTestState)) {
                    Button(L("단축키로 테스트", "Shortcut test")) { model.armInputTest() }.disabled(!canStartInputTest || model.inputTestArmed)
                    Button(L("5초 뒤 시작", "Start in 5 s")) { model.scheduleInputTest() }.disabled(!canStartInputTest)
                    if model.inputTestArmed { Button(L("취소", "Cancel")) { model.cancelInputTest() }.disabled(!isEditable) }
                }
            }
        }
        .onAppear { model.refreshPermissions() }
    }

    @ViewBuilder private func permissionBadge(_ allowed: Bool) -> some View {
        StatusBadge(kind: allowed ? .accent : .error, text: allowed ? L("허용됨", "Allowed") : L("허용 필요", "Needed"),
                    systemImage: allowed ? "checkmark" : "exclamationmark")
    }

    // MARK: - Sheets

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
                        .buttonStyle(AppIconButtonStyle(size: 28))
                        .disabled(!isEditable || model.preferences.writingProfiles[app.id] == nil)
                        .help(L("기본값 복원", "Restore default")).accessibilityLabel(L("\(app.name) 기본값 복원", "Reset \(app.name) to defaults"))
                }
            }
            SettingsRow(L("앱 추가", "Add app"), help: profilesHelp) { Button(L("앱 선택…", "Choose apps…")) { addWritingProfileApp() }.disabled(!isEditable) }
        }.onAppear { refreshWritingProfileApps() }
    }

    @ViewBuilder private func detailContent(_ selected: SettingsDetail) -> some View {
        switch selected {
        case .profiles: writingProfilesSection
        case .speechComparison:
            SpeechComparisonLabView(lab: model.speechLab, preferences: model.preferences,
                appBusy: model.phase != .idle || model.startupState == .loading || model.decisionConnectionTestInProgress,
                isEditable: isEditable && model.startupState == .ready, showsHeader: false)
        case .licenses: ModelLicenseSettingsView()
        default: EmptyView()
        }
    }

    private var reviewHelp: String { JevRepairPresentation.modeDetail(model.preferences.decisionReviewMode) + "\n\n" + L("원문·결과·표기 후보를 Jev에 추가 전송하며 비용이 추가됩니다. 입력 후 검토는 이미 입력한 글을 바꾸지 않습니다. 입력 전 보호는 검토 실패·시간 초과에 기존 결과를 입력하지만, 입력 전 교정은 검토 실패·미해결 시 보류합니다. 교정은 현재 문장 모델로 최대 한 번 생성·재검토하며 참고 단가로 추가비용 US$0.05 한도를 유지합니다. 정확성을 보장하지 않습니다. 재인식 ON이면 observe도 입력 전 대기가 생길 수 있습니다. fast는 자동 검토를 생략하고 번역 검토는 별도 옵션입니다.", "Also sends source, output, and spelling candidates to Jev with extra charges. Observe never changes typed text. Protect uses existing text on review failure or timeout; Repair holds on failed review or unresolved concerns. Repair uses the current text model at most once with recheck and the existing US$0.05 reference-price extra-cost limit. Accuracy is not guaranteed. Re-recognition may delay typing even in Observe. Quick dictation skips automatic review; translation review is a separate option.") }
    private var translationReviewHelp: String { L("입력 전 보호와 함께 켜야 유효합니다. 원문·번역·목표 언어·말투를 추가 전송합니다. 일반 입력 전 보호와 달리 위험 신호뿐 아니라 검토 실패·미확인에도 입력을 보류하며 번역을 자동 교정하지 않습니다. 번역 다듬기도 켜면 다듬은 결과를 검토합니다. 비활성일 때 선택값은 유지됩니다.", "Requires Protect before typing. Also sends source, translation, target language, and tone. Unlike ordinary Protect, it holds not only on concern but on failed or unverifiable review, without automatic translation repair. If refinement is on, reviews the refined result. Keeps your choice while inactive.") }
    private var profilesHelp: String { L("녹음 시작 앱에 맞는 작성 형식·말투입니다. 기본은 말한 반말·존댓말 유지이며 지정한 앱만 변경합니다. 웹사이트·대화 상대 판단이나 주변 글 읽기는 하지 않습니다. fast에는 미적용, 번역에는 앱별 말투만 적용하며 프롬프트에는 미적용입니다.", "Uses the app at recording start to select format and tone. Preserves spoken tone unless changed for that app. Does not identify websites or recipients or read context. Not applied to quick dictation or prompts; app tone alone applies to translation.") }
    private var contextHelp: String { L("명시적으로 허용한 앱에서만 커서 앞 최대1,000자를 AI에 함께 보냅니다. 보안 입력란은 제외하고 문맥은 보관하지 않습니다. 앱별 작성 방식과 별개이며 웹사이트·대화 상대별 허용이 아닙니다.", "Only explicitly allowed apps send up to 1,000 characters before the cursor to AI. Excludes secure fields and does not retain context. Independent of writing style, not website- or recipient-specific.") }
    private var transmissionHelp: String { L("유효한 빠른 로컬 받아쓰기는 음성·문장을 외부 AI로 보내지 않습니다. 그 외 온라인 인식은 녹음을, 문장 정리·번역·선택 수정은 원문·요청을 선택한 서비스로 보냅니다. Jev는 원문·결과·표기 후보를, 교정은 원문·기존 결과·오류 유형을, 번역 다듬기는 원문·초안·언어·말투·사전 힌트를 추가 전송할 수 있습니다. 오류 유형은 모델별 암호화 저장하며 과거 문장은 저장하지 않습니다. OpenRouter는 실제 공급자로 전달할 수 있고 각 제공자가 비용을 청구합니다.", "Effective quick dictation sends neither audio nor text externally. Otherwise online recognition sends audio, and cleanup, translation, and edits send source and requests to the selected service. Jev may also receive source, output, and candidates; repair receives source, output, and categories; refinement receives source, draft, language, tone, and hints. Error categories are encrypted per model without past sentences. OpenRouter may forward to a host, and each provider bills its API use.") }
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
        stopHotkeyRecording(); recordingHotkey = index; hotkeyRejectionHint = nil
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isEditable else { stopHotkeyRecording(); return nil }
            if event.keyCode == 53 { stopHotkeyRecording(); return nil }
            guard let binding = HotkeyBinding.from(event) else {
                hotkeyRejectionHint = L("Option(⌥), Control(⌃), Command(⌘) 중 하나 이상을 함께 눌러 주세요.", "Include at least one of Option (⌥), Control (⌃), or Command (⌘).")
                return nil
            }
            hotkeyRejectionHint = nil
            model.updateHotkey(binding, index: index); stopHotkeyRecording(); return nil
        }
    }
    private func stopHotkeyRecording() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil; recordingHotkey = nil; hotkeyRejectionHint = nil
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
        AppDisplayName.name(for: bundle)
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
        .appSheetStyle()
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
                SettingsRow(L("선택 모델", "Selected model"), help: L("다운로드·토크나이저·추론 엔진이 연결된 지원 모델 목록입니다. 임의의 모델 ID 직접 입력은 지원하지 않습니다.", "These supported models are linked to downloads, tokenizers, and the inference engine. Arbitrary model IDs are not supported.")) {
                    Picker(L("선택 모델", "Selected model"), selection: $model.preferences.localSpeechModel) {
                        ForEach(LocalSpeechModel.allCases) { Text($0.displayName).tag($0) }
                    }.labelsHidden().frame(width: 240).disabled(!controlsEnabled)
                }
                SettingsRow(L("메모리·파일 관리", "Files and memory"), state: model.localState.label) {
                    if model.localState == .ready {
                        Label(L("준비됨", "Ready"), systemImage: "checkmark.circle.fill")
                            .font(AppTypography.caption.weight(.medium)).foregroundStyle(AppTheme.accentForeground)
                    } else if model.localState.working {
                        Button(L("준비 취소", "Cancel")) { model.cancelLocalPreparation() }.disabled(!controlsEnabled)
                    } else {
                        Button(L("다운로드·준비", "Download / prepare"), action: model.prepareLocal)
                            .buttonStyle(AppActionButtonStyle(primary: true)).disabled(!controlsEnabled)
                    }
                    Button(L("상세…", "Manage…")) { showsDetail = true }
                }
                if case .downloading(let progress) = model.localState {
                    ProgressView(value: min(1, max(0, progress)))
                        .padding(.vertical, 6)
                } else if model.localState == .loading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .padding(.vertical, 6)
                }
            }
            SettingsPanel(L("모델 목록", "Available models")) {
                ForEach(Array(LocalSpeechModel.allCases.enumerated()), id: \.element.id) { index, speechModel in
                    if index > 0 { Divider() }
                    let isSelected = model.preferences.localSpeechModel == speechModel
                    SettingsRow(speechModel.displayName, state: modelRowState(speechModel, isSelected: isSelected)) {
                        if isSelected {
                            if model.localState == .ready {
                                Label(L("사용 준비됨", "Ready"), systemImage: "checkmark.circle.fill")
                                    .font(AppTypography.caption.weight(.medium)).foregroundStyle(AppTheme.accentForeground)
                            } else if model.localState.working {
                                Button(L("취소", "Cancel")) { model.cancelLocalPreparation() }.disabled(!controlsEnabled)
                            } else {
                                Button(L("다운로드·준비", "Download / prepare"), action: model.prepareLocal)
                                    .buttonStyle(AppActionButtonStyle(primary: true)).disabled(!controlsEnabled)
                            }
                        } else {
                            Button(L("선택", "Select")) { model.preferences.localSpeechModel = speechModel }
                                .disabled(!controlsEnabled)
                        }
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
    private func modelRowState(_ speechModel: LocalSpeechModel, isSelected: Bool) -> String {
        let cacheText = cacheState(speechModel)
        if isSelected {
            return "\(cacheText) · \(model.localState.label)"
        }
        return cacheText
    }
    private func cacheState(_ speechModel: LocalSpeechModel) -> String {
        guard let cache = model.localModelCaches.first(where: { $0.model == speechModel }) else { return L("파일 확인 전", "Files not checked") }
        return cache.isDownloaded ? L("저장됨 · \(ByteCountFormatter.string(fromByteCount: cache.storedBytes, countStyle: .file))", "Downloaded · \(ByteCountFormatter.string(fromByteCount: cache.storedBytes, countStyle: .file))") : L("파일 준비 필요", "Files needed")
    }
}

struct SpeakerSettingsContent: View {
    @Bindable var model: AppModel
    var embedded = false
    private var isEditable: Bool { !model.preferencesRecoveryRequired && !AppLaunch.isPreview }
    private var speakerHelp: String {
        LocalSpeakerRecognizer.limitation + "\n\n" + L("조용한 곳에서 혼자10~20초 자연스럽게 말합니다. 등록 원음은 삭제하고 목소리 특징만 암호화 저장합니다. 기본은 꺼짐이며 실제 사용자·TV·겹말 환경 성능 검증 전입니다.", "Speak naturally alone in a quiet place for 10–20 seconds. Deletes enrollment audio and saves only encrypted voice features. Off by default and not yet validated with real users, TV audio, or overlapping speech.")
    }
    var body: some View {
        if embedded { rows } else { SettingsPanel(L("화자 모델과 등록", "Speaker model and enrollment")) { rows } }
    }

    @ViewBuilder private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
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

private enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: L("시스템", "System"); case .light: L("라이트", "Light"); case .dark: L("다크", "Dark") }
    }
    var icon: String {
        switch self { case .system: "desktopcomputer"; case .light: "sun.max"; case .dark: "moon" }
    }
}
