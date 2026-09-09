import AppKit
import SwiftUI

@main
struct OpenNoTypeApp: App {
    @State private var model = AppModel()
    @State private var voiceBar: VoiceBarController?
    var body: some Scene {
        Window("OpenNoType", id: "main") {
            MainView(model: model)
                .task {
                    _ = Updater.shared
                    if voiceBar == nil { voiceBar = VoiceBarController(model: model) }
                }
                .preferredColorScheme(model.preferences.appearance == "dark" ? .dark : model.preferences.appearance == "light" ? .light : nil)
        }
        .defaultSize(width: 1010, height: 730)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("업데이트 확인…") { Updater.shared.check() }
                Divider()
            }
        }
        MenuBarExtra("OpenNoType", systemImage: model.isRecording ? "mic.fill" : "waveform") {
            MenuContent(model: model)
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
        }
        if model.isBusy { Button("현재 작업 취소") { model.cancel() } }
        Divider()
        Button("OpenNoType 열기") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("종료") { model.cancel(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

import OpenNoTypeCore
