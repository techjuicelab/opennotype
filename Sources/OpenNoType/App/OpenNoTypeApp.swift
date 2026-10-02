import AppKit
import SwiftUI

@main
struct OpenNoTypeApp: App {
    @NSApplicationDelegateAdaptor(UpdateApplicationDelegate.self) private var applicationDelegate
    @State private var model: AppModel
    @State private var voiceBar: VoiceBarController?
    @State private var updater: Updater

    init() {
        let model = AppLaunch.makeModel()
        let updater = Updater.shared
        let isBusy = { [weak model] in model.map { $0.isBusy || $0.historyReprocessing?.isProcessing == true } ?? false }
        updater.observeActivity { [weak model] in
            isBusy() || model?.startupState == .loading || model?.keyOperationInProgress == true
        }
        _model = State(initialValue: model)
        _updater = State(initialValue: updater)
        applicationDelegate.isBusy = isBusy
        applicationDelegate.terminationBlocked = { [weak model] in
            model?.notice = L("현재 작업을 마치거나 ‘현재 작업 취소’를 선택한 뒤 종료할 수 있어요. 업데이트 설치는 설정 › Mac·일반에서 다시 선택해 주세요.", "Finish the current task or choose Cancel current task before quitting. You can retry the update in Settings › Mac & general.")
            model?.showManager?()
        }
    }
    var body: some Scene {
        Window(AppLaunch.isPreview ? L("OpenNoType · 디자인 검증용 샘플", "OpenNoType · Design preview") : "OpenNoType", id: "main") {
            MainView(model: model)
                .environment(\.locale, model.preferences.interfaceLanguage.locale)
                .task {
                    guard !AppLaunch.isPreview else { return }
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
                Button(L("업데이트 확인…", "Check for Updates…")) { updater.check() }.disabled(!updater.canCheck)
                Divider()
            }
        }
        MenuBarExtra {
            MenuContent(model: model)
                .environment(\.locale, model.preferences.interfaceLanguage.locale)
        } label: {
            Image(nsImage: AppBrand.menuBarImage(isRecording: model.isRecording))
                .accessibilityLabel(model.isRecording ? L("OpenNoType — 녹음 중", "OpenNoType — Recording") : "OpenNoType")
        }
    }
}

@MainActor
final class UpdateApplicationDelegate: NSObject, NSApplicationDelegate {
    var isBusy: () -> Bool = { false }
    var terminationBlocked: (() -> Void)?

    func requestTermination() -> NSApplication.TerminateReply {
        guard !isBusy() else { terminationBlocked?(); return .terminateCancel }
        return .terminateNow
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // This also protects Sparkle paths that bypass its relaunch postponement delegate.
        requestTermination()
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
        if model.isBusy || model.historyReprocessing?.isProcessing == true {
            Button(L("현재 작업 취소", "Cancel current task")) { model.cancel() }
        }
        Divider()
        Button(L("OpenNoType 열기", "Open OpenNoType")) { show(model.page) }
        Button(L("사용량과 비용 보기", "View usage and costs")) { show(.usage) }
        if !model.failures.isEmpty { Button(L("실패한 녹음 다시 처리 · \(model.failures.count)개", "Recover recordings · \(model.failures.count)")) { show(.recovery) } }
        Button(L("설정…", "Settings…")) { show(.settings) }.keyboardShortcut(",", modifiers: .command).disabled(AppLaunch.isPreview)
        Divider()
        Button(L("종료", "Quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
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
            Button(L("설정…", "Settings…")) { show(.settings) }
                .keyboardShortcut(",", modifiers: .command).disabled(AppLaunch.isPreview)
        }
        CommandGroup(after: .sidebar) {
            Button(L("사용량과 비용", "Usage and costs")) { show(.usage) }
            Button(L("음성 모델", "Voice models")) { show(.voice) }.disabled(AppLaunch.isPreview)
        }
    }

    private func show(_ page: AppPage) {
        model.page = page
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

import OpenNoTypeCore
