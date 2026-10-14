import AppKit
import SwiftUI
import OpenNoTypeCore

struct HomeView: View {
    @Bindable var model: AppModel
    @State private var showSetupDetails = false
    @State private var showConnectionDetails = false

    private var readyForInput: Bool {
        !model.preferencesRecoveryRequired && model.startupState == .ready && aiConnectionReady && model.requiredJevReady && model.hotkeysRegistered && model.microphoneAllowed && model.accessibilityAllowed
            && (!model.preferences.needsLocalForDictation || model.localState == .ready)
            && (!model.preferences.speakerFilterEnabled || (model.hasSpeakerProfile && model.speakerState == .ready))
    }

    var body: some View {
        AppPageHeader(L("받아쓰기", "Dictation"), help: inputHelp)
        currentWork
        if !readyForInput { inputReadiness }
        if let composition = model.promptComposition {
            PromptCompositionResultView(composition: composition, isBusy: model.isBusy,
                regenerationSettings: model.promptRegenerationSettings, onRegenerate: model.regeneratePrompt)
        }
        latestResult
        JevAssistanceResultsView(model: model)
        latestJevReview
        if model.phase == .idle, model.promptComposition == nil, model.result.isEmpty,
           model.decisionOriginalText == nil, model.recentDecisionTarget == nil, model.translationRefinement == nil {
            Surface(L("최근 결과", "Latest result")) {
                Text(L("아직 결과가 없습니다.", "No result yet.")).font(AppTypography.body).foregroundStyle(.secondary)
            }
        }
        shortcutConflicts
        if readyForInput { inputReadiness }
        inputModes
        currentModels
        savedRecordings
    }

    private var inputHelp: String {
        L("입력할 앱의 본문을 클릭한 뒤 받아쓰기 단축키를 누릅니다. ", "Click the text field in the app you want to type into, then press your dictation shortcut. ")
            + shortcutInstructions
            + L("\n\nOpenNoType 창에는 일반 받아쓰기를 입력하지 않습니다. 비밀번호 입력란·Secure Input·손쉬운 사용 권한과 원래 입력 대상 확인은 기존 보호를 따릅니다. 준비됨은 키 저장·권한·모델 준비를 뜻하며 실제 API 연결과 입력 성공을 보장하지 않습니다.", "\n\nRegular dictation does not type into OpenNoType itself. Password fields, Secure Input, Accessibility permission and the original target retain their existing checks. Ready refers to saved keys, permissions and prepared models; it does not guarantee API connectivity or successful typing.")
    }

    @ViewBuilder private var currentWork: some View {
        if model.phase != .idle {
            Surface {
                HStack(spacing: 12) {
                    if model.phase == .starting || model.phase == .processing { ProgressView().controlSize(.small) }
                    Label(model.status, systemImage: model.isRecording ? "mic.fill" : "waveform")
                        .font(AppTypography.body).frame(maxWidth: .infinity, alignment: .leading)
                    if model.isRecording {
                        Text(String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60))
                            .font(AppTypography.utility).foregroundStyle(.secondary)
                        Button(L("녹음 끝내기", "Finish recording"), action: model.stop)
                            .frame(minHeight: AppLayout.controlHeight)
                    }
                    Button(L("취소", "Cancel"), action: model.cancel).frame(minHeight: AppLayout.controlHeight)
                }
            }
        }
    }

    @ViewBuilder private var shortcutConflicts: some View {
        if !model.hotkeyConflicts.isEmpty {
            // Survives notice resets: the launch notice is cleared on every recording start.
            Surface(L("단축키가 다른 앱과 겹쳐요", "Another app uses this shortcut")) {
                ForEach(model.hotkeyConflicts, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").font(AppTypography.caption).foregroundStyle(.orange).lineSpacing(4)
                }
                Button(L("설정 › 녹음·단축키 열기", "Open Settings › Recording & Shortcuts")) { openSettings(.input) }
            }
        }
    }

    private var inputReadiness: some View {
        Surface {
            HStack(spacing: 8) {
                Label(readyForInput ? L("준비됨", "Ready") : L("준비 필요", "Setup needed"),
                      systemImage: readyForInput ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(AppTypography.body).foregroundStyle(readyForInput ? AppTheme.accentForeground : AppTheme.warm)
                OptionHelp(title: L("입력 준비 상태", "Typing readiness"), message: inputHelp)
                Spacer(minLength: 8)
                Button(model.inputTestArmed ? L("준비 취소", "Cancel test") : L("입력 연습", "Test typing")) {
                    if model.inputTestArmed { model.cancelInputTest() } else { model.armInputTest() }
                }.disabled(model.isBusy || model.startupState != .ready || !model.accessibilityAllowed)
                    .frame(minHeight: AppLayout.controlHeight)
                OptionHelp(title: L("입력 연습", "Test typing"), message: L("원하는 앱의 빈 본문을 클릭한 뒤 받아쓰기 단축키를 누르면 시험 문장을 실제로 입력합니다. 녹음·API 호출·메시지 전송은 하지 않습니다. 5초 예약 방식도 준비 상세에서 사용할 수 있습니다.", "Click an empty text field in another app and press your dictation shortcut to enter a test sentence. This does not record, call an API or send a message. A five-second scheduled test is also available in readiness details."))
            }
            if !readyForInput { missingSetupRows }
            if model.inputTestArmed {
                Label(L("원하는 입력창에서 받아쓰기 단축키를 누르세요.", "Press your dictation shortcut in the text field you want to use."), systemImage: "keyboard")
                    .font(AppTypography.caption).foregroundStyle(AppTheme.accentForeground)
            }
            if let issue = model.requiredJevIssue {
                Label(issue.message, systemImage: "exclamationmark.circle")
                    .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                Button(L("Jev 연결 설정", "Set up Jev connection")) { openSettings(.connection) }
            }
            DisclosureGroup(L("준비 상태 확인", "Readiness details"), isExpanded: $showSetupDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    setupRows
                    HStack(spacing: 8) {
                        Button(L("권한 다시 확인", "Refresh permissions"), systemImage: "arrow.clockwise") { model.refreshPermissions() }
                        Button(L("Mac 권한", "Mac permissions")) { openSettings(.advanced) }
                        Button(L("5초 뒤 입력 연습", "Test typing in 5 seconds")) { model.scheduleInputTest() }
                            .disabled(model.isBusy || model.startupState != .ready || !model.accessibilityAllowed)
                    }
                    if !model.inputDiagnostics.isEmpty {
                        DisclosureGroup(L("최근 입력 진단", "Latest typing diagnostics")) {
                            Text(model.inputDiagnostics).font(AppTypography.utility).textSelection(.enabled).padding(.top, 8)
                        }
                    }
                }.padding(.top, 8)
            }.font(AppTypography.caption)
        }
    }

    @ViewBuilder private var missingSetupRows: some View {
        if !aiConnectionReady {
            setupRow(L("음성·문장 연결", "Speech and text connection"), detail: L("필요한 키를 저장해 주세요.", "Save the required keys."), ready: false) { openSettings(.connection) }
        }
        if !model.hotkeysRegistered {
            setupRow(L("단축키", "Shortcut"), detail: L("등록할 수 없는 조합입니다.", "The shortcut could not be registered."), ready: false) { openSettings(.input) }
        }
        if !model.microphoneAllowed {
            setupRow(L("마이크", "Microphone"), detail: L("사용 권한이 필요합니다.", "Permission is required."), ready: false) {
                if model.microphonePermissionNeedsSettings { model.openMicrophoneSettings() }
                else { Task { await model.requestMicrophone() } }
            }
        }
        if !model.accessibilityAllowed {
            setupRow(L("다른 앱에 입력", "Type into other apps"), detail: L("손쉬운 사용 권한이 필요합니다.", "Accessibility permission is required."), ready: false) { openSettings(.advanced) }
        }
        if model.preferences.needsLocalForDictation, model.localState != .ready {
            setupRow(L("로컬 음성 모델", "Local speech model"), detail: model.localState.label, ready: false) { model.page = .voice }
        }
        if model.preferences.speakerFilterEnabled, !model.hasSpeakerProfile || model.speakerState != .ready {
            setupRow(L("내 목소리 필터", "My voice filter"), detail: model.hasSpeakerProfile ? model.speakerState.label : L("등록 필요", "Enrollment needed"), ready: false) { model.page = .voice }
        }
    }

    private var inputModes: some View {
        Surface(L("입력할 앱에서 시작", "Start in the app you want to type into")) {
            modeRow(.dictation, icon: "waveform", detail: model.preferences.dictationOutputLanguage.isTranslation
                    ? L("현재 출력: \(model.preferences.dictationOutputLanguage.title)", "Current output: \(model.preferences.dictationOutputLanguage.title)")
                    : model.preferences.usesFastDictation
                    ? L("이 Mac에서 인식한 원문을 AI 정리 없이 입력합니다.", "Types the on-device transcript without AI cleanup.")
                    : L("추임새와 말실수를 정리하고 말한 언어를 유지합니다.", "Cleans up fillers and slips while keeping the spoken language."), index: 0)
            Divider()
            modeRow(.translation, icon: "character.bubble", detail: L("선택한 번역 언어로 입력합니다.", "Types in your selected translation language."), index: 1)
            Divider()
            modeRow(.rewrite, icon: "pencil.line", detail: L("외부 앱에서 문장을 먼저 선택한 뒤 수정 지시를 말합니다.", "Select text in another app, then speak your editing instruction."), index: 2)
            Divider()
            promptInput
        }
    }

    private var shortcutInstructions: String {
        let action: String
        switch model.preferences.shortcutActivation {
        case .toggle:
            action = L("같은 단축키를 다시 누르면 녹음이 끝납니다.", "Press the same shortcut again to finish recording.")
        case .hold:
            action = L("단축키를 누르는 동안 녹음하고, 손을 떼면 끝납니다.", "Hold your shortcut to record; release it to finish.")
        case .holdOrToggle:
            action = L("짧게 누르면 녹음을 유지하고 다시 눌러 끝냅니다. 길게 누르면 손을 뗄 때 끝납니다.", "Tap to keep recording and press again to finish. Hold to record until you release.")
        }
        return action + L(" 변경은 설정 › 녹음·단축키에서 할 수 있어요.", " Change this in Settings › Recording & Shortcuts.")
    }

    private var promptInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(L("프롬프트 만들기", "Create a prompt"), systemImage: "text.bubble").font(AppTypography.body)
                OptionHelp(title: L("프롬프트 만들기", "Create a prompt"), message: promptHelp)
                Spacer(minLength: 8)
                Text(model.hotkeyLabel(index: 3)).font(AppTypography.utility).foregroundStyle(.secondary)
                Button(model.isRecording && model.mode == .prompt ? L("녹음 끝내기", "Finish recording") : L("복사용 녹음", "Record to copy"),
                       systemImage: model.isRecording && model.mode == .prompt ? "stop.fill" : "mic.fill") {
                    Task { await model.toggle(.prompt) }
                }
                .frame(minHeight: AppLayout.controlHeight)
                .disabled(AppLaunch.isPreview || model.preferencesRecoveryRequired || model.startupState != .ready
                          || (model.isBusy && !(model.isRecording && model.mode == .prompt)))
            }
            if let issue = model.promptCompositionIssue {
                HStack(alignment: .top, spacing: 8) {
                    Label(issue, systemImage: "exclamationmark.circle")
                        .font(AppTypography.caption).foregroundStyle(AppTheme.warm).frame(maxWidth: .infinity, alignment: .leading)
                    Button(L("AI 연결 설정", "AI connection settings")) { openSettings(.connection) }
                }
            }
            Text(L("생성 1~2회·검토 2회 · 추가 API 비용 · 이 창에서는 복사 · AI 자동 제출 없음", "1–2 generations · 2 reviews · Additional API cost · Copy here · No automatic AI submission"))
                .font(AppTypography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var promptHelp: String {
        L("생각나는 대로 말하면 목표·맥락·제약·원하는 결과를 짧은 AI 지시문으로 정리합니다. 프로젝트나 AI를 말하면 포함하며, 코드나 직접 설계안은 만들지 않습니다. 받아쓰기·번역 설정과 별개로 처리합니다.\n\n홈에서 시작한 녹음·재처리·원문 수정은 복사용입니다. 다른 앱에서 단축키로 녹음하면 완성된 결과를 원래 입력창에 입력하며, AI에 자동 제출하지 않습니다. 참고 경고가 있어도 입력할 수 있지만 기존 지침 관련 차단·오류·취소 때는 입력하지 않습니다. 입력 실패 시 결과를 복사할 수 있습니다.\n\n음성 인식 뒤 문장 생성 1~2회와 Jev 검토 2회를 실행합니다. 초안에 수정이 필요할 때만 한 번 다듬으며 추가 비용과 대기 시간이 발생합니다.", "Speak freely to turn your goal, context, constraints and desired result into short AI instructions. Mention a project or AI to include it. It does not generate code or concrete designs and processes independently of dictation and translation settings.\n\nRecordings started from Home, reprocessing and source edits produce results to copy. Use the shortcut in another app to type the finished result into the original field. Prompts are never submitted to an AI automatically. Notes may still allow typing; instruction-boundary blocks, errors and cancellation prevent it. If typing fails, copy the result.\n\nAfter transcription, one or two text calls and two Jev reviews add cost and time. The draft is polished once only when it needs correction.")
    }

    @ViewBuilder private var latestResult: some View {
        if !model.result.isEmpty || model.decisionOriginalText != nil || model.recentDecisionTarget != nil || model.translationRefinement != nil {
            Surface(L("최근 결과", "Latest result")) {
                if let language = model.recentTranslationLanguage {
                    Label(model.translationRefinement?.held == true
                          ? L("번역 초안 · 당시 출력 언어: \(language)", "Draft translation · Captured output language: \(language)")
                          : L("번역 결과 · 당시 출력 언어: \(language)", "Translation · Captured output language: \(language)"), systemImage: "character.bubble")
                        .font(AppTypography.caption.weight(.medium)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let original = model.decisionOriginalText {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: AppLayout.panelSpacing) {
                            transcriptColumn(original)
                            resultColumn
                        }
                        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
                            transcriptColumn(original)
                            resultColumn
                        }
                    }
                } else { resultColumn }
                if let refinement = model.translationRefinement {
                    TranslationRefinementResultView(refinement: refinement)
                }
                if let target = model.recentDecisionTarget {
                    if model.decisionOriginalText == nil {
                        DisclosureGroup(L("인식 원문과 비교", "Compare with transcript")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(target.transcript).font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
                                Button(L("원문 복사", "Copy transcript"), systemImage: "doc.on.doc") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(target.transcript, forType: .string)
                                }
                            }.padding(.top, 8)
                        }.font(AppTypography.caption)
                    }
                    JevReviewRequestButton(model: model, title: L("최근 결과를 Jev로 검토…", "Review latest result with Jev…"),
                                           targetTitle: target.title, requestIdentity: target.id.uuidString, purpose: target.purpose) {
                        model.reviewRecentResult()
                    }
                }
            }
        }
    }

    private func transcriptColumn(_ original: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("인식 원문", "Transcript")).font(AppTypography.caption).foregroundStyle(.secondary)
            Text(original).font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
            Button(L("원문 복사", "Copy transcript"), systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(original, forType: .string)
            }
        }.frame(minWidth: 220, maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var resultColumn: some View {
        if !model.result.isEmpty || model.translationRefinement == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.translationRefinement?.held == true ? L("번역 초안", "Draft translation")
                     : model.recentTranslationLanguage == nil ? L("결과", "Result") : L("번역 결과", "Translation"))
                    .font(AppTypography.caption).foregroundStyle(.secondary)
                Text(model.result.isEmpty ? L("정리 결과가 비어 있습니다.", "The cleaned result is empty.") : model.result)
                    .font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
                Button(model.translationRefinement?.held == true ? L("초안 복사", "Copy draft") : L("결과 복사", "Copy result"), systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.result, forType: .string)
                }
                .buttonStyle(AppActionButtonStyle(primary: true)).disabled(model.result.isEmpty)
            }.frame(minWidth: 220, maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private var latestJevReview: some View {
        if let target = model.decisionReviewTarget, target.kind == .recent,
           target.id == model.recentDecisionTarget?.id {
            Surface(L("Jev 문장 검토", "Jev text review")) {
                JevReviewView(model: model, target: target)
            }
        }
    }

    @ViewBuilder private var savedRecordings: some View {
        if !model.failures.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Label(L("다시 처리할 수 있는 녹음 \(model.failures.count)개", "\(model.failures.count) recordings available to retry"), systemImage: "arrow.clockwise")
                    .font(AppTypography.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(L("다시 처리", "Recovery")) { model.page = .recovery }
            }
        }
    }

    private var currentModels: some View {
        Surface {
            HStack(spacing: 8) {
                Text(model.preferences.usesFastDictation
                     ? L("이 Mac · 빠른 받아쓰기", "This Mac · Quick dictation")
                     : L("AI 정리 · \(model.preferences.dictationOutputLanguage.title)", "AI cleanup · \(model.preferences.dictationOutputLanguage.title)"))
                    .font(AppTypography.body)
                OptionHelp(title: L("현재 처리 방식", "Current processing"), message: processingHelp)
                Spacer(minLength: 8)
                Button(L("변경", "Change")) { openSettings(.dictation) }.accessibilityLabel(L("받아쓰기 설정과 모델 변경", "Change dictation settings and models"))
                    .frame(minHeight: AppLayout.controlHeight)
            }
            if !model.preferences.usesFastDictation, !model.preferences.dictationOutputLanguage.isTranslation,
               model.preferences.decisionReviewMode != .off && model.preferences.decisionReviewMode != .repair && !jevConnectionReady {
                Label(L("말한 언어 유지 받아쓰기: Jev 연결이 준비되지 않아 자동 검토를 건너뜁니다.", "Keep spoken language dictation: automatic review is skipped while the Jev connection is unavailable."), systemImage: "exclamationmark.circle")
                    .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
            }
            if model.preferences.translationProtectionEnabled,
               model.preferences.decisionReviewMode == .protect && !jevConnectionReady {
                Label(L("번역의 입력 전 검토 연결이 준비되지 않았습니다. 검토할 수 없는 번역은 자동 입력을 보류합니다.", "Translation review is unavailable. Translations that cannot be reviewed will be held before typing."), systemImage: "exclamationmark.circle")
                    .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
            }
            DisclosureGroup(L("모델과 현재값", "Models and current values"), isExpanded: $showConnectionDetails) {
            VStack(alignment: .leading, spacing: 12) {
                modelRow(L("음성 인식", "Speech recognition"), icon: "waveform", name: model.preferences.needsLocalForDictation ? model.preferences.localSpeechModel.displayName : "\(model.preferences.provider.displayName) · \(model.preferences.transcriptionModel)")
                modelRow(L("문장 처리", "Text processing"), icon: "text.alignleft", name: model.preferences.usesFastDictation
                         ? L("사용 안 함 · 인식 원문 바로 입력", "Off · Type the transcript directly")
                         : "\(model.preferences.effectiveTextProvider.displayName) · \(model.preferences.textModel)")
                modelRow(L("Jev 검토", "Jev review"), icon: "checkmark.shield", name: model.preferences.usesFastDictation
                         ? L("빠른 받아쓰기 중 자동 검토 안 함", "No automatic review during quick dictation")
                         : model.preferences.translationProtectionEnabled && model.preferences.decisionReviewMode == .protect
                         ? L("\(jevConnectionName) · 번역도 입력 전 검토", "\(jevConnectionName) · Translation review before typing")
                         : model.preferences.dictationOutputLanguage.isTranslation
                         ? L("\(jevConnectionName) · 번역은 직접 검토", "\(jevConnectionName) · Translation review on request")
                         : "\(jevConnectionName) · \(model.preferences.decisionReviewMode.title)")
                modelRow(L("받아쓰기 출력 언어", "Dictation output language"), icon: "character.bubble", name: model.preferences.dictationOutputLanguage.title)
                modelRow(L("받아쓰기 표현", "Dictation expression"), icon: "slider.horizontal.3", name: model.preferences.usesFastDictation
                         ? L("AI 정리 없이 인식 원문 유지", "Keep the transcript without AI cleanup")
                         : model.preferences.dictationOutputLanguage.isTranslation
                         ? L("번역 중 사용 안 함", "Paused while translating")
                         : model.preferences.dictationExpression.isActive
                           ? "\(model.preferences.dictationExpression.style.title) · \(model.preferences.dictationExpression.strength)/100"
                           : L("현재 받아쓰기 · 강도 0", "Current dictation · Strength 0"))
            }
                if model.preferences.needsLocalForDictation && model.localState != .ready {
                    Button(L("로컬 모델 준비하기", "Prepare local model"), systemImage: "desktopcomputer") { model.page = .voice }
                }
            }.font(AppTypography.caption)
        }
    }

    private var processingHelp: String {
        let path = model.preferences.usesFastDictation
            ? L("빠른 받아쓰기는 이 Mac에서 인식한 원문을 AI 정리·자동 Jev 검토 없이 입력하며 음성·문장을 외부 AI로 보내지 않습니다. 번역·음성 수정·프롬프트는 설정된 AI 연결을 사용합니다.", "Quick dictation types the on-device transcript without AI cleanup or automatic Jev review and sends neither audio nor text to external AI. Translation, voice editing and prompts use the configured AI connection.")
            : L("반복·말실수를 정리하고 이름·조건·의미 있는 강조를 보존하도록 요청합니다. 로컬 음성 인식과 이후 AI 문장 처리는 별개입니다. 저장된 API 키의 실제 연결은 요청할 때 확인합니다.", "Cleanup is asked to preserve names, conditions and meaningful emphasis while removing repetition and slips. On-device speech recognition and later AI text processing are separate. Saved API keys are checked when a request is made.")
        return path + "\n\n" + jevConnectionDetail + "\n\n" + JevRepairPresentation.modeDetail(model.preferences.decisionReviewMode)
            + L("\n\n번역 입력 전 보호는 당시 원문·번역·목표 언어·말투를 추가 전송하며 위험 또는 검토 실패 시 입력을 보류합니다. 번역을 자동 교정하지 않습니다. 음성 재인식을 켠 입력 후 검토는 첫 판단과 필요한 재인식을 입력 전에 기다릴 수 있으며 이후 검토는 이미 입력한 글을 바꾸지 않습니다.", "\n\nTranslation protection additionally sends the captured source, translation, target language and tone; risk or review failure holds typing without automatically repairing the translation. With audio re-recognition enabled, review after typing may wait for the first judgment and re-recognition before typing; later review does not change text already entered.")
    }

    private func modelRow(_ title: String, icon: String, name: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon).font(AppTypography.body).foregroundStyle(AppTheme.accentForeground).frame(width: 20)
            Text(title).font(AppTypography.caption).foregroundStyle(.secondary).frame(width: 112, alignment: .leading)
            Text(name).font(AppTypography.body.weight(.medium)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var jevConnectionName: String {
        model.preferences.decisionProvider == .typeSafe
            ? L("TypeSafe 직접 연결", "TypeSafe direct")
            : L("OpenRouter 키 재사용", "Shared OpenRouter key")
    }

    private var jevConnectionReady: Bool {
        switch model.preferences.decisionProvider {
        case .typeSafe:
            model.decisionKeySaved && !model.decisionKeyOperationInProgress
        case .openRouter:
            model.preferences.effectiveTextProvider == .openRouter && model.textKeySaved && !model.textKeyOperationInProgress
        }
    }

    private var jevConnectionDetail: String {
        switch model.preferences.decisionProvider {
        case .typeSafe:
            if model.decisionKeyOperationInProgress {
                return L("저장된 Jev 키를 확인하고 있어요. Keychain 인증창이 나타나면 승인해 주세요.", "Checking your saved Jev key. Approve the Keychain prompt if it appears.")
            }
            return model.decisionKeySaved
                ? L("Jev API 키가 저장되어 있습니다. 실제 연결은 검토 요청 때 확인합니다.", "Your Jev API key is saved. The connection is checked when a review is requested.")
                : L("저장된 Jev API 키가 없습니다. AI 연결 설정에서 키를 저장해 주세요.", "No Jev API key is saved. Save one in AI connection settings.")
        case .openRouter:
            if model.preferences.effectiveTextProvider != .openRouter {
                return L("OpenRouter 키 재사용은 문장 처리 제공자가 OpenRouter일 때 사용할 수 있습니다.", "Sharing an OpenRouter key requires OpenRouter as the text processing provider.")
            }
            if model.textKeyOperationInProgress {
                return L("문장 처리에 저장된 OpenRouter 키를 확인하고 있어요.", "Checking the OpenRouter key saved for text processing.")
            }
            return model.textKeySaved
                ? L("문장 처리에 저장한 OpenRouter 키를 함께 사용합니다. 실제 연결은 검토 요청 때 확인합니다.", "Uses the OpenRouter key saved for text processing. The connection is checked when a review is requested.")
                : L("문장 처리에 저장된 OpenRouter 키가 없습니다. AI 연결 설정에서 키를 저장해 주세요.", "No OpenRouter key is saved for text processing. Save one in AI connection settings.")
        }
    }

    private var aiConnectionReady: Bool {
        (model.preferences.needsLocalForDictation || (model.keySaved && !model.transcriptionKeyOperationInProgress))
            && (model.preferences.usesFastDictation || (model.textKeySaved && !model.textKeyOperationInProgress))
    }

    private var setupRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            setupRow(L("받아쓰기 처리", "Dictation processing"), detail: model.preferences.usesFastDictation
                     ? L("이 Mac의 모델을 사용하며 API 키가 필요하지 않습니다.", "Uses a model on this Mac without an API key.")
                     : aiConnectionReady ? L("필요한 API 키가 모두 저장되어 있어요.", "All required API keys are saved.") : L("음성 인식과 문장 정리에 필요한 API 키를 저장해 주세요.", "Save the API keys needed for speech recognition and text cleanup."), ready: aiConnectionReady) {
                if model.preferences.usesFastDictation { model.page = .voice }
                else { openSettings(.connection) }
            }
            if !model.preferences.usesFastDictation, model.preferences.decisionReviewMode == .repair && !model.preferences.dictationOutputLanguage.isTranslation {
                Divider()
                setupRow(L("입력 전 교정", "Repair before typing"), detail: model.requiredJevIssue?.message ?? L("필요한 Jev 키와 연결 방식이 준비됐어요. 실제 연결은 검토 요청 때 확인합니다.", "The required Jev key and connection mode are ready. The connection is checked on a review request."), ready: model.requiredJevReady) { openSettings(.connection) }
            }
            Divider()
            setupRow(L("단축키", "Keyboard shortcuts"), detail: model.hotkeysRegistered ? L("받아쓰기 단축키: \(model.hotkeyLabel(index: 0))", "Dictation shortcut: \(model.hotkeyLabel(index: 0))") : L("단축키를 등록하지 못했습니다. 다른 조합으로 변경해 주세요.", "Shortcuts could not be registered. Choose another key combination."), ready: model.hotkeysRegistered) { openSettings(.input) }
            Divider()
            setupRow(L("마이크", "Microphone"), detail: model.microphonePermissionNeedsSettings ? L("시스템 설정에서 OpenNoType을 허용해 주세요.", "Allow OpenNoType in System Settings.") : L("녹음을 시작할 때만 마이크를 사용해요.", "The microphone is used only while recording."), ready: model.microphoneAllowed) {
                if model.microphonePermissionNeedsSettings { model.openMicrophoneSettings() }
                else { Task { await model.requestMicrophone() } }
            }
            Divider()
            setupRow(L("다른 앱에 입력", "Type into other apps"), detail: L("손쉬운 사용 권한으로 커서 위치에 글을 입력해요.", "Accessibility permission lets the app type at your cursor."), ready: model.accessibilityAllowed) { openSettings(.advanced) }
            if model.preferences.needsLocalForDictation {
                Divider()
                setupRow(L("로컬 음성 모델", "Local speech model"), detail: model.localState.label, ready: model.localState == .ready) { model.page = .voice }
            }
            if model.preferences.speakerFilterEnabled {
                Divider()
                setupRow(L("내 목소리 필터", "My voice filter"), detail: model.hasSpeakerProfile ? model.speakerState.label : L("목소리를 등록해 주세요.", "Register your voice."), ready: model.hasSpeakerProfile && model.speakerState == .ready) { model.page = .voice }
            }
        }
    }

    private func openSettings(_ section: SettingsSection) {
        model.settingsSection = section; model.page = .settings
    }

    private func modeRow(_ mode: InputMode, icon: String, detail: String, index: Int) -> some View {
        HStack(spacing: 8) {
            Label(mode.title, systemImage: icon).font(AppTypography.body)
            OptionHelp(title: mode.title, message: detail + "\n\n" + shortcutInstructions)
            Spacer(minLength: 8)
            Text(model.hotkeyLabel(index: index)).font(AppTypography.utility).textSelection(.enabled)
        }.frame(minHeight: AppLayout.rowHeight)
    }

    private func setupRow(_ title: String, detail: String, ready: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(AppTypography.body)
            OptionHelp(title: title, message: detail)
            if !ready {
                Text(detail).font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if ready {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accentForeground)
                    .accessibilityLabel(L("\(title) 준비됨", "\(title) is ready"))
            } else {
                Button(L("설정", "Set up"), action: action)
                    .accessibilityLabel(L("\(title) 설정", "Set up \(title)"))
                    .frame(minHeight: AppLayout.controlHeight)
            }
        }.frame(minHeight: AppLayout.rowHeight)
    }
}
