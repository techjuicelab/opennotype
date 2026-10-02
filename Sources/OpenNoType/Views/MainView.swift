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
                            startupStatus
                            if let error = model.error { NoticeView(text: error, isError: true) { model.error = nil } }
                            if let notice = model.notice { NoticeView(text: notice, isError: false) { model.notice = nil } }
                            page
                        }.padding(30).frame(maxWidth: 920, alignment: .leading).frame(maxWidth: .infinity).id("page-top")
                    }
                    .onChange(of: model.page) { _, _ in proxy.scrollTo("page-top", anchor: .top) }
                    .onChange(of: model.settingsSection) { _, _ in proxy.scrollTo("page-top", anchor: .top) }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(AppTheme.accent)
        .onAppear {
            model.showManager = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        }
    }
    @ViewBuilder private var startupStatus: some View {
        if model.startupState != .ready {
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
                    Text(L("말을 글로, 나답게", "Your voice, in your words")).font(.system(size: 12)).foregroundStyle(.secondary)
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
                Text(L("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "개발") · 개발 미리보기", "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L("개발", "Development")) · Development preview"))
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
        model.startupState == .ready && aiConnectionReady && model.microphoneAllowed && model.accessibilityAllowed
            && (!model.preferences.needsLocal || model.localState == .ready)
            && (!model.preferences.speakerFilterEnabled || (model.hasSpeakerProfile && model.speakerState == .ready))
    }

    var body: some View {
        introduction
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
                DisclosureGroup(L("연결·권한·모델 확인", "Connections, permissions & models"), isExpanded: $showSetupDetails) {
                    VStack(alignment: .leading, spacing: 14) {
                        setupRows
                        Text(L("입력 연습은 녹음과 API 호출 없이 다른 앱에 테스트 문장만 입력합니다.", "Test typing enters a test sentence in another app without recording or making an API request."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
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
            if model.preferences.decisionReviewMode == .repair && !jevConnectionReady {
                Label(L("입력 전 교정에 필요한 Jev 연결을 준비해 주세요. 준비 전에는 자동 입력을 보류합니다.", "Prepare the Jev connection for Repair before typing. Automatic input is held until it is ready."), systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.warm)
                Button(L("Jev 연결 설정", "Set up Jev connection")) { openSettings(.connection) }
            }
        }
        .onAppear { if !readyForInput { showSetupDetails = true } }
    }

    private var inputModes: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                modeCard(.dictation, icon: "waveform", detail: L("추임새와 말실수를 정리하고\n말한 언어를 그대로.", "Remove fillers and slips.\nKeep the language you spoke."), index: 0)
                modeCard(.translation, icon: "character.bubble", detail: L("의미와 뉘앙스를 살려\n자연스러운 다른 언어로.", "Translate naturally while\nkeeping meaning and nuance."), index: 1)
                modeCard(.rewrite, icon: "pencil.line", detail: L("문장을 선택하고 말하세요.\n원하는 표현으로 바꿔요.", "Select text and speak.\nRewrite it the way you want."), index: 2)
            }
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "keyboard").foregroundStyle(AppTheme.warm)
                Text(L("같은 단축키를 다시 누르면 녹음이 끝납니다. 변경은 설정 › 입력·단축키에서 할 수 있어요.", "Press the same shortcut again to finish recording. Change shortcuts in Settings › Input & Shortcuts."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var latestResult: some View {
        if !model.result.isEmpty || model.decisionOriginalText != nil || model.recentDecisionTarget != nil {
            Surface(L("최근 결과", "Latest result")) {
                if let original = model.decisionOriginalText {
                    Text(L("인식 원문", "Transcript")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text(original).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                    Button(L("원문 복사", "Copy transcript"), systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(original, forType: .string) }
                    Divider()
                    Text(L("문장 정리 결과", "Cleaned text")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                Text(model.result.isEmpty ? L("정리 결과가 비어 있습니다.", "The cleaned result is empty.") : model.result).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                Button(L("결과 복사", "Copy result"), systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.result, forType: .string) }
                    .disabled(model.result.isEmpty)
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
                modelRow(L("Jev 검토", "Jev review"), icon: "checkmark.shield", name: "\(jevConnectionName) · \(model.preferences.decisionReviewMode.title)")
            }
            if model.preferences.decisionReviewMode != .off && model.preferences.decisionReviewMode != .repair && !jevConnectionReady {
                Label(L("Jev 연결이 준비되지 않아 자동 검토를 건너뜁니다.", "Automatic review is skipped while the Jev connection is unavailable."), systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.warm)
            }
            DisclosureGroup(L("처리 방식과 연결 상태", "Processing & connection details"), isExpanded: $showConnectionDetails) {
                VStack(alignment: .leading, spacing: 14) {
                    connectionDetail(L("음성 인식", "Speech recognition"), text: model.preferences.needsLocal ? model.localState.label : L("녹음이 선택한 제공자로 전송됩니다.", "Recordings are sent to the selected provider."))
                    connectionDetail(L("문장 처리", "Text processing"), text: L("반복·말실수를 정리하고, 이름·조건·의미 있는 강조를 보존하도록 처리합니다.", "Removes repetition and speech errors while preserving names, conditions and meaningful emphasis."))
                    connectionDetail(L("Jev 문장 검토 · 실험 기능", "Jev text review · Experimental"), text: jevConnectionDetail)
                    Text(JevRepairPresentation.modeDetail(model.preferences.decisionReviewMode))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
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
            Text(model.preferences.hotkeys[index].label).font(.system(size: 12, weight: .medium, design: .monospaced))
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
