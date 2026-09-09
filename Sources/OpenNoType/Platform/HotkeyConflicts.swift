import AppKit
import Foundation

/// Carbon global shortcuts are not exclusive: every app that registered the same combination is
/// notified. When another app reacts to our shortcut by activating itself, focus leaves the field the
/// user was writing in. This reads the shortcut preferences of known apps so the overlap can be
/// explained before the first failed insertion. Only shortcut definitions are read, nothing else.
enum HotkeyConflicts {
    struct KnownApp {
        let bundleID: String
        let displayName: String
        /// UserDefaults keys written by the `KeyboardShortcuts` package: JSON `{"carbonKeyCode":49,"carbonModifiers":2048}`.
        let shortcutKeys: [String]
        let settingsHint: String
    }

    static let knownApps: [KnownApp] = [
        KnownApp(bundleID: "com.openai.chat", displayName: "ChatGPT",
                 shortcutKeys: ["KeyboardShortcuts_toggleLauncher", "KeyboardShortcuts_toggleAttachedLauncher"],
                 settingsHint: "ChatGPT 설정 › 키보드 단축키에서 채팅 바 단축키를 바꾸거나 꺼 주세요.")
    ]

    /// Parses one stored shortcut. Returns nil for missing, cleared, or unrecognised values.
    static func binding(fromStoredShortcut value: Any?) -> HotkeyBinding? {
        let data: Data?
        switch value {
        case let string as String: data = string.data(using: .utf8)
        case let raw as Data: data = raw
        default: data = nil
        }
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keyCode = (object["carbonKeyCode"] as? NSNumber)?.uint32Value,
              let modifiers = (object["carbonModifiers"] as? NSNumber)?.uint32Value else { return nil }
        return HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
    }

    /// Human-readable warnings for every binding that another *running* app also uses. Preferences of
    /// apps that are installed but not running are ignored: only a running process can hold a hotkey.
    static func warnings(for bindings: [HotkeyBinding],
                         defaults: (String) -> [String: Any]? = { UserDefaults(suiteName: $0)?.dictionaryRepresentation() },
                         isRunning: (String) -> Bool = { id in NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == id } }) -> [String] {
        var warnings: [String] = []
        for app in knownApps where isRunning(app.bundleID) {
            guard let stored = defaults(app.bundleID) else { continue }
            let theirs = app.shortcutKeys.compactMap { binding(fromStoredShortcut: stored[$0]) }
            for binding in bindings where theirs.contains(binding) {
                warnings.append("\(app.displayName) 앱도 \(binding.label) 단축키를 사용합니다. 이 단축키를 누르면 \(app.displayName) 창이 앞으로 나와 자동입력이 실패할 수 있습니다. \(app.settingsHint) 또는 OpenNoType의 단축키를 바꿔 주세요.")
            }
        }
        return warnings
    }
}
