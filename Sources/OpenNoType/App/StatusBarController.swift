import AppKit
import Observation
import OpenNoTypeCore

/// Own the status item for the application lifetime, independently of manager windows.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let isPreview: Bool
    private let statusBar: NSStatusBar
    private let terminate: () -> Void
    private var observationID = UUID()
    private(set) var statusItem: NSStatusItem?

    init(model: AppModel, isPreview: Bool? = nil,
         statusBar: NSStatusBar? = nil, terminate: (() -> Void)? = nil) {
        self.model = model
        self.isPreview = isPreview ?? AppLaunch.isPreview
        self.statusBar = statusBar ?? .system
        self.terminate = terminate ?? { NSApp.terminate(nil) }
        super.init()
    }

    func start() {
        if let statusItem {
            statusItem.isVisible = true
            return
        }
        // NSStatusBar does not retain the item. Do not inherit SwiftUI's removable
        // extra state: this is the entry point when the Dock and main window are hidden.
        let item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        // AppKit chooses an autosave name even when none is supplied. Resetting it
        // clears saved visibility; its null-resettable getter need not return nil.
        item.autosaveName = nil
        item.behavior = []
        item.isVisible = true
        let menu = NSMenu(title: "OpenNoType")
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshAppearance()
        rebuildMenu(menu)
    }

    func stop() {
        observationID = UUID()
        guard let item = statusItem else { return }
        item.menu?.delegate = nil
        statusBar.removeStatusItem(item)
        statusItem = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func refreshAppearance() {
        guard let button = statusItem?.button else { return }
        let id = observationID
        withObservationTracking {
            button.image = AppBrand.menuBarImage(isRecording: model.isRecording)
            let label = model.isRecording ? L("OpenNoType — 녹음 중", "OpenNoType — Recording") : "OpenNoType"
            button.toolTip = label
            button.setAccessibilityLabel(label)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationID == id else { return }
                self.refreshAppearance()
            }
        }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: model.status, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        for (index, mode) in InputMode.allCases.enumerated() {
            let shortcut = model.preferences.hotkeys.indices.contains(index) ? model.preferences.hotkeys[index].label : ""
            let item = addItem("\(mode.title)  \(shortcut)", action: #selector(toggleInput(_:)), to: menu)
            item.tag = index
            item.isEnabled = !isPreview
        }
        if model.isBusy || model.historyReprocessing?.isProcessing == true {
            addItem(L("현재 작업 취소", "Cancel current task"), action: #selector(cancelCurrentTask(_:)), to: menu)
        }
        menu.addItem(.separator())
        addItem(L("OpenNoType 열기", "Open OpenNoType"), action: #selector(openManager(_:)), to: menu)
        addItem(L("사용량과 비용 보기", "View usage and costs"), action: #selector(openUsage(_:)), to: menu)
        if !model.failures.isEmpty {
            addItem(L("실패한 녹음 다시 처리 · \(model.failures.count)개", "Recover recordings · \(model.failures.count)"), action: #selector(openRecovery(_:)), to: menu)
        }
        let settings = addItem(L("설정…", "Settings…"), action: #selector(openSettings(_:)), key: ",", to: menu)
        settings.isEnabled = !isPreview
        menu.addItem(.separator())
        addItem(L("종료", "Quit"), action: #selector(quit(_:)), key: "q", to: menu)
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = .command
        menu.addItem(item)
        return item
    }

    @objc private func toggleInput(_ sender: NSMenuItem) {
        guard !isPreview, InputMode.allCases.indices.contains(sender.tag) else { return }
        let mode = InputMode.allCases[sender.tag]
        Task { [weak model] in await model?.toggle(mode) }
    }

    @objc private func cancelCurrentTask(_ sender: NSMenuItem) { model.cancel() }
    @objc private func openManager(_ sender: NSMenuItem) { show(model.page) }
    @objc private func openUsage(_ sender: NSMenuItem) { show(.usage) }
    @objc private func openRecovery(_ sender: NSMenuItem) { show(.recovery) }
    @objc private func openSettings(_ sender: NSMenuItem) {
        guard !isPreview else { return }
        show(.settings)
    }
    @objc private func quit(_ sender: NSMenuItem) { terminate() }

    private func show(_ page: AppPage) {
        model.page = page
        // MainView retains SwiftUI's openWindow action here, including after close.
        model.showManager?()
        NSApp.activate(ignoringOtherApps: true)
    }
}
