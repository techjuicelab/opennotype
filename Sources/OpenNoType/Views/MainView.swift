import AppKit
import SwiftUI
import OpenNoTypeCore

enum AppTheme {
    static let accent = Color(red: 0.31, green: 0.48, blue: 0.40)
    static let accentForeground = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.58, green: 0.78, blue: 0.66, alpha: 1)
        }
        return NSColor(srgbRed: 0.25, green: 0.41, blue: 0.33, alpha: 1)
    })
    static let warm = Color(red: 0.75, green: 0.55, blue: 0.33)
}

struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var confirmsRecoveredSettings = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 212)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(model.page.title).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Circle().fill(model.isRecording ? .red : AppTheme.accent).frame(width: 6, height: 6)
                    Text(model.isBusy ? model.status : L("음성: \(model.preferences.needsLocal ? "이 Mac" : model.preferences.provider.displayName) · 문장: \(model.preferences.effectiveTextProvider.displayName)", "Speech: \(model.preferences.needsLocal ? L("이 Mac", "This Mac") : model.preferences.provider.displayName) · Text: \(model.preferences.effectiveTextProvider.displayName)"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.horizontal, 30).frame(height: 56)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            preferencesRecovery
                            startupStatus
                            if let error = model.error { NoticeView(text: error, isError: true) { model.error = nil } }
                            if let notice = model.notice { NoticeView(text: notice, isError: false) { model.notice = nil } }
                            page.disabled(model.preferencesRecoveryRequired)
                        }.padding(30).frame(maxWidth: 920, alignment: .leading).frame(maxWidth: .infinity).id("page-top")
                    }
                    .onChange(of: model.page) { _, _ in proxy.scrollTo("page-top", anchor: .top) }
                    .onChange(of: model.settingsSection) { _, _ in proxy.scrollTo("page-top", anchor: .top) }
                    .onChange(of: model.phase) { _, phase in
                        if phase == .idle, model.page == .home, model.promptComposition != nil {
                            proxy.scrollTo("page-top", anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(AppTheme.accent)
        .onAppear {
            model.showManager = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        }
        .confirmationDialog(L("표시된 복구 설정으로 시작할까요?", "Start with the recovered settings shown here?"), isPresented: $confirmsRecoveredSettings, titleVisibility: .visible) {
            Button(L("복구 설정 저장하고 시작", "Save recovered settings and start")) { model.acceptRecoveredPreferences() }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("읽지 못한 항목에는 기본값을 사용합니다. 보관 기간은 \(recoveredRetentionDescription)이며, 복구 후 해당 기간에 따른 기록 정리가 재개됩니다. 손상된 설정 원본은 보존됩니다.", "Unreadable settings use defaults. History retention will be \(recoveredRetentionDescription); cleanup under that policy resumes after recovery. The damaged settings source is preserved."))
        }
    }
    @ViewBuilder private var preferencesRecovery: some View {
        if model.preferencesRecoveryRequired {
            Surface(L("저장된 설정을 복구해 주세요", "Recover your saved settings")) {
                Label(L("설정 일부를 읽지 못해 녹음과 데이터 변경을 잠시 멈췄어요. 기존 설정 원본과 기록은 보존했습니다.", "Some settings could not be read, so recording and data changes are paused. Your original settings and records are preserved."), systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 13)).foregroundStyle(AppTheme.warm).fixedSize(horizontal: false, vertical: true)
                Text(L("복구안: 음성 \(model.preferences.provider.displayName) · 문장 \(model.preferences.effectiveTextProvider.displayName) · 보관 \(recoveredRetentionDescription)", "Recovered settings: speech \(model.preferences.provider.displayName) · text \(model.preferences.effectiveTextProvider.displayName) · retention \(recoveredRetentionDescription)"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                Text(L("이전 정상 설정이 있으면 먼저 복원하세요. 복구안을 선택한 뒤에는 AI 연결과 보관 기간을 확인해 주세요.", "Restore the previous valid settings when available. After accepting recovered settings, check your AI connections and retention period."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    if model.canRestorePreviousPreferences {
                        Button(L("이전 정상 설정 복원", "Restore previous valid settings")) { model.restorePreviousPreferences() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button(L("복구안 확인 후 시작…", "Review and accept recovered settings…")) { confirmsRecoveredSettings = true }
                }
            }
        }
    }
    private var recoveredRetentionDescription: String {
        model.preferences.retentionDays == -1 ? L("계속 보관", "Forever") : L("\(model.preferences.retentionDays)일", "\(model.preferences.retentionDays) days")
    }
    @ViewBuilder private var startupStatus: some View {
        if !model.preferencesRecoveryRequired && model.startupState != .ready {
            Surface(L("앱 준비", "Getting ready")) {
                if model.startupState == .loading {
                    HStack(alignment: .top, spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(L("Keychain과 저장된 설정을 준비하고 있어요. 인증창이 나타나면 이 Mac에서 승인해 주세요.", "Preparing Keychain and your saved settings. If an authorization dialog appears, approve it on this Mac."))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                } else {
                    Text(model.startupError ?? L("저장된 데이터를 열지 못했습니다. Keychain 접근을 확인한 뒤 다시 시도해 주세요.", "Could not open saved data. Check Keychain access, then try again."))
                        .font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                    Button(L("앱 준비 다시 시도", "Try again"), systemImage: "arrow.clockwise") { model.retryStartup() }
                }
            }
        } else if model.keyOperationInProgress {
            Surface(L("AI 연결 준비", "Preparing AI connections")) {
                HStack(alignment: .top, spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(L("Keychain을 확인하고 있어요. 인증창이 나타나면 이 Mac에서 승인해 주세요.", "Checking Keychain. If an authorization dialog appears, approve it on this Mac."))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: AppBrand.icon)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 34, height: 34).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("OpenNoType").font(.system(size: 16, weight: .semibold))
                    Text(AppIdentity.current.isPromptTest ? L("Prompt Test · 테스트용", "Prompt Test · Testing") : L("말을 글로, 나답게", "Your voice, in your words"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.top, 27).padding(.bottom, 25)
            sidebarGroup(L("활동", "Activity"), pages: [.home, .history, .usage])
            sidebarGroup(L("도구", "Tools"), pages: [.dictionary, .recovery])
            sidebarGroup(L("앱 관리", "App"), pages: [.voice, .settings])
            Spacer(minLength: 16)
            VStack(alignment: .leading, spacing: 9) {
                Label(L("기록은 이 Mac에 보관", "Records stay on this Mac"), systemImage: "lock.shield")
                    .font(.system(size: 12, weight: .medium))
                Button(L("전송·보관 설정 보기", "Transfer & storage settings")) {
                    model.settingsSection = .privacy; model.page = .settings
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(AppTheme.accentForeground).disabled(AppLaunch.isPreview)
                Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L("개발", "Development")) (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.bottom, 23)
        }.background(AppTheme.accent.opacity(0.035))
    }
    private func sidebarGroup(_ title: String, pages: [AppPage]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 24).padding(.bottom, 4)
            ForEach(pages) { page in
                Button { model.page = page } label: {
                    HStack(spacing: 11) {
                        Image(systemName: page.icon).font(.system(size: 15)).frame(width: 20)
                        Text(page.title).font(.system(size: 13, weight: model.page == page ? .semibold : .regular))
                        Spacer(minLength: 2)
                        if page == .recovery, !model.failures.isEmpty {
                            Text("\(model.failures.count)").font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.warm)
                        }
                    }.padding(.horizontal, 13).padding(.vertical, 10)
                        .foregroundStyle(model.page == page ? AppTheme.accentForeground : Color.primary.opacity(0.78))
                        .background(model.page == page ? AppTheme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).padding(.horizontal, 12)
                    .accessibilityAddTraits(model.page == page ? .isSelected : [])
                    .disabled(AppLaunch.isPreview && page != .usage)
            }
        }.padding(.bottom, 16)
    }
    @ViewBuilder private var page: some View {
        switch model.page {
        case .home: HomeView(model: model)
        case .history: HistoryView(model: model)
        case .usage: UsageView(model: model)
        case .dictionary: DictionaryView(model: model)
        case .recovery: RecoveryView(model: model)
        case .voice: VoiceSettingsView(model: model)
        case .settings: SettingsView(model: model)
        }
    }
}

struct Surface<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title { Text(title).font(.system(size: 14, weight: .semibold)) }
            content
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.055), lineWidth: 1))
    }
}

struct NoticeView: View {
    let text: String
    let isError: Bool
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
            Text(text).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel(L("알림 닫기", "Dismiss notification"))
        }.foregroundStyle(isError ? Color.orange : AppTheme.accentForeground).padding(14)
            .background((isError ? Color.orange : AppTheme.accent).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct HomeView: View {
    @Bindable var model: AppModel
    @State private var showSetupDetails = false
    @State private var showConnectionDetails = false

    private var readyForInput: Bool {
        !model.preferencesRecoveryRequired && model.startupState == .ready && aiConnectionReady && model.requiredJevReady && model.hotkeysRegistered && model.microphoneAllowed && model.accessibilityAllowed
            && (!model.preferences.needsLocal || model.localState == .ready)
            && (!model.preferences.speakerFilterEnabled || (model.hasSpeakerProfile && model.speakerState == .ready))
    }

    var body: some View {
        introduction
        if let composition = model.promptComposition {
            PromptCompositionResultView(composition: composition, isBusy: model.isBusy,
                regenerationSettings: model.promptRegenerationSettings, onRegenerate: model.regeneratePrompt)
        }
        shortcutConflicts
        inputReadiness
        inputModes
        currentModels
        latestResult
        latestJevReview
        JevAssistanceResultsView(model: model)
        savedRecordings
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L("말하면, 글이 됩니다.", "Speak. Make it text.")).font(.system(size: 30, weight: .semibold)).tracking(-1)
            Text(L("원하는 앱의 입력창에서 단축키를 눌러 시작하세요.", "Press your shortcut in any app’s text field to start."))
                .font(.system(size: 14)).foregroundStyle(.secondary)
        }.padding(.top, 4).padding(.bottom, 2)
    }

    @ViewBuilder private var shortcutConflicts: some View {
        if !model.hotkeyConflicts.isEmpty {
            // Survives notice resets: the launch notice is cleared on every recording start.
            Surface(L("단축키가 다른 앱과 겹쳐요", "Another app uses this shortcut")) {
                ForEach(model.hotkeyConflicts, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange).lineSpacing(3)
                }
                Button(L("설정 › 입력·단축키 열기", "Open Settings › Input & Shortcuts")) { openSettings(.input) }
            }
        }
    }

    private var inputReadiness: some View {
        Surface(L("입력 준비 상태", "Ready to type")) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: readyForInput ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 20)).foregroundStyle(readyForInput ? AppTheme.accentForeground : AppTheme.warm)
                VStack(alignment: .leading, spacing: 4) {
                    Text(readyForInput ? L("녹음과 입력을 시작할 수 있어요", "Ready to record and type") : L("연결과 Mac 권한을 확인해 주세요", "Check your connections and Mac permissions"))
                        .font(.system(size: 14, weight: .medium))
                    Text(L("API 키의 실제 연결 여부는 첫 처리 때 확인합니다.", "API keys are checked with the provider on your first request."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(L("Mac 권한", "Mac permissions")) { openSettings(.general) }
            }
            HStack(alignment: .top, spacing: 18) {
                DisclosureGroup(L("설치 후 확인 · 연결 → 권한 → 입력 연습", "Setup check · Connections → permissions → test typing"), isExpanded: $showSetupDetails) {
                    VStack(alignment: .leading, spacing: 14) {
                        setupRows
                        Divider()
                        Text(L("마지막으로 TextEdit 등의 빈 본문을 직접 클릭해 입력을 확인하세요. 입력 연습은 녹음과 API 호출 없이 테스트 문장만 입력합니다.", "Finally, click an empty text area in an app such as TextEdit to verify typing. This test enters only a test sentence, without recording or an API request."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        HStack {
                            Button(L("권한 상태 다시 확인", "Refresh permissions"), systemImage: "arrow.clockwise") { model.refreshPermissions() }
                            Button(L("5초 뒤 입력 연습", "Test typing in 5 seconds")) { model.scheduleInputTest() }
                                .disabled(model.isBusy || model.startupState != .ready || !model.accessibilityAllowed)
                        }
                        if !model.inputDiagnostics.isEmpty {
                            DisclosureGroup(L("최근 입력 진단", "Latest typing diagnostics")) {
                                Text(model.inputDiagnostics).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                    .padding(.top, 8)
                            }
                        }
                    }.padding(.top, 14)
                }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                Button(model.inputTestArmed ? L("준비 취소", "Cancel test") : L("입력 연습", "Test typing")) {
                    if model.inputTestArmed { model.cancelInputTest() } else { model.armInputTest() }
                }.disabled(model.isBusy || model.startupState != .ready || !model.accessibilityAllowed)
                    .help(L("녹음과 API 호출 없이 테스트 문장만 입력합니다.", "Types a test sentence without recording or making an API request."))
            }
            if model.inputTestArmed {
                Label(L("원하는 입력창에서 받아쓰기 단축키를 누르세요.", "Press your dictation shortcut in the text field you want to use."), systemImage: "keyboard")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.accentForeground)
            }
            if let issue = model.requiredJevIssue {
                Label(issue.message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.warm)
                Button(L("Jev 연결 설정", "Set up Jev connection")) { openSettings(.connection) }
            }
        }
        .onAppear { if !readyForInput { showSetupDetails = true } }
    }

    private var inputModes: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                modeCard(.dictation, icon: "waveform", detail: model.preferences.dictationOutputLanguage.isTranslation
                         ? L("의미와 말투를 살려\n\(model.preferences.dictationOutputLanguage.title)로 바로 입력.", "Preserve meaning and tone.\nType in \(model.preferences.dictationOutputLanguage.title).")
                         : L("추임새와 말실수를 정리하고\n말한 언어를 그대로.", "Remove fillers and slips.\nKeep the language you spoke."), index: 0)
                modeCard(.translation, icon: "character.bubble", detail: L("의미와 뉘앙스를 살려\n자연스러운 다른 언어로.", "Translate naturally while\nkeeping meaning and nuance."), index: 1)
                modeCard(.rewrite, icon: "pencil.line", detail: L("문장을 선택하고 말하세요.\n원하는 표현으로 바꿔요.", "Select text and speak.\nRewrite it the way you want."), index: 2)
            }
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "keyboard").foregroundStyle(AppTheme.warm)
                Text(L("같은 단축키를 다시 누르면 녹음이 끝납니다. 변경은 설정 › 입력·단축키에서 할 수 있어요.", "Press the same shortcut again to finish recording. Change shortcuts in Settings › Input & Shortcuts."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            promptInput
        }
    }

    private var promptInput: some View {
        Surface {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.bubble").font(.system(size: 21, weight: .light)).foregroundStyle(AppTheme.accentForeground)
                VStack(alignment: .leading, spacing: 7) {
                    Text(L("프롬프트 만들기", "Create a prompt")).font(.system(size: 14, weight: .semibold))
                    Text(L("생각나는 대로 말하세요. 목표와 조건을 짧은 AI 지시문으로 정리하고 Jev로 두 번 검토합니다.", "Speak your ideas freely. Turn your goal and constraints into a short AI instruction, with two Jev reviews."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    Text(L("프로젝트나 AI를 말하면 포함합니다. 완성된 프롬프트를 확인하고 복사해 사용하세요.", "Mention a project or AI to include it. Review the finished prompt, then copy it to use."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(model.hotkeyLabel(index: 3)).font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 9).padding(.vertical, 5).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
            }
            if let issue = model.promptCompositionIssue {
                HStack(alignment: .top, spacing: 10) {
                    Label(issue, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(AppTheme.warm).frame(maxWidth: .infinity, alignment: .leading)
                    Button(L("AI 연결 설정", "AI connection settings")) { openSettings(.connection) }
                }
            }
            Button(model.isRecording && model.mode == .prompt
                   ? L("녹음 끝내고 프롬프트 만들기", "Finish recording and create prompt")
                   : L("프롬프트 녹음 시작", "Record a prompt"), systemImage: model.isRecording && model.mode == .prompt ? "stop.fill" : "mic.fill") {
                Task { await model.toggle(.prompt) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(AppLaunch.isPreview || model.preferencesRecoveryRequired || model.startupState != .ready
                      || (model.isBusy && !(model.isRecording && model.mode == .prompt)))
            Text(L("받아쓰기·번역 설정과 별개로 짧게 정리합니다. 다른 앱에 자동 입력하거나 전송하지 않습니다.", "Creates a concise prompt independently of dictation and translation settings. It is not typed into or sent to another app automatically."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text(L("코드나 직접 설계안 없이 목표·맥락·제약·원하는 결과만 담습니다. 음성 인식 뒤 문장 생성 1~2회와 Jev 검토 2회가 실행되어 추가 비용과 대기 시간이 발생합니다. 초안에 수정이 필요할 때만 한 번 다듬습니다.", "Includes only the goal, context, constraints and desired result, without code or concrete designs. After transcription, one or two text calls and two Jev reviews add cost and wait time. The draft is polished once only when it needs correction."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var latestResult: some View {
        if !model.result.isEmpty || model.decisionOriginalText != nil || model.recentDecisionTarget != nil || model.translationRefinement != nil {
            Surface(L("최근 결과", "Latest result")) {
                if let language = model.recentTranslationLanguage {
                    Label(model.translationRefinement?.held == true
                          ? L("번역 초안 · 당시 출력 언어: \(language)", "Draft translation · Captured output language: \(language)")
                          : L("번역 결과 · 당시 출력 언어: \(language)", "Translation · Captured output language: \(language)"), systemImage: "character.bubble")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let original = model.decisionOriginalText {
                    Text(L("인식 원문", "Transcript")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text(original).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                    Button(L("원문 복사", "Copy transcript"), systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(original, forType: .string) }
                    Divider()
                    Text(model.translationRefinement?.held == true ? L("번역 초안", "Draft translation")
                         : model.recentTranslationLanguage == nil ? L("문장 정리 결과", "Cleaned text") : L("번역 결과", "Translation"))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                if !model.result.isEmpty || model.translationRefinement == nil {
                    Text(model.result.isEmpty ? L("정리 결과가 비어 있습니다.", "The cleaned result is empty.") : model.result).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                    Button(model.translationRefinement?.held == true ? L("초안 복사", "Copy draft") : L("결과 복사", "Copy result"), systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.result, forType: .string) }
                        .disabled(model.result.isEmpty)
                }
                if let refinement = model.translationRefinement {
                    TranslationRefinementResultView(refinement: refinement)
                }
                if let target = model.recentDecisionTarget {
                    if model.decisionOriginalText == nil {
                        DisclosureGroup(L("인식 원문과 비교", "Compare with transcript")) {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(target.transcript).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                                Button(L("원문 복사", "Copy transcript"), systemImage: "doc.on.doc") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(target.transcript, forType: .string)
                                }
                            }.padding(.top, 8)
                        }.font(.system(size: 12))
                    }
                    JevReviewRequestButton(model: model, title: L("최근 결과를 Jev로 검토…", "Review latest result with Jev…"),
                                           targetTitle: target.title, requestIdentity: target.id.uuidString, purpose: target.purpose) {
                        model.reviewRecentResult()
                    }
                }
            }
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
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(L("다시 처리", "Recovery")) { model.page = .recovery }
            }
        }
    }

    private var currentModels: some View {
        Surface {
            HStack {
                Text(L("현재 AI 연결", "Current AI connections")).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(L("변경", "Change")) { openSettings(.connection) }
                    .accessibilityLabel(L("AI 연결과 모델 변경", "Change AI connections and models"))
            }
            VStack(alignment: .leading, spacing: 12) {
                modelRow(L("음성 인식", "Speech recognition"), icon: "waveform", name: model.preferences.needsLocal ? L("Whisper Large v3 · 이 Mac", "Whisper Large v3 · This Mac") : "\(model.preferences.provider.displayName) · \(model.preferences.transcriptionModel)")
                modelRow(L("문장 처리", "Text processing"), icon: "text.alignleft", name: "\(model.preferences.effectiveTextProvider.displayName) · \(model.preferences.textModel)")
                modelRow(L("Jev 검토", "Jev review"), icon: "checkmark.shield", name: model.preferences.translationProtectionEnabled && model.preferences.decisionReviewMode == .protect
                         ? L("\(jevConnectionName) · 번역도 입력 전 검토", "\(jevConnectionName) · Translation review before typing")
                         : model.preferences.dictationOutputLanguage.isTranslation
                         ? L("\(jevConnectionName) · 번역은 직접 검토", "\(jevConnectionName) · Translation review on request")
                         : "\(jevConnectionName) · \(model.preferences.decisionReviewMode.title)")
                modelRow(L("받아쓰기 출력 언어", "Dictation output language"), icon: "character.bubble", name: model.preferences.dictationOutputLanguage.title)
                modelRow(L("받아쓰기 표현", "Dictation expression"), icon: "slider.horizontal.3", name: model.preferences.dictationOutputLanguage.isTranslation
                         ? L("번역 중 사용 안 함", "Paused while translating")
                         : model.preferences.dictationExpression.isActive
                           ? "\(model.preferences.dictationExpression.style.title) · \(model.preferences.dictationExpression.strength)/100"
                           : L("현재 받아쓰기 · 강도 0", "Current dictation · Strength 0"))
            }
            if !model.preferences.dictationOutputLanguage.isTranslation,
               model.preferences.decisionReviewMode != .off && model.preferences.decisionReviewMode != .repair && !jevConnectionReady {
                Label(L("말한 언어 유지 받아쓰기: Jev 연결이 준비되지 않아 자동 검토를 건너뜁니다.", "Keep spoken language dictation: automatic review is skipped while the Jev connection is unavailable."), systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.warm)
            }
            if model.preferences.translationProtectionEnabled,
               model.preferences.decisionReviewMode == .protect && !jevConnectionReady {
                Label(L("번역의 입력 전 검토 연결이 준비되지 않았습니다. 검토할 수 없는 번역은 자동 입력을 보류합니다.", "Translation review is unavailable. Translations that cannot be reviewed will be held before typing."), systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.warm)
            }
            DisclosureGroup(L("처리 방식과 연결 상태", "Processing & connection details"), isExpanded: $showConnectionDetails) {
                VStack(alignment: .leading, spacing: 14) {
                    connectionDetail(L("음성 인식", "Speech recognition"), text: model.preferences.needsLocal ? model.localState.label : L("녹음이 선택한 제공자로 전송됩니다.", "Recordings are sent to the selected provider."))
                    connectionDetail(L("문장 처리", "Text processing"), text: L("반복·말실수를 정리하고, 이름·조건·의미 있는 강조를 보존하도록 처리합니다.", "Removes repetition and speech errors while preserving names, conditions and meaningful emphasis."))
                    connectionDetail(L("Jev 문장 검토 · 실험 기능", "Jev text review · Experimental"), text: jevConnectionDetail)
                    Text(model.preferences.translationProtectionEnabled && model.preferences.decisionReviewMode == .protect
                         ? L("번역 단축키와 받아쓰기 번역도 입력 전에 Jev로 검토합니다. 원문·번역·목표 언어·선택한 말투를 검토 서비스로 추가 전송하며, 의미 위험이나 검토 실패가 있으면 자동 입력을 보류합니다. 이 Jev 검토 자체는 번역을 교정하지 않습니다.", "The translation shortcut and translated dictation are reviewed before typing. Source text, translation, target language and selected tone are additionally sent to the review service. Meaning risks or review failures hold automatic typing. This Jev review does not repair translations.")
                         : model.preferences.dictationOutputLanguage.isTranslation
                         ? L("번역 결과는 최근 결과나 기록에서 Jev로 직접 검토할 수 있습니다. 번역의 입력 전 검토는 설정의 입력 전 보호에서 별도로 켤 수 있습니다.", "You can request a Jev review of translations from Latest result or History. Enable translation review separately in Protect before typing settings.")
                         : JevRepairPresentation.modeDetail(model.preferences.decisionReviewMode))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    if !model.preferences.dictationOutputLanguage.isTranslation,
                       model.preferences.decisionReviewMode == .observe && model.jevReviewMayDelayInput {
                        Text(L("음성 재인식을 켠 입력 후 검토는 첫 Jev 판단과 필요한 재인식을 입력 전에 기다립니다. 이후 교정 검토는 입력한 문장을 바꾸지 않습니다.", "With audio re-recognition enabled, Review after typing waits for the first Jev judgment and any needed re-recognition before typing. The later repair review does not change text already entered."))
                            .font(.system(size: 12)).foregroundStyle(AppTheme.warm).lineSpacing(3)
                    }
                    if model.preferences.needsLocal && model.localState != .ready {
                        Button(L("로컬 모델 준비하기", "Prepare local model"), systemImage: "desktopcomputer") { model.page = .voice }
                    }
                }.padding(.top, 12)
            }.font(.system(size: 12))
        }
    }

    private func modelRow(_ title: String, icon: String, name: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(AppTheme.accentForeground).frame(width: 20)
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 112, alignment: .leading)
            Text(name).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func connectionDetail(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
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
        (model.preferences.needsLocal || (model.keySaved && !model.transcriptionKeyOperationInProgress))
            && model.textKeySaved && !model.textKeyOperationInProgress
    }

    private var setupRows: some View {
        VStack(alignment: .leading, spacing: 14) {
            setupRow(L("AI 연결", "AI connections"), detail: aiConnectionReady ? L("필요한 API 키가 모두 저장되어 있어요.", "All required API keys are saved.") : L("음성 인식과 문장 정리에 필요한 API 키를 저장해 주세요.", "Save the API keys needed for speech recognition and text cleanup."), ready: aiConnectionReady) { openSettings(.connection) }
            if model.preferences.decisionReviewMode == .repair && !model.preferences.dictationOutputLanguage.isTranslation {
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
            setupRow(L("다른 앱에 입력", "Type into other apps"), detail: L("손쉬운 사용 권한으로 커서 위치에 글을 입력해요.", "Accessibility permission lets the app type at your cursor."), ready: model.accessibilityAllowed) { openSettings(.general) }
            if model.preferences.needsLocal {
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

    private func modeCard(_ mode: InputMode, icon: String, detail: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.system(size: 21, weight: .light)).foregroundStyle(AppTheme.accentForeground)
            Text(mode.title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            Text(model.hotkeyLabel(index: index)).font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 9).padding(.vertical, 5).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(17)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.primary.opacity(0.06)))
    }

    private func setupRow(_ title: String, detail: String, ready: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if ready { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accentForeground).accessibilityLabel(L("\(title) 준비됨", "\(title) is ready")) }
            else { Button(L("설정", "Set up"), action: action).accessibilityLabel(L("\(title) 설정", "Set up \(title)")) }
        }
    }
}
