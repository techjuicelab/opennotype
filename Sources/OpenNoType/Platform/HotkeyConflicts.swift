import AppKit
import Carbon
import Foundation

/// Carbon global shortcuts are not exclusive: every app that registered the same combination is
/// notified. When another app reacts to our shortcut, the dictation either ends up in that app or focus
/// leaves the field the user was writing in. This reads the shortcut preferences of known apps so the
/// overlap can be explained before the first failed insertion. Only shortcut definitions are read, nothing else.
enum HotkeyConflicts {
    struct KnownApp {
        let bundleID: String
        let displayName: String
        /// Every shortcut the app currently holds, derived from its preferences domain (nil when the
        /// domain cannot be read). Apps that fall back to built-in defaults return those defaults.
        let bindings: ([String: Any]?) -> [HotkeyBinding]
        /// What happens when both apps receive the same press.
        let consequence: String
        let settingsHint: String
    }

    static let knownApps: [KnownApp] = [
        KnownApp(bundleID: "com.openai.chat", displayName: "ChatGPT",
                 bindings: { stored in
                     guard let stored else { return [] }
                     // UserDefaults keys written by the `KeyboardShortcuts` package: JSON `{"carbonKeyCode":49,"carbonModifiers":2048}`.
                     return ["KeyboardShortcuts_toggleLauncher", "KeyboardShortcuts_toggleAttachedLauncher"]
                         .compactMap { binding(fromStoredShortcut: stored[$0]) }
                 },
                 consequence: "이 단축키를 누르면 ChatGPT 창이 앞으로 나와 자동입력이 실패할 수 있습니다.",
                 settingsHint: "ChatGPT 설정 › 키보드 단축키에서 채팅 바 단축키를 바꾸거나 꺼 주세요. 또는 OpenNoType의 단축키를 바꿔 주세요."),
        // OpenNoType's closed predecessor keeps starting at login on Macs where it was installed and
        // ships with the same default shortcuts. Both apps then record the same press; notype's
        // accessibility write into Electron apps is ignored, so its result only reaches the clipboard.
        // The warning assumes notype's launch-time hotkey registration succeeded (it registers every
        // stored binding of every mode, non-exclusively, before onboarding).
        KnownApp(bundleID: "space.techjuicelab.notype", displayName: "notype",
                 bindings: { stored in notypeBindings(fromStoredBindings: stored?["shortcutBindings.v1"]) },
                 consequence: "이 단축키를 누르면 두 앱이 함께 녹음을 시작해 결과가 notype 쪽에서 처리되거나 입력창에 들어가지 않을 수 있습니다.",
                 settingsHint: "notype은 OpenNoType의 이전 버전입니다. 메뉴 막대의 notype 아이콘에서 종료하고, 시스템 설정 › 일반 › 로그인 항목에서 notype을 제거해 주세요. notype을 계속 쓰려면 OpenNoType의 단축키를 바꿔 주세요.")
    ]

    /// notype registers these when nothing valid is stored (`ShortcutBinding.defaults` in its source):
    /// 받아쓰기 ⌥Space, 번역 ⌥⇧T, 고쳐쓰기 ⌥⇧Space.
    static let notypeDefaultBindings: [HotkeyBinding] = [
        HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        HotkeyBinding(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey | shiftKey)),
        HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey))
    ]
    private static let notypeModes = ["dictate", "translate", "rewrite"]

    /// Parses one `KeyboardShortcuts`-style stored shortcut. Returns nil for missing, cleared, or unrecognised values.
    static func binding(fromStoredShortcut value: Any?) -> HotkeyBinding? {
        guard let object = jsonObject(from: value) as? [String: Any],
              let keyCode = (object["carbonKeyCode"] as? NSNumber)?.uint32Value,
              let modifiers = (object["carbonModifiers"] as? NSNumber)?.uint32Value else { return nil }
        return HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
    }

    /// Parses notype's `shortcutBindings.v1` value the way notype does. The value must be Data that
    /// decodes as the flat alternating array `JSONEncoder` writes for `[ShortcutMode: [ShortcutBinding]]`
    /// (`["dictate", [{"keyCode": 49, "modifiers": 2048}], "translate", [...], "rewrite", [...]]`); every
    /// mode needs at least one binding, no binding may repeat, and each needs a ⌘/⌥/⌃/⇧ bit. On any other
    /// value (missing, a keyed object, a string, a malformed entry, a missing mode) notype registers its
    /// defaults, so this returns them too: all-or-nothing, never a partially parsed set.
    static func notypeBindings(fromStoredBindings value: Any?) -> [HotkeyBinding] {
        guard let data = value as? Data, let flat = (try? JSONSerialization.jsonObject(with: data)) as? [Any],
              flat.count.isMultiple(of: 2) else { return notypeDefaultBindings }
        var decoded: [String: [HotkeyBinding]] = [:]
        for index in stride(from: 0, to: flat.count, by: 2) {
            guard let mode = flat[index] as? String, notypeModes.contains(mode),
                  let entries = flat[index + 1] as? [[String: Any]] else { return notypeDefaultBindings }
            var bindings: [HotkeyBinding] = []
            for entry in entries {
                guard let keyCode = uint32(entry["keyCode"]), let modifiers = uint32(entry["modifiers"]) else { return notypeDefaultBindings }
                bindings.append(HotkeyBinding(keyCode: keyCode, modifiers: modifiers))
            }
            // A repeated mode name overwrites the earlier one, as Dictionary decoding does.
            decoded[mode] = bindings
        }
        let flattened = notypeModes.flatMap { decoded[$0] ?? [] }
        guard notypeModes.allSatisfy({ !(decoded[$0] ?? []).isEmpty }),
              Set(flattened.map { "\($0.keyCode):\($0.modifiers)" }).count == flattened.count,
              flattened.allSatisfy({ $0.modifiers & UInt32(cmdKey | optionKey | controlKey | shiftKey) != 0 }) else {
            return notypeDefaultBindings
        }
        return flattened
    }

    /// Mirrors `JSONDecoder`'s UInt32 decoding: an integral, non-negative, in-range number that is not a Bool.
    private static func uint32(_ value: Any?) -> UInt32? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double >= 0, double <= Double(UInt32.max), double == double.rounded() else { return nil }
        return number.uint32Value
    }

    private static func jsonObject(from value: Any?) -> Any? {
        let data: Data?
        switch value {
        case let string as String: data = string.data(using: .utf8)
        case let raw as Data: data = raw
        default: data = nil
        }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Human-readable warnings for every binding that another *running* app also uses. Preferences of
    /// apps that are installed but not running are ignored: only a running process can hold a hotkey.
    static func warnings(for bindings: [HotkeyBinding],
                         defaults: (String) -> [String: Any]? = { UserDefaults(suiteName: $0)?.dictionaryRepresentation() },
                         isRunning: (String) -> Bool = { id in NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == id } }) -> [String] {
        var warnings: [String] = []
        for app in knownApps where isRunning(app.bundleID) {
            let theirs = app.bindings(defaults(app.bundleID))
            for binding in bindings where theirs.contains(binding) {
                warnings.append("\(app.displayName) 앱도 \(binding.label) 단축키를 사용합니다. \(app.consequence) \(app.settingsHint)")
            }
        }
        return warnings
    }
}
