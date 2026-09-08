import AppKit
import SwiftUI
import OpenNoTypeCore

enum AppTheme {
    static let accent = Color(red: 0.31, green: 0.48, blue: 0.40)
    static let warm = Color(red: 0.75, green: 0.55, blue: 0.33)
}

struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 216)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(model.page.title).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Circle().fill(model.isRecording ? .red : AppTheme.accent).frame(width: 6, height: 6)
                    Text(model.isBusy ? model.status : "내 키로, 내 Mac에서")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.horizontal, 30).frame(height: 56)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let error = model.error { NoticeView(text: error, isError: true) { model.error = nil } }
                        if let notice = model.notice { NoticeView(text: notice, isError: false) { model.notice = nil } }
                        page
                    }.padding(30).frame(maxWidth: 920, alignment: .leading).frame(maxWidth: .infinity)
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
                Image(systemName: "waveform").font(.system(size: 22, weight: .semibold)).foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenNoType").font(.system(size: 16, weight: .semibold))
                    Text("VOICE, IN YOUR WORDS").font(.system(size: 7.5, weight: .medium, design: .monospaced)).tracking(1.1).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 22).padding(.top, 28).padding(.bottom, 35)
            ForEach(AppPage.allCases) { page in
                Button { model.page = page } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page.icon).font(.system(size: 15)).frame(width: 20)
                        Text(page.title).font(.system(size: 13, weight: model.page == page ? .semibold : .regular))
                        Spacer()
                        if page == .recovery, !model.failures.isEmpty { Text("\(model.failures.count)").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.horizontal, 13).padding(.vertical, 11)
                        .foregroundStyle(model.page == page ? AppTheme.accent : Color.primary.opacity(0.7))
                        .background(model.page == page ? AppTheme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 3)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Label("나의 API · 나의 기록", systemImage: "lock.shield").font(.system(size: 11, weight: .medium))
                Text("콘텐츠는 선택한 AI 제공자에게만 전송됩니다. 기록은 이 Mac에 보관합니다.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                Text("0.1.0 · 개발 미리보기").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            }.padding(22)
        }.background(.quaternary.opacity(0.15))
    }
    @ViewBuilder private var page: some View {
        switch model.page {
        case .home: HomeView(model: model)
        case .history: HistoryView(model: model)
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
        }.foregroundStyle(isError ? Color.orange : AppTheme.accent).padding(14)
            .background((isError ? Color.orange : AppTheme.accent).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct HomeView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR VOICE. YOUR WAY.").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(AppTheme.accent)
            Text("말은 편하게.\n글은 또렷하게.").font(.system(size: 36, weight: .semibold)).tracking(-1.4).lineSpacing(2)
            Text("생각을 말하면, 당신의 말투를 지켜 글로 옮깁니다.")
                .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 2)
        }.padding(.top, 6).padding(.bottom, 10)
        HStack(alignment: .top, spacing: 12) {
            modeCard(.dictation, icon: "waveform", detail: "추임새와 말실수를 정리하고\n말한 언어를 그대로.", index: 0)
            modeCard(.translation, icon: "character.bubble", detail: "의미와 뉘앙스를 살려\n자연스러운 다른 언어로.", index: 1)
            modeCard(.rewrite, icon: "pencil.line", detail: "문장을 선택하고 말하세요.\n원하는 표현으로 바꿔요.", index: 2)
        }
        Surface("처음 한 번만 준비해 주세요") {
            setupRow("01", title: "사용할 AI 연결", detail: model.keySaved ? "\(model.preferences.provider.displayName) API 키 저장됨" : "OpenAI, OpenRouter 또는 Claude API 키를 사용해요.", ready: model.keySaved) { model.page = .settings }
            Divider()
            setupRow("02", title: "마이크 허용", detail: "녹음은 단축키나 버튼으로 시작할 때만 켜집니다.", ready: model.microphoneAllowed) { Task { await model.requestMicrophone() } }
            Divider()
            setupRow("03", title: "다른 앱에 입력 허용", detail: "손쉬운 사용 권한으로 커서 위치에 글을 입력해요.", ready: model.accessibilityAllowed) { TextInsertion.requestPermission(); model.refreshPermissions() }
        }
        if !model.result.isEmpty {
            Surface("최근 결과") {
                Text(model.result).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                Button("결과 복사", systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.result, forType: .string) }
            }
        }
        HStack(spacing: 9) {
            Image(systemName: "keyboard").foregroundStyle(AppTheme.warm)
            Text("원하는 앱의 입력창을 클릭한 뒤 단축키를 누르세요. 다시 누르면 녹음이 끝납니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private func modeCard(_ mode: InputMode, icon: String, detail: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(AppTheme.accent)
            Text(mode.title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            Text(model.preferences.hotkeys[index].label).font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 9).padding(.vertical, 5).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(19)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.primary.opacity(0.06)))
    }
    private func setupRow(_ number: String, title: String, detail: String, ready: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Text(number).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if ready { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accent) }
            else { Button("설정", action: action).controlSize(.small) }
        }
    }
}
