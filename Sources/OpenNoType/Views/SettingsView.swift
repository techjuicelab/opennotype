import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OpenNoTypeCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var recordingHotkey: Int?
    @State private var eventMonitor: Any?
    @State private var showWritingProfiles = false
    @State private var writingProfileApps: [WritingProfileApp] = []
    @State private var showsJevModelComparison = false
    @State private var showsJevPolicy = false
    @State private var showsJevLearning = false
    @State private var showsJevAlternatives = false
    private var isEditable: Bool { !model.preferencesRecoveryRequired && !AppLaunch.isPreview }
    private var connectionsEditable: Bool {
        isEditable && !AppLaunch.isPreview && model.startupState != .loading
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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("나에게 맞는 OpenNoType", "Make OpenNoType yours"))
                    .font(.system(size: 24, weight: .semibold))
                Text(L("입력 방식은 앱에서, Mac 접근 권한은 시스템 설정에서 관리해요.", "Manage input behavior here and Mac permissions in System Settings."))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Picker(L("설정 분류", "Settings category"), selection: $model.settingsSection) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }.pickerStyle(.segmented)
            Text(model.settingsSection.detail)
                .font(.system(size: 13)).foregroundStyle(.secondary)
            sectionContent
        }
        .onChange(of: model.settingsSection) { _, _ in stopHotkeyRecording() }
        .onChange(of: model.preferencesRecoveryRequired) { _, required in
            if required { stopHotkeyRecording() }
        }
        .onDisappear { stopHotkeyRecording() }
        .sheet(isPresented: $showsJevModelComparison) {
            JevModelComparisonView(model: model).disabled(!connectionsEditable)
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch model.settingsSection {
        case .connection:
            connectionSection
            decisionReviewSection
            Surface(L("사용량과 비용", "Usage and cost")) {
                OptionHelpLabel(L("모델별 사용량", "Usage by model"), help: L("음성 인식과 문장 처리에 사용한 모델별 요청·사용량을 확인하세요. 로컬 처리는 API 사용과 따로 표시합니다.", "View requests and usage for each speech and text model. On-device processing is shown separately from API usage."))
                Button(L("모델별 사용량 보기", "View usage by model"), systemImage: "chart.bar.xaxis") { model.page = .usage }
                    .disabled(!isEditable)
            }
        case .input:
            VoiceInputOptionsView(model: model)
            hotkeysSection
            DictationTranslationSettingsView(outputLanguage: $model.preferences.dictationOutputLanguage,
                                             isEditable: isEditable)
            TranslationRefinementSettingsView(isEnabled: $model.preferences.translationRefinementEnabled,
                                              reviewsBeforeTyping: model.preferences.translationProtectionEnabled && model.preferences.decisionReviewMode == .protect,
                                              isEditable: isEditable && !AppLaunch.isPreview && model.startupState == .ready)
            DictationExpressionSettingsView(expression: $model.preferences.dictationExpression,
                                           outputLanguage: model.preferences.dictationOutputLanguage,
                                           isFastDictation: model.preferences.usesFastDictation,
                                           isEditable: isEditable)
            translationSection
            writingProfilesSection
            diagnosticsSection
        case .privacy:
            transmissionSection
            contextSection
            learningSection
            usagePrivacySection
            retentionSection
        case .general:
            generalSection
            UpdateSettingsView(updater: .shared, isEditable: isEditable)
            permissionsSection
        }
    }

    private var decisionReviewSection: some View {
        Surface(L("Jev 문장 검토 · 실험 기능", "Jev text review · Experimental")) {
            HStack(spacing: 16) {
                OptionHelpLabel(L("Jev 연결 방식", "Jev connection"), help: model.preferences.decisionProvider == .typeSafe
                     ? L("인식 원문과 정리 결과, 관련 표기 후보를 TypeSafe의 Jev API에 직접 보내 의미 변경과 영문 표기를 검토합니다. 녹음과 다른 앱의 주변 문맥은 보내지 않습니다.", "Sends the transcript, cleaned-up text, and relevant spelling candidates directly to TypeSafe’s Jev API to review meaning changes and English spellings. Audio and surrounding text from other apps are not sent.")
                     : L("인식 원문과 정리 결과, 관련 표기 후보를 OpenRouter를 통해 TypeSafe의 Jev 모델에 추가로 보내 의미 변경과 영문 표기를 검토합니다. 녹음과 다른 앱의 주변 문맥은 보내지 않습니다.", "Also sends the transcript, cleaned-up text, and relevant spelling candidates to TypeSafe’s Jev model through OpenRouter to review meaning changes and English spellings. Audio and surrounding text from other apps are not sent."))
                Spacer(minLength: 12)
                Picker(L("Jev 연결 방식", "Jev connection"), selection: $model.preferences.decisionProvider) {
                    Text(L("OpenRouter 키 하나로 사용", "Use your OpenRouter key")).tag(DecisionProvider.openRouter)
                    Text(L("Jev API 키로 직접 연결", "Connect with a Jev API key")).tag(DecisionProvider.typeSafe)
                }
                .labelsHidden().frame(width: 240).disabled(!connectionsEditable)
                .onChange(of: model.preferences.decisionProvider) { _, provider in
                    if provider == .typeSafe { model.loadDecisionKey() }
                }
            }
            if model.preferences.decisionProvider == .typeSafe {
                KeyManagementDisclosure(title: L("Jev API 키 관리", "Manage Jev API key"),
                                        needsAttention: !model.decisionKeySaved || model.decisionKeyDraftIsChanged || model.decisionKeyOperationInProgress) {
                    HStack {
                        SecureField(L("Jev API 키 · TypeSafe", "Jev API key · TypeSafe"), text: $model.decisionAPIKeyDraft).textFieldStyle(.roundedBorder)
                        Button(model.decisionAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.decisionKeySaved ? L("저장된 키 삭제", "Delete saved key") : L("Keychain에 저장", "Save to Keychain")) { model.saveDecisionKey() }
                            .disabled(model.decisionAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.decisionKeySaved)
                    }.disabled(!connectionsEditable || model.decisionKeyOperationInProgress)
                    Button(L("저장된 Jev 키 다시 확인", "Reload saved Jev key")) { model.loadDecisionKey(force: true) }
                        .disabled(!connectionsEditable || model.decisionKeyOperationInProgress)
                        .controlSize(.small)
                    Text(L("음성 인식·문장 정리 제공자와 독립적으로 연결합니다. 다른 서비스의 키는 바뀌지 않습니다.", "This connection is independent of your speech and text providers. Keys for other services stay the same."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text(model.decisionKeyOperationInProgress ? L("TypeSafe 키를 준비하고 있어요. Keychain 인증창이 나타나면 승인해 주세요. 입력 전 교정은 키 준비가 끝난 뒤 시작할 수 있습니다.", "Loading your TypeSafe key. Approve the Keychain prompt if it appears. Repair before typing becomes available once the key is ready.")
                     : model.decisionKeyStatus ?? (model.decisionKeyDraftIsChanged ? L("변경한 키는 저장 후 다음 받아쓰기부터 적용됩니다.", "Save the changed key to use it for your next dictation.") : model.decisionKeySaved ? L("TypeSafe 키가 저장되어 있습니다. 실제 연결은 검토 요청 때 확인합니다.", "Your TypeSafe key is saved. The connection is checked when a review is requested.") : L("TypeSafe에서 발급한 Jev API 키를 저장해 주세요. 입력 전 교정과 켜 둔 번역 입력 전 검토는 키가 준비되지 않으면 자동 입력을 보류합니다. 그 밖의 기존 모드는 검토를 건너뜁니다.", "Save a Jev API key issued by TypeSafe. Repair before typing and enabled pre-typing translation review hold automatic input when the key is unavailable. Other existing modes skip review.")))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            } else {
                Text(L("문장 정리에 저장한 OpenRouter 키를 그대로 사용합니다. Jev 전용 키는 필요하지 않습니다.", "Uses the OpenRouter key saved for text cleanup. No separate Jev key is needed."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                OptionHelpLabel(L("문장 검토", "Text review"), help: JevRepairPresentation.modeDetail(model.preferences.decisionReviewMode))
                Spacer(minLength: 12)
                Picker(L("문장 검토", "Text review"), selection: $model.preferences.decisionReviewMode) {
                    ForEach(DecisionReviewMode.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 240)
                    .disabled(!connectionsEditable || (model.preferences.decisionProvider == .openRouter && model.preferences.effectiveTextProvider != .openRouter))
            }
            if model.preferences.decisionProvider == .openRouter && model.preferences.effectiveTextProvider != .openRouter {
                Text(L("OpenRouter 키 재사용은 문장 정리 제공자가 OpenRouter일 때 사용할 수 있습니다. 직접 연결은 다른 문장 정리 제공자와도 함께 쓸 수 있습니다.", "Reusing your OpenRouter key requires OpenRouter as the text cleanup provider. A direct connection also works with other text providers."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text(reviewStatus)
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            OptionToggle(L("번역도 입력 전에 검토", "Review translations before typing"),
                help: L("입력 전 보호에서만 사용하는 실험 기능이며 기본값은 꺼짐입니다. 인식 원문·번역 결과·목표 언어·선택한 말투를 선택한 Jev 검토 서비스로 추가 전송해 대기 시간과 API 비용이 추가될 수 있습니다. 위험 신호가 있거나 검토를 확인하지 못하면 자동 입력을 보류합니다. 정상 번역도 보류할 수 있으며 이 검토 자체는 번역을 교정하지 않습니다. 번역 문장 다듬기를 따로 켜면 다듬은 결과를 검토합니다.", "Experimental, available only in Protect before typing and off by default. Also sends the transcript, translation, target language, and selected tone to your selected Jev review service, which may add delay and API charges. A concern or an unverifiable review holds automatic typing. Correct translations may also be held. This review does not repair translations. If translation refinement is separately enabled, it reviews the refined result."),
                isOn: $model.preferences.translationProtectionEnabled,
                isEnabled: connectionsEditable && model.preferences.decisionReviewMode == .protect)
            if model.preferences.decisionReviewMode != .protect {
                Text(L("현재 미적용 · 입력 전 보호에서 사용", "Not applied · Available in Protect before typing"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else if model.preferences.translationProtectionEnabled {
                Label(L("실험 · 추가 전송·API 비용 · 위험·검토 실패 시 번역 입력 보류", "Experimental · Additional transfer and API cost · Translation is held on a concern or failed review"), systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.warm)
            }
            if model.preferences.dictationOutputLanguage.isTranslation {
                Text(model.preferences.decisionReviewMode == .protect && model.preferences.translationProtectionEnabled
                     ? L("현재 받아쓰기는 번역으로 출력하며 입력 전에 Jev 검토를 기다립니다. 말한 언어 유지 받아쓰기의 입력 전 교정·입력 후 검토는 번역에 적용하지 않습니다.", "Dictation currently outputs a translation and waits for Jev review before typing. Keep spoken language dictation's Repair before typing and Review after typing modes do not apply to translation.")
                     : L("현재 받아쓰기는 번역으로 출력합니다. 입력 전 보호를 선택하고 위 옵션을 켜면 번역도 입력 전에 검토합니다. 번역 결과는 최근 결과나 기록에서 직접 검토할 수도 있습니다.", "Dictation currently outputs a translation. Select Protect before typing and enable the option above to review translations before typing. You can also request a review from Latest result or History."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }
            if !model.preferences.dictationOutputLanguage.isTranslation, !model.preferences.usesFastDictation,
               model.preferences.decisionReviewMode == .observe && model.jevReviewMayDelayInput {
                Label(L("음성 재인식을 켜면 첫 Jev 판단과 필요한 재인식을 입력 전에 기다립니다. 이후 교정 검토는 이미 입력한 글을 바꾸지 않습니다.", "When audio re-recognition is enabled, typing waits for the first Jev judgment and any needed re-recognition. The later repair review does not change text already entered."), systemImage: "clock")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.warm).lineSpacing(4)
            }
            Text(L("검토 실행 시 API 비용이 추가됩니다. 입력 전 교정의 추가 비용 한도는 참고 단가로 US$0.05이며, 정확성을 보장하지는 않습니다.", "Reviews add API charges. Repair before typing has an extra-cost limit of US$0.05 at reference prices and does not guarantee accuracy."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            DisclosureGroup(L("검토·교정과 기록 보관 안내", "Review, repair and retention details"), isExpanded: $showsJevPolicy) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("입력 전 교정은 같은 문장 제공자·현재 모델로 최대 한 번 다시 생성한 뒤 Jev로 재검토합니다. 두 번째 생성은 하지 않으며, 교정·재검토가 끝날 때까지 입력을 기다립니다. 비용을 확인할 수 없거나 참고 단가로 예약한 추가 비용이 US$0.05를 넘으면 자동 입력을 보류합니다.", "Repair uses your current text provider and model to generate at most one corrected candidate, then reviews it with Jev. It never generates a second repair. Input waits for repair and recheck. If cost cannot be estimated, or the reserved extra cost at reference prices exceeds US$0.05, automatic input is held."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    Text(L("자동 교정과 입력 후 검토는 말한 언어 유지 받아쓰기에 적용합니다. 번역 입력 전 검토는 위 옵션을 켠 입력 전 보호에서만 실행합니다. 원문·교정안·진단은 처리 중 메모리에 두고, 원문·최종 결과의 기록 보관은 기존 설정을 따릅니다. 아래 오류 유형 학습은 별도의 선택이며, 문장을 저장하지 않습니다. 기록을 끄거나 모두 삭제하면 진행 중인 작업·진단·학습한 오류 유형도 지웁니다. API 비용이 추가되며, 검토·교정이 정확성을 보장하지는 않습니다.", "Automatic repair and review after typing apply to Keep spoken language dictation. Pre-typing translation review runs only in Protect before typing with the option above enabled. The source, repair candidate and diagnostics stay in memory during processing; history of the source and final result follows your existing settings. Error-pattern learning below is a separate choice and stores no sentences. Turning off or clearing all history cancels pending work and clears diagnostics and learned error categories. Additional API charges apply; review and repair do not guarantee accuracy."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    Text(L("자동 검토를 꺼 두어도 최근 받아쓰기, 보관된 받아쓰기 기록, 다시 처리한 미리보기에서 ‘Jev로 검토’를 직접 실행할 수 있습니다. 전송 전에 대상과 비용 안내를 확인하며, 영문 표기는 직접 확인해 개인 사전에 저장할 수 있습니다.", "Even with automatic review off, you can request a Jev review of your latest dictation, a saved dictation record or a reprocessed preview. Confirm the target and API cost notice before sending. You can also review spelling suggestions and choose which to save to your dictionary."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                }.padding(.top, 10)
            }.font(.system(size: 12))
            DisclosureGroup(isExpanded: $showsJevLearning) {
                JevFeedbackLearningSettingsView(model: model, isEditable: connectionsEditable).padding(.top, 10)
            } label: {
                HStack {
                    Text(L("오류 유형 학습", "Error-pattern learning"))
                    Spacer()
                    Text(model.preferences.jevFeedbackLearningEnabled ? L("사용 중 · 저장된 유형 \(model.jevLearnedIssues.count)개", "On · \(model.jevLearnedIssues.count) saved categories") : L("사용 안 함", "Off"))
                        .foregroundStyle(.secondary)
                }
            }.font(.system(size: 12))
            DisclosureGroup(L("보조 모델과 직접 비교", "Alternative model and comparison"), isExpanded: $showsJevAlternatives) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("개선안용 보조 모델", "Model for explicit alternatives")).font(.system(size: 12, weight: .semibold))
                    ProviderModelPicker(L("보조 모델", "Alternative model"), selection: Binding(get: {
                        model.preferences.improvementModel
                    }, set: { if connectionsEditable { model.preferences.improvementModels[model.preferences.effectiveTextProvider.rawValue] = $0 } }),
                    choices: ProviderModelChoice.textChoices(for: model.preferences.effectiveTextProvider))
                        .disabled(!connectionsEditable)
                    Button(L("현재 문장 모델과 동일하게", "Use current text model")) {
                        model.preferences.improvementModels.removeValue(forKey: model.preferences.effectiveTextProvider.rawValue)
                    }.controlSize(.small).disabled(!connectionsEditable)
                    Text(L("직접 요청한 개선안과 말한 언어 유지 받아쓰기의 입력 전 보호 자동 개선안 옵션에 사용합니다. 입력 전 교정·입력 후 검토는 현재 문장 모델을 사용하며, 같은 작업에서 두 번 생성하지 않습니다. 최근 번역·선택 수정도 직접 검토할 수 있고 당시 원문은 검토 중 메모리에만 보관합니다.", "Used for alternatives you request and for automatic alternatives in Protect before typing with Keep spoken language dictation. Repair before typing and Review after typing use your current text model, without generating twice for the same job. Recent translations and edits can also be reviewed explicitly; their source stays in memory during review."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    Button(L("내 문장으로 모델 비교…", "Compare models with my examples…"), systemImage: "chart.bar.xaxis") {
                        showsJevModelComparison = true
                    }.disabled(!connectionsEditable)
                    Text(L("직접 고른 문장과 원하는 결과로 소수의 모델을 비교합니다. 시작 전에 전송할 내용과 비용 한도를 확인하며, 추천 모델은 직접 적용합니다.", "Compare a few models using examples and expected results you choose. Review the content and spending limit before starting, then choose whether to apply a recommendation."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }.font(.system(size: 12))
            JevAssistanceSettingsView(model: model, isEditable: connectionsEditable)
            Divider()
            HStack {
                OptionHelpLabel(L("Jev 연결 테스트", "Test Jev connection"), help: L("고정된 합성 문장으로 선택한 연결과 저장된 키를 확인합니다. 녹음·자동 입력·문장 기록 저장은 하지 않으며, API 사용료와 사용량 기록이 발생할 수 있습니다. 검토를 꺼 둔 상태에서도 테스트할 수 있습니다.", "Checks the selected connection and saved key with a fixed synthetic sentence. It does not record audio, enter text, or save text history. API charges and usage records may apply. You can test the connection with text review turned off."))
                Spacer()
                Button(model.decisionConnectionTestInProgress ? L("확인 중…", "Testing…") : L("연결 테스트", "Test connection")) { model.testDecisionConnection() }
                    .disabled(!connectionsEditable || model.isBusy || model.keyOperationInProgress)
            }
            Text(L("테스트 실행 시 API 비용이 발생할 수 있습니다.", "The test may incur API charges."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if let status = model.decisionConnectionTestStatus {
                Text(status).font(.system(size: 12)).textSelection(.enabled)
            }
            if let summary = model.decisionReviewSummary {
                Divider()
                if let target = model.decisionReviewTarget {
                    Text(target.title).font(.system(size: 12, weight: .medium))
                }
                Text(summary).font(.system(size: 12)).textSelection(.enabled)
                Button(L("검토한 결과와 표기 제안 보기", "View reviewed result and spelling suggestions")) {
                    model.page = model.decisionReviewTarget?.kind == .recent ? .home : .history
                }.disabled(!connectionsEditable)
            }
        }
        .onAppear { if model.preferences.decisionProvider == .typeSafe { model.loadDecisionKey() } }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Surface(L("음성 인식", "Speech recognition")) {
                Picker(L("음성 인식 제공자", "Speech provider"), selection: $model.preferences.provider) {
                    ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented).disabled(!connectionsEditable).onChange(of: model.preferences.provider) { _, _ in
                    model.loadKey(); model.loadTextKey()
                }
                if model.preferences.provider == .anthropic {
                    Label(L("음성 인식은 이 Mac에서 처리", "Speech is processed on this Mac"), systemImage: "desktopcomputer")
                } else {
                    OptionToggle(L("음성 인식을 이 Mac에서 처리", "Process speech on this Mac"),
                        help: L("녹음을 이 Mac의 모델로 인식합니다. 문장 정리·번역에는 선택한 문장 서비스가 사용됩니다. 로컬 모델의 준비 상태는 음성 모델 화면에서 확인하세요.", "Recognizes audio with a model on this Mac. Text cleanup and translation use your selected text service. Check model readiness in Voice models."),
                        isOn: $model.preferences.useLocalTranscription, isEnabled: connectionsEditable)
                        .onChange(of: model.preferences.useLocalTranscription) { _, useLocal in
                            if !useLocal { model.loadKey() }
                        }
                }
                if !model.preferences.needsLocal {
                    KeyManagementDisclosure(title: L("음성 인식 API 키 관리", "Manage speech API key"),
                                            needsAttention: !model.keySaved || model.keyDraftIsChanged || model.transcriptionKeyOperationInProgress) {
                        HStack {
                            SecureField(L("\(model.preferences.provider.displayName) 음성 인식 API 키", "\(model.preferences.provider.displayName) speech API key"), text: $model.apiKeyDraft)
                                .textFieldStyle(.roundedBorder)
                            Button(model.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.keySaved ? L("저장된 키 삭제", "Delete saved key") : L("Keychain에 저장", "Save to Keychain")) { model.saveKey() }
                                .disabled(model.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.keySaved)
                        }.disabled(!connectionsEditable || model.transcriptionKeyOperationInProgress)
                    }.id(model.preferences.provider.rawValue)
                    Text(model.transcriptionKeyOperationInProgress ? L("Keychain을 확인하고 있어요. 인증창이 나타나면 승인해 주세요.", "Checking Keychain. Approve the authentication prompt if it appears.") : model.keyDraftIsChanged ? L("키가 변경되었습니다. 저장해야 다음 처리에 적용됩니다.", "The key has changed. Save it to use it for the next request.") : model.keySaved ? L("음성 인식 키가 저장되어 있습니다.", "Your speech API key is saved.") : L("음성 인식에 사용할 API 키를 저장해 주세요.", "Save an API key for speech recognition."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if model.preferences.provider == .groq {
                        ProviderModelPicker(L("음성 인식 모델", "Speech model"), selection: transcriptionModelBinding, choices: GroqModelChoices.transcription)
                            .id("groq-transcription")
                            .disabled(!connectionsEditable)
                        Link(L("Groq 연결 안내", "Groq setup guide"), destination: URL(string: "https://console.groq.com/docs/quickstart")!)
                            .font(.system(size: 12))
                    } else {
                        LabeledContent(L("음성 인식 모델", "Speech model")) {
                            TextField(L("모델 ID", "Model ID"), text: transcriptionModelBinding).textFieldStyle(.roundedBorder)
                        }.disabled(!connectionsEditable)
                    }
                    Text(L("녹음 파일은 \(model.preferences.provider.displayName)로 전송됩니다.", "Recordings are sent to \(model.preferences.provider.displayName)."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text(L("녹음 파일은 이 Mac에서 인식합니다. 인식한 글은 아래 문장 정리 서비스로 전송됩니다.", "Speech recognition runs on this Mac. The transcript is sent to the text cleanup service below."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Button(L("로컬 모델 준비 상태 보기", "View on-device model status"), systemImage: "desktopcomputer") { model.page = .voice }
                    .disabled(!connectionsEditable)
            }
            Surface(L("문장 정리", "Text cleanup")) {
                Picker(L("문장 정리 제공자", "Text cleanup provider"), selection: textProviderBinding) {
                    ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented).disabled(!connectionsEditable)
                if model.preferences.needsLocal || model.preferences.effectiveTextProvider != model.preferences.provider {
                    KeyManagementDisclosure(title: L("문장 정리 API 키 관리", "Manage text cleanup API key"),
                                            needsAttention: !model.textKeySaved || model.textKeyDraftIsChanged || model.textKeyOperationInProgress) {
                        HStack {
                            SecureField(L("\(model.preferences.effectiveTextProvider.displayName) 문장 정리 API 키", "\(model.preferences.effectiveTextProvider.displayName) text cleanup API key"), text: $model.textAPIKeyDraft)
                                .textFieldStyle(.roundedBorder)
                            Button(model.textAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.textKeySaved ? L("저장된 키 삭제", "Delete saved key") : L("Keychain에 저장", "Save to Keychain")) { model.saveTextKey() }
                                .disabled(model.textAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.textKeySaved)
                        }.disabled(!connectionsEditable || model.textKeyOperationInProgress)
                    }.id(model.preferences.effectiveTextProvider.rawValue)
                    Text(model.textKeyOperationInProgress ? L("Keychain을 확인하고 있어요. 인증창이 나타나면 승인해 주세요.", "Checking Keychain. Approve the authentication prompt if it appears.") : model.textKeyDraftIsChanged ? L("키가 변경되었습니다. 저장해야 다음 처리에 적용됩니다.", "The key has changed. Save it to use it for the next request.") : model.textKeySaved ? L("문장 정리 키가 저장되어 있습니다.", "Your text cleanup API key is saved.") : L("문장 정리에 사용할 API 키를 저장해 주세요.", "Save an API key for text cleanup."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text(L("음성 인식과 같은 API 키를 사용합니다.", "Uses the same API key as speech recognition."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if model.preferences.effectiveTextProvider == .groq {
                    ProviderModelPicker(L("문장 정리 모델", "Text cleanup model"), selection: textModelBinding, choices: GroqModelChoices.text)
                        .id("groq-text")
                        .disabled(!connectionsEditable)
                } else if model.preferences.effectiveTextProvider == .openRouter {
                    ProviderModelPicker(L("문장 정리 모델", "Text cleanup model"), selection: textModelBinding, choices: OpenRouterModelChoices.text)
                        .id("openrouter-text")
                        .disabled(!connectionsEditable)
                } else {
                    LabeledContent(L("문장 정리 모델", "Text cleanup model")) {
                        TextField(L("모델 ID", "Model ID"), text: textModelBinding).textFieldStyle(.roundedBorder)
                    }.disabled(!connectionsEditable)
                }
                Text(L("인식한 글은 \(model.preferences.effectiveTextProvider.displayName)로 전송해 받아쓰기 정리·번역에 사용합니다. 선택 문장 수정도 이 모델을 사용합니다. 모델 선택은 자동 저장됩니다.", "The transcript is sent to \(model.preferences.effectiveTextProvider.displayName) for dictation cleanup and translation. Editing selected text also uses this model. Model selections are saved automatically."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if model.preferences.effectiveTextProvider == .openRouter {
                    Text(L("OpenRouter는 선택한 모델의 공급자로 요청을 전달합니다. 같은 모델이어도 실제 처리 공급자는 달라질 수 있습니다.", "OpenRouter forwards requests to a provider hosting the selected model. The provider that handles a request may vary even for the same model."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                }
            }
            Text(L("대화 앱 구독과 API 사용료는 별개입니다. 음성 인식과 문장 정리의 각 제공자가 API 사용료를 부과합니다.", "Chat app subscriptions and API charges are separate. Each speech and text provider bills its own API usage."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var translationSection: some View {
        Surface {
            HStack(spacing: 16) {
                OptionHelpLabel(L("번역 단축키 출력 언어", "Translation shortcut output language"),
                    help: L("별도 번역 단축키로 녹음할 때 사용하는 언어입니다. 받아쓰기 출력 언어와 따로 설정하며, 의미와 말투를 유지해 자연스럽게 옮기도록 번역합니다. 표현은 AI 모델에 따라 달라질 수 있습니다.", "Used when recording with the separate translation shortcut. This is independent of your dictation output language. Translation aims to preserve meaning and tone in natural wording; wording can vary by AI model."))
                Spacer(minLength: 12)
                Picker(L("번역할 언어", "Translate into"), selection: $model.preferences.targetLanguage) {
                    Text(L("영어 · 미국식", "English · United States")).tag("English (United States)")
                    Text(L("영어 · 영국식", "English · United Kingdom")).tag("English (United Kingdom)")
                    Text(L("한국어", "Korean")).tag("Korean")
                    Text(L("일본어", "Japanese")).tag("Japanese")
                    Text(L("중국어 · 간체", "Chinese · Simplified")).tag("Chinese (Simplified)")
                    Text(L("중국어 · 번체", "Chinese · Traditional")).tag("Chinese (Traditional)")
                }.labelsHidden().frame(width: 220).disabled(!isEditable)
            }
        }
    }

    private var hotkeysSection: some View {
        Surface {
            OptionHelpLabel(L("단축키", "Keyboard shortcuts"), help: shortcutHelp)
            ForEach(Array(InputMode.allCases.enumerated()), id: \.element.id) { index, mode in
                HStack {
                    Text(mode.title).font(.system(size: 13)); Spacer()
                    Button(recordingHotkey == index ? L("새 단축키를 누르세요…", "Press a new shortcut…") : model.hotkeyLabel(index: index)) { recordHotkey(index) }
                        .font(.system(size: 12, design: .monospaced)).frame(minWidth: 150)
                        .accessibilityLabel(L("\(mode.title) 단축키 변경", "Change \(mode.title) shortcut"))
                        .accessibilityValue(recordingHotkey == index ? L("새 단축키 입력 대기", "Waiting for a new shortcut") : model.hotkeyLabel(index: index))
                        .disabled(!isEditable)
                }
            }
            Text(shortcutActivationSummary).font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(model.hotkeyConflicts, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
            }
            Button(L("다른 앱과 겹치는 단축키 확인", "Check for shortcut conflicts")) { model.refreshHotkeyConflicts() }
                .controlSize(.small).disabled(!isEditable)
        }
        .onAppear { model.refreshHotkeyConflicts() }
    }

    private var contextSection: some View {
        Surface {
            OptionHelpLabel(L("문맥 사용 · 앱별 허용", "Context access · Allowed apps"),
                help: L("허용한 앱에서만 커서 앞 최대 1,000자를 AI 제공자에게 함께 보냅니다. 보안 입력란은 제외하고, 문맥은 기록에 저장하지 않습니다.", "In allowed apps, up to 1,000 characters before the cursor are also sent to your AI provider. Secure fields are excluded, and context is not saved in history."))
            if model.preferences.allowedContextApps.isEmpty {
                Label(L("현재 허용된 앱이 없습니다", "No apps are currently allowed"), systemImage: "lock").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Text(L("허용한 앱의 주변 글을 AI에 추가 전송합니다.", "Surrounding text from allowed apps is also sent to AI."))
                    .font(.system(size: 12)).foregroundStyle(AppTheme.warm)
            }
            ForEach(model.preferences.allowedContextApps.sorted(), id: \.self) { bundle in
                HStack {
                    Image(systemName: "app"); Text(appName(bundle)).font(.system(size: 13)); Spacer()
                    Button(L("허용 해제", "Remove access")) { model.preferences.allowedContextApps.remove(bundle) }
                        .controlSize(.small).disabled(!isEditable)
                }
            }
            Button(L("앱 추가…", "Add apps…"), systemImage: "plus") { addContextApp() }.disabled(!isEditable)
        }
    }

    private var retentionSection: some View {
        Surface(L("기록과 보관", "History and retention")) {
            OptionToggle(L("음성 처리 결과 기록", "Save voice processing history"),
                help: L("받아쓰기·번역·문장 수정 결과와 제공된 프롬프트(검토 참고 사항 포함)를 저장합니다. 차단되거나 오류가 난 프롬프트 작업과 중간 초안은 기록하지 않습니다. 기록을 끄면 진행 중인 Jev 검토와 진단, 학습한 오류 유형도 지웁니다. 기존 텍스트 기록은 보관 기간에 따르며 개인 사전은 유지됩니다.", "Saves dictation, translation, voice edit results, and delivered prompts, including review notes. Blocked or failed prompt tasks and intermediate drafts are not saved. Turning history off also clears pending Jev reviews, diagnostics, and learned error categories. Existing text history follows the retention period; your personal dictionary is kept."),
                isOn: $model.preferences.historyEnabled, isEnabled: isEditable)
            Text(L("기록을 끄면 진행 중인 검토·진단과 학습한 오류 유형도 지웁니다.", "Turning history off also clears pending reviews, diagnostics, and learned error categories."))
                .font(.system(size: 12)).foregroundStyle(AppTheme.warm)
            HStack(spacing: 16) {
                OptionHelpLabel(L("텍스트 보관 기간", "Keep text history for"),
                    help: L("설정한 기간이 지난 텍스트 기록을 정리합니다. 성공한 녹음은 즉시 삭제합니다. 실패한 녹음은 암호화해 24시간 동안 복구할 수 있습니다. 앱 실행 중에는 만료된 파일을 정리하며, 앱이 꺼져 있으면 다음 실행 때 정리합니다.", "Text history is removed after the selected period. Successful recordings are deleted immediately. Failed recordings are encrypted and recoverable for 24 hours. Expired files are removed while the app is running, or the next time it opens."))
                Spacer(minLength: 12)
                Picker(L("텍스트 보관 기간", "Keep text history for"), selection: $model.preferences.retentionDays) {
                    Text(L("1일", "1 day")).tag(1); Text(L("7일", "7 days")).tag(7); Text(L("30일", "30 days")).tag(30); Text(L("90일", "90 days")).tag(90); Text(L("계속 보관", "Forever")).tag(-1)
                }.labelsHidden().frame(width: 180).disabled(!isEditable)
                    .onChange(of: model.preferences.retentionDays) { _, _ in Task { await model.refreshData() } }
            }
            Text(L("실패 녹음 · 24시간 암호화 보관", "Failed recordings · Encrypted for 24 hours"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var diagnosticsSection: some View {
        Surface(L("입력 문제 확인", "Input diagnostics")) {
            OptionHelpLabel(L("녹음 없이 입력 테스트", "Test typing without recording"), help: L("테스트를 준비한 뒤 원하는 입력창에서 받아쓰기 단축키를 누르세요. ‘OpenNoType 입력 테스트입니다.’를 입력하며 녹음·API 호출·메시지 전송은 하지 않습니다.", "Prepare the test, then press the dictation shortcut in the text field you want to test. It enters “This is an OpenNoType input test.” without recording audio, calling an API, or sending a message."))
            Text(L("테스트 문장을 실제 입력합니다 · 녹음·API 호출 없음", "Types a test sentence · No recording or API request"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button(model.inputTestArmed ? L("입력창에서 단축키를 눌러 주세요", "Press the shortcut in a text field") : L("녹음 없이 입력 테스트 준비", "Prepare input test without recording")) { model.armInputTest() }
                .disabled(!isEditable || model.inputTestArmed || model.isBusy)
            Button(L("5초 뒤 입력 테스트", "Test input in 5 seconds")) { model.scheduleInputTest() }.disabled(!isEditable || model.isBusy)
            if model.inputTestArmed {
                Button(L("입력 테스트 준비 취소", "Cancel input test")) { model.cancelInputTest() }
                    .disabled(!isEditable)
            }
            if !model.inputDiagnostics.isEmpty {
                Text(model.inputDiagnostics).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            }
            if let timings = model.lastProcessingTimings {
                Divider()
                Text(L("최근 처리 시간", "Latest processing times")).font(.system(size: 12, weight: .medium))
                Text(timings).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Text(L("입력·확인에는 붙여넣은 뒤의 확인 대기가 포함됩니다. 화면에 글이 보인 시각과 다를 수 있습니다.", "Input verification includes the wait after pasting. It may differ from when the text appeared on screen."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
    }

    private var transmissionSection: some View {
        Surface(L("AI로 보내는 정보", "Information sent to AI")) {
            Label(model.preferences.needsLocalForDictation ? L("음성 인식은 이 Mac에서 처리", "Speech is processed on this Mac") : L("녹음은 \(model.preferences.provider.displayName) 서비스로 전송", "Recordings are sent to \(model.preferences.provider.displayName)"), systemImage: model.preferences.needsLocalForDictation ? "desktopcomputer" : "network")
                .font(.system(size: 13, weight: .medium))
            Text(model.preferences.usesFastDictation
                 ? L("빠른 로컬 받아쓰기는 음성·문장을 외부 AI로 보내지 않습니다. 번역·선택 문장 수정·프롬프트 만들기는 별도의 AI 처리를 사용합니다.", "Quick on-device dictation sends neither audio nor text to an external AI. Translation, selected-text edits and prompt creation use their separate AI processing.")
                 : L("인식한 글과 요청은 문장 처리를 위해 \(model.preferences.effectiveTextProvider.displayName) 서비스로 보냅니다. 선택 문장 수정은 선택한 문장도 함께 보냅니다.", "The transcript and request are sent to \(model.preferences.effectiveTextProvider.displayName) for text processing. Rewriting also sends the selected text."))
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            if model.preferences.translationRefinementEnabled {
                OptionHelpLabel(L("번역 다듬기의 추가 전송", "Additional transfer for translation refinement"), help: L("번역 문장 다듬기는 같은 문장 서비스로 인식 원문·번역 초안·목표 언어·말투·사전 힌트를 한 번 더 보냅니다. 녹음과 주변 문맥을 다시 전송하지 않으며 추가 처리 시간과 API 비용이 발생할 수 있습니다. 초안과 다듬기 과정은 메모리에만 표시하고 별도로 보관하지 않습니다.", "Translation refinement sends the transcript, draft translation, target language, tone and dictionary hints once more to the same text service. It does not resend audio or surrounding context and may add delay and API charges. The draft and refinement details are shown in memory only and are not saved separately."))
                Text(L("번역 다듬기 · 추가 전송·API 비용", "Translation refinement · Additional transfer and API cost"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if model.preferences.provider == .openRouter || model.preferences.effectiveTextProvider == .openRouter {
                Text(L("OpenRouter는 선택한 모델을 제공하는 공급자로 요청을 전달합니다.", "OpenRouter forwards requests to a provider hosting the selected model."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if model.preferences.decisionReviewMode != .off {
                OptionHelpLabel(L("Jev 검토의 추가 전송", "Additional transfer for Jev review"), help: L("Jev 문장 검토를 켜면 받아쓰기 원문·정리 결과와 관련 표기 후보를 \(model.preferences.decisionProvider == .typeSafe ? "TypeSafe에 직접" : "OpenRouter 경유 TypeSafe에") 추가 전송합니다. 검토 결과는 메모리에만 두고, 새 작업·기록 삭제·검토 중단 시 지웁니다.", "When Jev text review is enabled, the transcript, cleaned-up text, and relevant spelling candidates are also sent \(model.preferences.decisionProvider == .typeSafe ? "directly to TypeSafe" : "to TypeSafe through OpenRouter"). Review results stay in memory only and are cleared when a new job starts, history is deleted, or review is stopped."))
                Text(L("Jev 검토 · 원문·결과·표기 후보 추가 전송", "Jev review · Transcript, result, and spelling candidates are also sent"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if model.preferences.decisionReviewMode == .repair || model.preferences.decisionReviewMode == .observe {
                OptionHelpLabel(L("교정안 생성과 재검토", "Repair generation and recheck"), help: L("Jev가 강한 오류 신호를 발견하면 같은 문장 제공자에 원문·기존 결과·정해진 오류 유형을 보내 교정안을 한 번 만들고 Jev에 재검토합니다. 입력 전 교정은 검토를 마친 결과만 자동 입력하며, 입력 후 검토는 이미 입력한 글을 바꾸지 않습니다.", "When Jev detects a strong concern, the source, current result and predefined error categories are sent to the same text provider for one repair, then to Jev for recheck. Repair before typing enters only a result that completes review; review after typing never changes text already entered."))
                Text(model.preferences.decisionReviewMode == .repair ? L("입력 전 교정 · 확인한 결과만 자동 입력", "Repair before typing · Only verified results are typed") : L("입력 후 검토 · 이미 입력한 글 유지", "Review after typing · Typed text stays unchanged"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if model.preferences.jevFeedbackLearningEnabled {
                OptionHelpLabel(L("오류 유형의 보관과 반영", "Storage and use of error categories"), help: L("해결한 오류 유형은 문장 제공자·모델별로 이 Mac에 암호화해 저장합니다. 숫자·부정·조건 같은 정해진 유형만 다음 문장 정리의 주의사항으로 보내며, 과거 원문·교정안은 학습 저장소에 남기지 않습니다. AI 모델 자체를 재학습하는 기능은 아닙니다.", "Resolved error categories are encrypted on this Mac, scoped to the text provider and model. Only predefined categories, such as numbers, negation and conditions, are sent as reminders in future cleanup requests; past sources and repair candidates are not retained by the learning store. This does not train the AI model itself."))
                Text(L("오류 유형만 암호화 보관 · 원문·교정안 저장 안 함", "Only error categories are encrypted · Sources and repair candidates are not saved"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Button(L("AI 연결과 음성 인식 방식 변경", "Change AI connections and speech processing")) { model.settingsSection = .connection }
                .disabled(!isEditable)
        }
    }

    private var learningSection: some View {
        Surface(L("개인 사전 학습", "Dictionary learning")) {
            OptionToggle(L("안전한 이름·표기 교정 자동 학습", "Automatically learn safe name and spelling corrections"),
                help: L("입력 직후 직접 고친 이름과 표기 중 확실한 교정만 개인 사전에 반영합니다. 의미가 달라질 수 있는 변경은 검토 후 저장할 수 있습니다.", "Only clear name and spelling corrections you make immediately after input are added automatically to your personal dictionary. Changes that may affect meaning can be reviewed before saving."),
                isOn: $model.preferences.automaticLearningEnabled, isEnabled: isEditable)
            HStack {
                Button(L("개인 사전과 교정 검토", "Review dictionary and corrections"), systemImage: "character.book.closed") { model.page = .dictionary }
                    .disabled(!isEditable)
                if model.canUndoLastLearning {
                    Button(L("최근 자동 학습 되돌리기", "Undo latest automatic learning")) { Task { await model.undoLastLearning() } }
                        .disabled(!isEditable)
                }
            }
        }
    }

    private var usagePrivacySection: some View {
        Surface(L("사용량 통계", "Usage statistics")) {
            OptionToggle(L("사용량 통계 기록", "Record usage statistics"),
                help: L("모델·요청 횟수·토큰·음성 처리 시간 등의 사용 정보만 이 Mac에 암호화해 보관합니다. 통계에는 문장 내용과 녹음 원음을 포함하지 않습니다. 결과 기록 설정과 별도로 최대 10,000건을 보관합니다. 끄면 새 요청 수집을 중단합니다. 이미 수집해 저장 중인 기록은 늦게 반영될 수 있고, 기존 통계는 유지됩니다.", "Only usage details such as models, request counts, tokens, and audio processing time are encrypted on this Mac. Statistics exclude text content and audio. Up to 10,000 usage records are kept independently of text history. Turning this off stops collecting new requests. Records already being saved may appear later; existing statistics remain."),
                isOn: $model.preferences.usageTrackingEnabled, isEnabled: isEditable)
            Text(L("문장·녹음 원음을 제외한 사용 정보만 보관", "Keeps usage details without text or audio"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button(L("사용량과 보관 중인 통계 보기", "View usage and saved statistics"), systemImage: "chart.bar.xaxis") { model.page = .usage }
                .disabled(!isEditable)
        }
    }

    private var generalSection: some View {
        Surface(L("앱 실행과 화면", "Startup and appearance")) {
            HStack(spacing: 16) {
                OptionHelpLabel(L("앱 언어", "App language"), help: L("언어 변경은 바로 적용됩니다. 받아쓰기 출력 언어·번역할 언어·음성 인식 방식은 바뀌지 않습니다.", "Language changes apply immediately. Dictation output language, translation language, and speech recognition settings stay the same."))
                Spacer(minLength: 12)
                Picker(L("앱 언어", "App language"), selection: $model.preferences.interfaceLanguage) {
                    Text(AppLanguage.english.title).tag(AppLanguage.english)
                    Text(AppLanguage.korean.title).tag(AppLanguage.korean)
                }.labelsHidden().frame(width: 180).disabled(!isEditable)
            }
            Divider()
            OptionToggle(L("Mac에 로그인할 때 실행", "Open at login"),
                help: L("창을 열지 않고 메뉴바에서 대기합니다. 필요할 때 메뉴바에서 OpenNoType을 여세요.", "Starts in the menu bar without opening a window. Open OpenNoType from the menu bar when needed."),
                isOn: Binding(get: { model.launchAtLoginEnabled }, set: { if isEditable { model.setLaunchAtLogin($0) } }),
                isEnabled: isEditable)
            if let status = model.loginItemStatusText {
                Label(status, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            Button(L("로그인 항목 시스템 설정 열기", "Open Login Items in System Settings"), systemImage: "arrow.up.forward.square") { model.openLoginItemSettings() }
                .disabled(!isEditable)
            Divider()
            HStack(spacing: 16) {
                OptionHelpLabel(L("화면 모드", "Appearance"), help: L("시스템 설정에 맞추거나 라이트·다크 모드를 지정합니다. 일반 설정은 자동 저장하며 API 키는 ‘Keychain에 저장’을 눌러 적용합니다.", "Follow the system appearance or select Light or Dark. General settings save automatically; API key changes apply after you choose Save to Keychain."))
                Spacer(minLength: 12)
                Picker(L("화면 모드", "Appearance"), selection: $model.preferences.appearance) {
                    Text(L("시스템 설정에 맞춤", "System")).tag("system")
                    Text(L("라이트", "Light")).tag("light")
                    Text(L("다크", "Dark")).tag("dark")
                }.labelsHidden().frame(width: 180).disabled(!isEditable)
            }
            Text(L("설정 자동 저장 · API 키는 별도 저장", "Settings save automatically · API keys save separately"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var permissionsSection: some View {
        Surface(L("Mac 접근 권한", "Mac permissions")) {
            permissionStatus(L("마이크", "Microphone"), detail: L("단축키나 버튼으로 시작한 녹음에 사용합니다.", "Used for recordings you start with a shortcut or button."), allowed: model.microphoneAllowed)
            HStack {
                if !model.microphoneAllowed && !model.microphonePermissionNeedsSettings {
                    Button(L("마이크 사용 요청", "Request microphone access")) { Task { await model.requestMicrophone() } }
                        .disabled(!isEditable)
                }
                Button(L("마이크 시스템 설정 열기", "Open Microphone in System Settings"), systemImage: "arrow.up.forward.square") { model.openMicrophoneSettings() }
                    .disabled(!isEditable)
            }
            Divider()
            permissionStatus(L("손쉬운 사용", "Accessibility"), detail: L("선택한 문장을 읽고, 다른 앱의 커서 위치에 글을 입력합니다.", "Reads selected text and enters text at the cursor in other apps."), allowed: model.accessibilityAllowed)
            Button(L("손쉬운 사용 시스템 설정 열기", "Open Accessibility in System Settings"), systemImage: "arrow.up.forward.square") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }.disabled(!isEditable)
            Divider()
            Text(L("시스템 설정 › 개인정보 보호 및 보안에서 OpenNoType을 허용한 뒤 돌아오세요. 앱이 활성화되면 권한 상태를 다시 확인합니다.", "Allow OpenNoType in System Settings › Privacy & Security, then return here. Permissions are checked again when the app becomes active."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            HStack {
                Button(L("권한 상태 다시 확인", "Refresh permission status"), systemImage: "arrow.clockwise") { model.refreshPermissions() }
                    .disabled(!isEditable)
                Button(L("연결부터 입력까지 한 번에 확인", "Check connections through typing")) { model.page = .home }
                    .disabled(!isEditable)
            }
        }
        .onAppear { model.refreshPermissions() }
    }

    private func permissionStatus(_ title: String, detail: String, allowed: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                OptionHelpLabel(title, help: detail + "\n\n" + L("시스템 설정 › 개인정보 보호 및 보안에서 OpenNoType을 허용한 뒤 돌아오세요. 앱이 활성화되면 권한 상태를 다시 확인합니다.", "Allow OpenNoType in System Settings › Privacy & Security, then return here. Permissions are checked again when the app becomes active."))
            }.frame(maxWidth: .infinity, alignment: .leading)
            Label(allowed ? L("허용됨", "Allowed") : L("허용 필요", "Access needed"), systemImage: allowed ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(allowed ? AppTheme.accentForeground : .orange)
        }
    }

    private var transcriptionModelBinding: Binding<String> {
        Binding(get: { model.preferences.transcriptionModel }, set: { if connectionsEditable { model.preferences.transcriptionModels[model.preferences.provider.rawValue] = $0 } })
    }

    private var textProviderBinding: Binding<AIProvider> {
        Binding(get: { model.preferences.effectiveTextProvider }, set: {
            guard connectionsEditable else { return }
            model.preferences.textProvider = $0
            model.loadTextKey()
            if $0 == model.preferences.provider { model.loadKey() }
        })
    }

    private var textModelBinding: Binding<String> {
        Binding(get: { model.preferences.textModel }, set: { if connectionsEditable { model.preferences.textModels[model.preferences.effectiveTextProvider.rawValue] = $0 } })
    }

    private var writingProfilesSection: some View {
        Surface {
            OptionHelpLabel(L("앱별 작성 방식", "Writing style by app"), help: L("녹음을 시작한 앱에 맞춰 문장과 형식을 정리합니다. 기본적으로 반말·존댓말은 말한 그대로 유지하며, 아래에서 말투를 지정한 앱에서만 바꿉니다. 앱 이름만 구분하므로 브라우저의 웹사이트나 대화 상대는 판단하지 않습니다. 이 설정으로 주변 텍스트를 읽지는 않습니다. 문맥 사용은 개인정보 설정에서 별도로 허용할 수 있습니다.", "Adjusts wording and formatting for the app where recording began. Your spoken formality is preserved unless you choose a tone for that app below. Only the app is identified; websites and conversation partners are not detected. This setting does not read surrounding text. Context access is allowed separately in Privacy settings."))
            if model.preferences.usesFastDictation {
                Text(L("바로 입력 중에는 앱별 문장 정리·말투 미적용", "App-specific cleanup and tone are not applied to direct input"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else if model.preferences.dictationOutputLanguage.isTranslation {
                Text(L("받아쓰기 표현 설정 미적용 · 앱별 말투는 번역에 적용", "Dictation wording settings are not applied · App-specific tone applies to translation"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            DisclosureGroup(L("앱별 설정 \(writingProfileApps.count)개 보기", "View settings for \(writingProfileApps.count) apps"), isExpanded: $showWritingProfiles) {
                VStack(alignment: .leading, spacing: 18) {
            ForEach(writingProfileApps) { app in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.system(size: 12))
                        Text(model.preferences.writingProfiles[app.id] == nil ? L("기본 설정", "Default") : L("사용자 설정", "Custom"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Picker(L("\(app.name) 작성 형식", "\(app.name) writing style"), selection: profileKindBinding(app.id)) {
                        ForEach(WritingProfileKind.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 100).disabled(!isEditable)
                    Picker(L("\(app.name) 말투", "\(app.name) tone"), selection: profileToneBinding(app.id)) {
                        ForEach(WritingTone.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 160).disabled(!isEditable)
                    Button(L("복원", "Reset")) {
                        model.preferences.writingProfiles.removeValue(forKey: app.id)
                        refreshWritingProfileApps()
                    }
                    .controlSize(.small)
                    .disabled(!isEditable || model.preferences.writingProfiles[app.id] == nil)
                    .help(L("이 앱의 작성 방식을 기본값으로 복원", "Reset this app’s writing style to its default"))
                    .accessibilityLabel(L("\(app.name) 기본값 복원", "Reset \(app.name) to defaults"))
                }
            }
                }.padding(.top, 14)
            }
            if writingProfileApps.isEmpty {
                Text(L("앱을 추가해 작성 방식과 말투를 지정할 수 있습니다.", "Add apps to customize their writing style and tone."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Button(L("앱 추가…", "Add apps…"), systemImage: "plus") { addWritingProfileApp() }
                .disabled(!isEditable)
        }
        .onAppear { refreshWritingProfileApps() }
    }

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
        showWritingProfiles = true
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


private struct KeyManagementDisclosure<Content: View>: View {
    let title: String
    let needsAttention: Bool
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10, content: content).padding(.top, 10)
        } label: {
            Label(title, systemImage: "key")
        }
        .font(.system(size: 12))
        .onAppear { isExpanded = needsAttention }
        .onChange(of: needsAttention) { _, needsAttention in isExpanded = needsAttention }
    }
}

struct VoiceSettingsView: View {
    @Bindable var model: AppModel
    private var isEditable: Bool { !model.preferencesRecoveryRequired && !AppLaunch.isPreview }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L("이 Mac에서 듣고 구분해요", "Speech processing on this Mac")).font(.system(size: 23, weight: .semibold)).tracking(-0.6)
            Text(L("모델은 처음 한 번 내려받습니다. 로컬 모델의 음성 처리는 기기에서 이루어집니다.", "Models are downloaded once. On-device models process audio locally."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Surface(L("현재 음성 인식 방식", "Current speech recognition method")) {
            Label(model.preferences.needsLocalForDictation ? L("로컬 음성 인식 사용 중", "Using on-device speech recognition") : L("\(model.preferences.provider.displayName) API 음성 인식 사용 중", "Using \(model.preferences.provider.displayName) API speech recognition"), systemImage: model.preferences.needsLocalForDictation ? "desktopcomputer" : "network")
                .font(.system(size: 14, weight: .medium))
            Text(L("모델을 다운로드해도 사용 방식이 자동으로 바뀌지는 않습니다. AI 연결 설정에서 로컬 인식을 선택하세요.", "Downloading a model does not change how speech is processed. Select on-device recognition in AI connection settings."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Text(model.preferences.usesFastDictation ? L("빠른 로컬 받아쓰기는 음성·문장을 외부 AI로 보내지 않습니다.", "Quick on-device dictation sends neither audio nor text to an external AI.") : L("로컬 음성 인식에는 API 인식 비용이 들지 않습니다. 이후 문장 처리는 선택한 AI 제공자의 API를 사용합니다.", "On-device speech recognition has no speech API charges. Text cleanup afterward uses your selected AI provider’s API."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Button(L("음성 인식 방식 변경", "Change speech recognition method")) { model.settingsSection = .connection; model.page = .settings }
                .disabled(!isEditable)
        }
        LocalModelOptionsView(model: model)
        SpeechComparisonLabView(lab: model.speechLab, preferences: model.preferences,
                                appBusy: model.phase != .idle || model.startupState == .loading || model.decisionConnectionTestInProgress)
            .disabled(model.preferencesRecoveryRequired || AppLaunch.isPreview)
        Surface(L("내 목소리 구분 · 실험 단계", "Recognize my voice · Experimental")) {
            OptionHelpLabel(L("등록한 내 목소리 필터", "Enrolled voice filter"), help: LocalSpeakerRecognizer.limitation + "\n\n" + L("조용한 곳에서 혼자 10~20초 동안 자연스럽게 말해 주세요. 등록 녹음은 삭제하고 목소리 특징만 암호화해 저장합니다.", "Speak naturally by yourself in a quiet place for 10–20 seconds. The enrollment recording is deleted; only encrypted voice features are saved."))
            Text(L("현재 빌드는 실제 사용자·TV·겹말 환경의 성능 검증 전입니다. 필터는 기본적으로 꺼져 있습니다.", "This build has not been validated with real users, TV audio, or overlapping speech. The filter is off by default."))
                .font(.system(size: 12)).foregroundStyle(.orange)
            modelStatus(model.speakerState)
            Button(model.speakerState == .ready ? L("화자 모델 준비됨", "Speaker model ready") : L("화자 모델 다운로드 / 준비 · 약 14 MB", "Download / prepare speaker model · About 14 MB"), action: model.prepareSpeaker)
                .disabled(!isEditable || model.speakerState.working || model.speakerState == .ready)
            if model.speakerState.working { Button(L("화자 모델 준비 취소", "Cancel speaker model preparation")) { model.cancelSpeakerPreparation() }.disabled(!isEditable) }
            Divider()
            HStack {
                Label(model.hasSpeakerProfile ? L("내 목소리가 등록되어 있습니다", "Your voice is enrolled") : L("아직 등록된 목소리가 없습니다", "No voice is enrolled yet"), systemImage: model.hasSpeakerProfile ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.system(size: 12))
                Spacer()
                if model.hasSpeakerProfile {
                    Button(L("삭제", "Delete"), role: .destructive) { Task { await model.deleteVoice() } }
                        .disabled(!isEditable || model.isBusy)
                }
            }
            HStack {
                Button(model.hasSpeakerProfile ? L("다시 등록", "Enroll again") : L("목소리 등록 시작", "Start voice enrollment")) { Task { await model.enrollVoice() } }
                    .disabled(!isEditable || model.speakerState != .ready || model.isBusy)
                if model.phase == .enrolling { Button(L("등록 녹음 종료", "Stop enrollment recording")) { model.stop() }.disabled(!isEditable) }
            }
            OptionToggle(L("등록한 내 목소리 필터 사용", "Use my enrolled voice filter"), help: LocalSpeakerRecognizer.limitation,
                isOn: $model.preferences.speakerFilterEnabled,
                isEnabled: isEditable && model.hasSpeakerProfile && model.speakerState == .ready)
        }
        Surface(L("모델과 라이선스", "Models and licenses")) {
            Text(L("WhisperKit / Whisper 모델: MIT\nFluidAudio 코드: Apache-2.0\n화자 모델: CC BY 4.0 — FluidInference, pyannote, WeSpeaker", "WhisperKit / Whisper models: MIT\nFluidAudio code: Apache-2.0\nSpeaker models: CC BY 4.0 — FluidInference, pyannote, WeSpeaker"))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
            Link(L("음성 모델 출처", "Speech model source"), destination: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!)
            Link(L("화자 모델 출처", "Speaker model source"), destination: URL(string: "https://huggingface.co/FluidInference/speaker-diarization-coreml")!)
        }
    }
    @ViewBuilder private func modelStatus(_ state: LocalModelState) -> some View {
        HStack {
            if state.working { ProgressView().controlSize(.small) }
            Text(state.label).font(.system(size: 12)).foregroundStyle(state == .ready ? AppTheme.accentForeground : .secondary)
        }
        if case .downloading(let progress) = state { ProgressView(value: progress) }
    }
}

private extension LocalModelState {
    var working: Bool {
        switch self { case .downloading, .loading: true; default: false }
    }
}
