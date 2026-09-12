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
                    Text(model.isBusy ? model.status : "내 키로, 내 Mac에서")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.horizontal, 30).frame(height: 56)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions(); Task { await model.refreshData() }
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
                    Text("말을 글로, 나답게").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.top, 27).padding(.bottom, 25)
            sidebarGroup("활동", pages: [.home, .history, .usage])
            sidebarGroup("도구", pages: [.dictionary, .recovery])
            sidebarGroup("앱 관리", pages: [.voice, .settings])
            Spacer(minLength: 16)
            VStack(alignment: .leading, spacing: 9) {
                Label("기록은 이 Mac에 보관", systemImage: "lock.shield")
                    .font(.system(size: 12, weight: .medium))
                Button("전송·보관 설정 보기") {
                    model.settingsSection = .privacy; model.page = .settings
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(AppTheme.accentForeground).disabled(AppLaunch.isPreview)
                Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "개발") · 개발 미리보기")
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
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("알림 닫기")
        }.foregroundStyle(isError ? Color.orange : AppTheme.accentForeground).padding(14)
            .background((isError ? Color.orange : AppTheme.accent).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct HomeView: View {
    @Bindable var model: AppModel
    @State private var showSetupDetails = false

    private var readyForInput: Bool {
        model.keySaved && model.microphoneAllowed && model.accessibilityAllowed
            && (!model.preferences.needsLocal || model.localState == .ready)
            && (!model.preferences.speakerFilterEnabled || (model.hasSpeakerProfile && model.speakerState == .ready))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("말하면, 글이 됩니다.").font(.system(size: 30, weight: .semibold)).tracking(-1)
            Text("원하는 앱의 입력창에서 단축키를 눌러 시작하세요.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
        }.padding(.top, 4).padding(.bottom, 2)
        if !model.hotkeyConflicts.isEmpty {
            // Survives notice resets: the launch notice is cleared on every recording start.
            Surface("단축키가 다른 앱과 겹쳐요") {
                ForEach(model.hotkeyConflicts, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange).lineSpacing(3)
                }
                Button("설정 › 입력·단축키 열기") { openSettings(.input) }
            }
        }
        currentModels
        HStack(alignment: .top, spacing: 12) {
            modeCard(.dictation, icon: "waveform", detail: "추임새와 말실수를 정리하고\n말한 언어를 그대로.", index: 0)
            modeCard(.translation, icon: "character.bubble", detail: "의미와 뉘앙스를 살려\n자연스러운 다른 언어로.", index: 1)
            modeCard(.rewrite, icon: "pencil.line", detail: "문장을 선택하고 말하세요.\n원하는 표현으로 바꿔요.", index: 2)
        }
        Surface("입력 준비 상태") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: readyForInput ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 20)).foregroundStyle(readyForInput ? AppTheme.accentForeground : AppTheme.warm)
                VStack(alignment: .leading, spacing: 4) {
                    Text(readyForInput ? "녹음과 입력을 시작할 수 있어요" : "연결과 Mac 권한을 확인해 주세요")
                        .font(.system(size: 14, weight: .medium))
                    Text("API 키의 실제 연결 여부는 첫 처리 때 확인합니다.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button("Mac 권한") { openSettings(.general) }
            }
            DisclosureGroup("연결·권한·모델 확인", isExpanded: $showSetupDetails) {
                setupRows.padding(.top, 14)
            }
            Divider()
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("먼저 다른 앱에 입력을 연습해 보세요").font(.system(size: 13, weight: .medium))
                    Text("녹음과 API 호출 없이 테스트 문장만 입력합니다.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(model.inputTestArmed ? "준비 취소" : "입력 연습") {
                    if model.inputTestArmed { model.cancelInputTest() } else { model.armInputTest() }
                }.disabled(model.isBusy || !model.accessibilityAllowed)
            }
            if model.inputTestArmed {
                Label("원하는 입력창에서 받아쓰기 단축키를 누르세요.", systemImage: "keyboard")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.accentForeground)
            }
        }
        .onAppear { if !readyForInput { showSetupDetails = true } }
        HStack(alignment: .top, spacing: 12) {
            destinationCard(.usage, detail: "모델별 요청과\n사용량·비용 확인")
            destinationCard(.dictionary, detail: model.preferences.automaticLearningEnabled ? "자동 학습 켜짐\n교정 검토와 되돌리기" : "자동 학습 꺼짐\n자주 쓰는 표현 관리")
            destinationCard(.recovery, detail: model.failures.isEmpty ? "실패한 녹음을\n24시간 안에 복구" : "보관 중인 녹음 \(model.failures.count)개\n현재 설정으로 재처리")
        }
        if !model.result.isEmpty {
            Surface("최근 결과") {
                Text(model.result).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                Button("결과 복사", systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.result, forType: .string) }
            }
        }
        HStack(spacing: 9) {
            Image(systemName: "keyboard").foregroundStyle(AppTheme.warm)
            Text("같은 단축키를 다시 누르면 녹음이 끝납니다. 변경은 설정 › 입력·단축키에서 할 수 있어요.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var currentModels: some View {
        Surface {
            HStack {
                Text("현재 사용하는 모델").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("변경") { openSettings(.connection) }
                    .accessibilityLabel("AI 연결과 모델 변경")
            }
            modelRow("음성 인식", icon: "waveform", name: model.preferences.needsLocal ? "Whisper Large v3 · 이 Mac" : "\(model.preferences.provider.displayName) · \(model.preferences.transcriptionModel)", detail: model.preferences.needsLocal ? model.localState.label : "녹음이 선택한 제공자로 전송됩니다.")
            Divider()
            modelRow("문장 처리", icon: "text.alignleft", name: "\(model.preferences.provider.displayName) · \(model.preferences.textModel)", detail: "반복·말실수를 정리하고, 이름·조건·의미 있는 강조를 보존하도록 처리합니다.")
            if model.preferences.needsLocal && model.localState != .ready {
                Button("로컬 모델 준비하기", systemImage: "desktopcomputer") { model.page = .voice }
            }
        }
    }

    private func modelRow(_ title: String, icon: String, name: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(AppTheme.accentForeground).frame(width: 23)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Text(name).font(.system(size: 13, weight: .medium)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var setupRows: some View {
        VStack(alignment: .leading, spacing: 14) {
            setupRow("AI 연결", detail: model.keySaved ? "\(model.preferences.provider.displayName) API 키가 저장되어 있어요." : "사용할 제공자의 API 키를 저장해 주세요.", ready: model.keySaved) { openSettings(.connection) }
            Divider()
            setupRow("마이크", detail: model.microphonePermissionNeedsSettings ? "시스템 설정에서 OpenNoType을 허용해 주세요." : "녹음을 시작할 때만 마이크를 사용해요.", ready: model.microphoneAllowed) {
                if model.microphonePermissionNeedsSettings { model.openMicrophoneSettings() }
                else { Task { await model.requestMicrophone() } }
            }
            Divider()
            setupRow("다른 앱에 입력", detail: "손쉬운 사용 권한으로 커서 위치에 글을 입력해요.", ready: model.accessibilityAllowed) { openSettings(.general) }
            if model.preferences.needsLocal {
                Divider()
                setupRow("로컬 음성 모델", detail: model.localState.label, ready: model.localState == .ready) { model.page = .voice }
            }
            if model.preferences.speakerFilterEnabled {
                Divider()
                setupRow("내 목소리 필터", detail: model.hasSpeakerProfile ? model.speakerState.label : "목소리를 등록해 주세요.", ready: model.hasSpeakerProfile && model.speakerState == .ready) { model.page = .voice }
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

    private func destinationCard(_ page: AppPage, detail: String) -> some View {
        Button { model.page = page } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: page.icon).foregroundStyle(AppTheme.accentForeground)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text(page.title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(17)
                .background(AppTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
                .contentShape(RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain)
    }

    private func setupRow(_ title: String, detail: String, ready: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if ready { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accentForeground).accessibilityLabel("\(title) 준비됨") }
            else { Button("설정", action: action).accessibilityLabel("\(title) 설정") }
        }
    }
}
