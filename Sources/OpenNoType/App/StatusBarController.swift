import AppKit
import Observation
import OpenNoTypeCore

/// Own the status item for the application lifetime, independently of manager windows.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let isPreview: Bool
    private let identity: AppIdentity
    private let statusBar: NSStatusBar
    private let terminate: () -> Void
    private var observationID = UUID()
    private(set) var statusItem: NSStatusItem?

    init(model: AppModel, isPreview: Bool? = nil, identity: AppIdentity = .current,
         statusBar: NSStatusBar? = nil, terminate: (() -> Void)? = nil) {
        self.model = model
        self.isPreview = isPreview ?? AppLaunch.isPreview
        self.identity = identity
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
        let menu = NSMenu(title: identity.displayName)
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
            button.title = identity.isPromptTest ? "TEST" : ""
            button.imagePosition = identity.isPromptTest ? .imageLeading : .imageOnly
            let name = identity.displayName
            let label = model.isRecording ? L("\(name) — 녹음 중", "\(name) — Recording") : name
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
        if model.phase == .idle, let issue = model.primaryReadinessIssue {
            let setupItem = addItem(
                L("준비 필요: \(issue.shortTitle)…", "Setup needed: \(issue.shortTitle)…"),
                action: #selector(resolveReadinessIssue(_:)),
                to: menu
            )
            setupItem.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
            setupItem.isEnabled = !isPreview
        }
        menu.addItem(.separator())
        for (index, mode) in InputMode.allCases.enumerated() {
            let shortcut = model.preferences.hotkeys.indices.contains(index) ? model.preferences.hotkeys[index].label : ""
            let plainTitle = shortcut.isEmpty ? mode.title : "\(mode.title)  \(shortcut)"
            let item = addItem(plainTitle, action: #selector(toggleInput(_:)), to: menu)
            item.tag = index
            item.isEnabled = !isPreview
            if !shortcut.isEmpty {
                let attributed = NSMutableAttributedString(
                    string: mode.title,
                    attributes: [.font: NSFont.menuFont(ofSize: 0)]
                )
                attributed.append(NSAttributedString(
                    string: "   \(shortcut)",
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                ))
                item.attributedTitle = attributed
            }
        }
        if model.isBusy || model.historyReprocessing?.isProcessing == true {
            addItem(L("현재 작업 취소", "Cancel current task"), action: #selector(cancelCurrentTask(_:)), to: menu)
        }
        menu.addItem(.separator())
        let canEditQuickOptions = !isPreview && !model.preferencesRecoveryRequired && !model.isBusy
        menu.addItem(makeProcessingSubmenuItem(enabled: canEditQuickOptions))
        menu.addItem(makeOutputLanguageSubmenuItem(enabled: canEditQuickOptions))
        menu.addItem(.separator())
        addItem(L("\(identity.displayName) 열기", "Open \(identity.displayName)"), action: #selector(openManager(_:)), to: menu)
        addItem(AppPage.usage.title, action: #selector(openUsage(_:)), to: menu)
        if !model.failures.isEmpty {
            addItem(L("실패한 녹음 다시 처리 · \(model.failures.count)개", "Recover recordings · \(model.failures.count)"), action: #selector(openRecovery(_:)), to: menu)
        }
        let settings = addItem(L("설정…", "Settings…"), action: #selector(openSettings(_:)), key: ",", to: menu)
        settings.isEnabled = !isPreview
        menu.addItem(.separator())
        addItem(L("종료", "Quit"), action: #selector(quit(_:)), key: "q", to: menu)
    }

    private func makeProcessingSubmenuItem(enabled: Bool) -> NSMenuItem {
        let current = model.preferences.dictationProcessing.title
        let parent = NSMenuItem(
            title: L("받아쓰기 방식: \(current)", "Dictation mode: \(current)"),
            action: nil,
            keyEquivalent: ""
        )
        parent.isEnabled = enabled
        let submenu = NSMenu(title: L("받아쓰기 방식", "Dictation mode"))
        submenu.autoenablesItems = false
        for (index, mode) in DictationProcessingMode.allCases.enumerated() {
            let item = NSMenuItem(title: mode.title, action: #selector(selectDictationProcessing(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = model.preferences.dictationProcessing == mode ? .on : .off
            item.isEnabled = enabled
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func makeOutputLanguageSubmenuItem(enabled: Bool) -> NSMenuItem {
        let current = model.preferences.dictationOutputLanguage.title
        let parent = NSMenuItem(
            title: L("출력 언어: \(current)", "Output language: \(current)"),
            action: nil,
            keyEquivalent: ""
        )
        parent.isEnabled = enabled
        let submenu = NSMenu(title: L("출력 언어", "Output language"))
        submenu.autoenablesItems = false
        for (index, language) in DictationOutputLanguage.allCases.enumerated() {
            let item = NSMenuItem(title: language.title, action: #selector(selectOutputLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = model.preferences.dictationOutputLanguage == language ? .on : .off
            item.isEnabled = enabled
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
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

    @objc private func resolveReadinessIssue(_ sender: NSMenuItem) {
        guard !isPreview, let issue = model.primaryReadinessIssue else { return }
        model.openReadinessIssue(issue)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func selectDictationProcessing(_ sender: NSMenuItem) {
        guard !isPreview, !model.preferencesRecoveryRequired, !model.isBusy,
              DictationProcessingMode.allCases.indices.contains(sender.tag) else { return }
        model.preferences.dictationProcessing = DictationProcessingMode.allCases[sender.tag]
    }

    @objc private func selectOutputLanguage(_ sender: NSMenuItem) {
        guard !isPreview, !model.preferencesRecoveryRequired, !model.isBusy,
              DictationOutputLanguage.allCases.indices.contains(sender.tag) else { return }
        model.preferences.dictationOutputLanguage = DictationOutputLanguage.allCases[sender.tag]
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
        // The application owns the opener even while the manager is hidden or closed.
        model.showManager?()
        NSApp.activate(ignoringOtherApps: true)
    }
}
