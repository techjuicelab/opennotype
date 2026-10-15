import AppKit
import SwiftUI

@main
struct OpenNoTypeApp: App {
    @NSApplicationDelegateAdaptor(UpdateApplicationDelegate.self) private var applicationDelegate
    @State private var model: AppModel
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
            model?.notice = L("현재 작업을 마치거나 ‘현재 작업 취소’를 선택한 뒤 종료할 수 있어요. 업데이트 설치는 설정 › 앱 설정에서 다시 선택해 주세요.", "Finish the current task or choose Cancel current task before quitting. You can retry the update in Settings › App settings.")
            model?.showManager?()
        }
        applicationDelegate.configureStatusBar(model: model)
    }
    var body: some Scene {
        Window(AppLaunch.isPreview ? L("OpenNoType · 디자인 검증용 샘플", "OpenNoType · Design preview") : AppIdentity.current.displayName, id: "main") {
            ManagerWindowContent(model: model, windows: applicationDelegate.windows)
                .environment(\.locale, model.preferences.interfaceLanguage.locale)
                .preferredColorScheme(model.preferences.appearance == "dark" ? .dark : model.preferences.appearance == "light" ? .light : nil)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            AppNavigationCommands(model: model)
            CommandGroup(after: .appInfo) {
                Button(L("업데이트 확인…", "Check for Updates…")) { updater.check() }.disabled(!updater.canCheck)
                Divider()
            }
        }
    }
}

@MainActor
final class UpdateApplicationDelegate: NSObject, NSApplicationDelegate {
    var isBusy: () -> Bool = { false }
    var terminationBlocked: (() -> Void)?
    private(set) var statusBarController: StatusBarController?
    let windows = AppWindows()
    private weak var model: AppModel?
    var makeRecordingBar: (AppModel) -> AnyObject = { VoiceBarController(model: $0) }
    private var recordingBar: AnyObject?

    func configureStatusBar(model: AppModel) {
        guard statusBarController == nil else { return }
        self.model = model
        model.showManager = { [weak self] in self?.windows.show() }
        statusBarController = StatusBarController(model: model)
        if NSApp?.isRunning == true { statusBarController?.start() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController?.start()
        // Recording feedback must remain available without ever opening the manager.
        if !AppLaunch.isPreview, recordingBar == nil, let model {
            recordingBar = makeRecordingBar(model)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        statusBarController?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication, coder: NSCoder) -> Bool { false }
    func applicationShouldRestoreApplicationState(_ app: NSApplication, coder: NSCoder) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.showManager?()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.stop()
    }

    func requestTermination() -> NSApplication.TerminateReply {
        guard !isBusy() else { terminationBlocked?(); return .terminateCancel }
        return .terminateNow
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // This also protects Sparkle paths that bypass its relaunch postponement delegate.
        requestTermination()
    }
}

private struct ManagerWindowContent: View {
    @Bindable var model: AppModel
    let windows: AppWindows
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MainView(model: model)
            .background(ManagerWindowAccessor(windows: windows))
            .onAppear {
                windows.connectWindowOpening { openWindow(id: "main") }
            }
    }
}

private struct AppNavigationCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(L("설정…", "Settings…")) { show(.settings) }
                .keyboardShortcut(",", modifiers: .command).disabled(AppLaunch.isPreview)
        }
        CommandGroup(after: .sidebar) {
            Button(AppPage.usage.title) { show(.usage) }
            Button(AppPage.voice.title) { show(.voice) }.disabled(AppLaunch.isPreview)
        }
    }

    private func show(_ page: AppPage) {
        model.page = page
        model.showManager?()
    }
}

import OpenNoTypeCore
