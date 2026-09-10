import AppKit
import SwiftUI

@main
struct OpenNoTypeApp: App {
    @State private var model = AppLaunch.makeModel()
    @State private var voiceBar: VoiceBarController?
    var body: some Scene {
        Window(AppLaunch.isPreview ? "OpenNoType · 디자인 검증용 샘플" : "OpenNoType", id: "main") {
            MainView(model: model)
                .task {
                    guard !AppLaunch.isPreview else { return }
                    _ = Updater.shared
                    if voiceBar == nil { voiceBar = VoiceBarController(model: model) }
                }
                .preferredColorScheme(model.preferences.appearance == "dark" ? .dark : model.preferences.appearance == "light" ? .light : nil)
        }
        .defaultSize(width: 1010, height: 730)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            AppNavigationCommands(model: model)
            CommandGroup(after: .appInfo) {
                Button("업데이트 확인…") { Updater.shared.check() }.disabled(AppLaunch.isPreview)
                Divider()
            }
        }
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: AppBrand.menuBarImage(isRecording: model.isRecording))
                .accessibilityLabel(model.isRecording ? "OpenNoType — 녹음 중" : "OpenNoType")
        }
    }
}

private struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.status)
        Divider()
        ForEach(Array(InputMode.allCases.enumerated()), id: \.element.id) { index, mode in
            Button("\(mode.title)  \(model.preferences.hotkeys[index].label)") { Task { await model.toggle(mode) } }
                .disabled(AppLaunch.isPreview)
        }
        if model.isBusy { Button("현재 작업 취소") { model.cancel() } }
        Divider()
        Button("OpenNoType 열기") { show(model.page) }
        Button("사용량과 비용 보기") { show(.usage) }
        if !model.failures.isEmpty { Button("실패한 녹음 다시 처리 · \(model.failures.count)개") { show(.recovery) } }
        Button("설정…") { show(.settings) }.keyboardShortcut(",", modifiers: .command).disabled(AppLaunch.isPreview)
        Divider()
        Button("종료") { model.cancel(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func show(_ page: AppPage) {
        model.page = page
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AppNavigationCommands: Commands {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("설정…") { show(.settings) }
                .keyboardShortcut(",", modifiers: .command).disabled(AppLaunch.isPreview)
        }
        CommandGroup(after: .sidebar) {
            Button("사용량과 비용") { show(.usage) }
            Button("음성 모델") { show(.voice) }.disabled(AppLaunch.isPreview)
        }
    }

    private func show(_ page: AppPage) {
        model.page = page
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

import OpenNoTypeCore
