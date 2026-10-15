import AppKit
import SwiftUI
import OpenNoTypeCore

struct MainView: View {
    @Bindable var model: AppModel
    @State private var confirmsRecoveredSettings = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: AppLayout.sidebarWidth)
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(model.page == .recovery ? AppPage.history.title : model.page.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 12)
                    if model.isBusy {
                        Text(model.status).font(AppTypography.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        model.openSettings(SettingsSection.connection)
                    } label: {
                        Label(L("AI 연결", "AI connections"), systemImage: "network")
                            .font(AppTypography.caption)
                    }.buttonStyle(.borderless).foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppLayout.pageInset)
                .frame(height: AppLayout.toolbarHeight)
                .background(AppTheme.panelBackground)
                Divider()
                if model.page == .history || model.page == .recovery {
                    if hasGlobalNotice {
                        globalNotices.padding(AppLayout.pageInset)
                            .frame(maxWidth: AppLayout.contentMaxWidth)
                    }
                    page.padding(AppLayout.pageInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .disabled(model.preferencesRecoveryRequired)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
                                globalNotices
                                page.disabled(model.preferencesRecoveryRequired && model.page != .settings && model.page != .voice)
                            }
                            .padding(AppLayout.pageInset)
                            .frame(maxWidth: AppLayout.contentMaxWidth, alignment: .leading)
                            .frame(maxWidth: .infinity)
                            .id("page-top")
                        }
                        .onChange(of: model.page) { _, _ in proxy.scrollTo("page-top", anchor: .top) }
                        .onChange(of: model.settingsSection) { _, _ in proxy.scrollTo("page-top", anchor: .top) }
                        .onChange(of: model.phase) { _, phase in
                            if phase == .idle, model.page == .home,
                               model.promptComposition != nil || !model.result.isEmpty || model.translationRefinement != nil {
                                proxy.scrollTo("page-top", anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 960, minHeight: 680)
        .background(AppTheme.pageBackground)
        .font(AppTypography.body)
        .buttonStyle(AppActionButtonStyle())
        .controlSize(.large)
        .tint(AppTheme.accent)
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
    private var hasGlobalNotice: Bool {
        model.preferencesRecoveryRequired || model.startupState != .ready || model.keyOperationInProgress
            || model.error != nil || model.notice != nil
    }

    @ViewBuilder private var globalNotices: some View {
        if hasGlobalNotice {
            VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
                preferencesRecovery
                startupStatus
                if let error = model.error { NoticeView(text: error, isError: true) { model.error = nil } }
                if let notice = model.notice { NoticeView(text: notice, isError: false) { model.notice = nil } }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(nsImage: AppBrand.icon).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 28, height: 28).accessibilityHidden(true)
                Text(AppIdentity.current.isPromptTest ? "Prompt Test" : "OpenNoType")
                    .font(.system(size: 15, weight: .semibold))
            }.frame(height: 36).padding(.horizontal, 8)
            VStack(spacing: 4) {
                sidebarItems([.home, .history, .dictionary])
                Divider().padding(.horizontal, 8).padding(.vertical, 12)
                sidebarItems([.voice, .usage, .settings])
            }
            Spacer(minLength: 16)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    model.openSettings(SettingsSection.privacy)
                } label: {
                    Label(L("이 Mac에 보관", "Stored on this Mac"), systemImage: "lock.shield")
                        .font(AppTypography.caption)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L("개발", "Development")) (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(.horizontal, 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 16)
        .background(AppTheme.sidebarBackground)
    }

    private func sidebarItems(_ pages: [AppPage]) -> some View {
        ForEach(pages) { page in
            let selected = model.page == page || (page == .history && model.page == .recovery)
            Button { model.page = page } label: {
                HStack(spacing: 10) {
                    Image(systemName: page.icon).font(.system(size: 16)).frame(width: 18)
                    Text(page.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                    Spacer(minLength: 2)
                    if page == .history, !model.failures.isEmpty {
                        Text("\(model.failures.count)").font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                    }
                }
                .padding(.horizontal, 12).frame(minHeight: 36)
                .foregroundStyle(selected ? AppTheme.accentForeground : AppTheme.textSecondary)
                .background(selected ? AppTheme.accent.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .disabled(AppLaunch.isPreview && ![AppPage.home, .history, .dictionary, .usage, .settings, .voice].contains(page))
        }
    }
    @ViewBuilder private var page: some View {
        switch model.page {
        case .home: HomeView(model: model)
        case .history, .recovery: HistoryWorkspaceView(model: model, showsRecovery: model.page == .recovery)
        case .usage: UsageView(model: model)
        case .dictionary: DictionaryView(model: model)
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
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(AppTypography.sectionTitle).accessibilityAddTraits(.isHeader) }
            content
        }.padding(AppLayout.panelInset).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: AppLayout.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: AppLayout.cornerRadius).stroke(AppTheme.separator, lineWidth: 1))
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
        }.foregroundStyle(isError ? AppTheme.warm : AppTheme.accentForeground).padding(12)
            .background((isError ? Color.orange : AppTheme.accent).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
