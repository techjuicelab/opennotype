import OpenNoTypeCore
import AppKit
import Carbon
import Foundation

/// Carbon global shortcuts are not exclusive: every app that registered the same combination is
/// notified. When another app reacts to our shortcut, the dictation either ends up in that app or focus
/// leaves the field the user was writing in. This reads the shortcut preferences of known apps so the
/// overlap can be explained before the first failed insertion. Only shortcut definitions are inspected;
/// no third-party settings, commands, or rule descriptions are copied into warnings or changed.
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

    static var knownApps: [KnownApp] { [
        KnownApp(bundleID: "com.openai.chat", displayName: "ChatGPT",
                 bindings: { stored in
                     guard let stored else { return [] }
                     // UserDefaults keys written by the `KeyboardShortcuts` package: JSON `{"carbonKeyCode":49,"carbonModifiers":2048}`.
                     return ["KeyboardShortcuts_toggleLauncher", "KeyboardShortcuts_toggleAttachedLauncher"]
                         .compactMap { binding(fromStoredShortcut: stored[$0]) }
                 },
                 consequence: L("이 단축키를 누르면 ChatGPT 창이 앞으로 나와 자동입력이 실패할 수 있습니다.", "This shortcut may bring ChatGPT to the front and prevent automatic insertion."),
                 settingsHint: L("ChatGPT 설정 › 키보드 단축키에서 채팅 바 단축키를 바꾸거나 꺼 주세요. 또는 OpenNoType의 단축키를 바꿔 주세요.", "Change or disable the chat bar shortcut in ChatGPT Settings › Keyboard shortcuts, or change the OpenNoType shortcut.")),
        // OpenNoType's closed predecessor keeps starting at login on Macs where it was installed and
        // ships with the same default shortcuts. Both apps then record the same press; notype's
        // accessibility write into Electron apps is ignored, so its result only reaches the clipboard.
        // The warning assumes notype's launch-time hotkey registration succeeded (it registers every
        // stored binding of every mode, non-exclusively, before onboarding).
        KnownApp(bundleID: "space.techjuicelab.notype", displayName: "notype",
                 bindings: { stored in notypeBindings(fromStoredBindings: stored?["shortcutBindings.v1"]) },
                 consequence: L("이 단축키를 누르면 두 앱이 함께 녹음을 시작해 결과가 notype 쪽에서 처리되거나 입력창에 들어가지 않을 수 있습니다.", "This shortcut may start recording in both apps, sending the result to notype or preventing insertion into your text field."),
                 settingsHint: L("notype은 OpenNoType의 이전 버전입니다. 메뉴 막대의 notype 아이콘에서 종료하고, 시스템 설정 › 일반 › 로그인 항목에서 notype을 제거해 주세요. notype을 계속 쓰려면 OpenNoType의 단축키를 바꿔 주세요.", "notype is the previous version of OpenNoType. Quit it from its menu bar icon and remove it in System Settings › General › Login Items. To keep using notype, change the OpenNoType shortcut.")),
        // The Settings app may be closed while the user-session core service keeps remapping keys.
        KnownApp(bundleID: "org.pqrs.Karabiner-Core-Service", displayName: "Karabiner-Elements",
                 bindings: { stored in karabinerBindings(fromConfiguration: stored?["configuration"]) },
                 consequence: L("선택 프로필의 키 변환과 겹쳐 다른 동작으로 처리될 수 있습니다.", "A key remapping in the selected profile may trigger a different action."),
                 settingsHint: L("Karabiner-Elements 설정 › Complex Modifications에서 해당 키 조합의 규칙을 확인해 주세요. 또는 OpenNoType의 단축키를 바꿔 주세요.", "Check the rules for this key combination in Karabiner-Elements Settings › Complex Modifications, or change the OpenNoType shortcut."))
    ] }

    /// notype registers these when nothing valid is stored (`ShortcutBinding.defaults` in its source):
    /// 받아쓰기 ⌥Space, 번역 ⌥⇧T, 고쳐쓰기 ⌥⇧Space.
    static let notypeDefaultBindings: [HotkeyBinding] = [
        HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        HotkeyBinding(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey | shiftKey)),
        HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey))
    ]
    private static let notypeModes = ["dictate", "translate", "rewrite"]

    /// Conservative read-only detection, not an interpreter for Karabiner's rule engine. Only an
    /// unambiguous selected profile, unconditional basic rules, exact keys, and unsided mandatory
    /// modifiers are supported. Device/frontmost/variable conditions, simultaneous keys, optional
    /// modifiers, simple remaps and event-tap fallback settings do not establish a shortcut conflict.
    static func karabinerBindings(fromConfiguration value: Any?) -> [HotkeyBinding] {
        guard let root = jsonObject(from: value) as? [String: Any],
              let profiles = root["profiles"] as? [[String: Any]] else { return [] }
        let selected = profiles.filter {
            guard let value = $0["selected"] as? NSNumber,
                  CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
            return value.boolValue
        }
        guard selected.count == 1,
              let modifications = selected[0]["complex_modifications"] as? [String: Any],
              let rules = modifications["rules"] as? [[String: Any]] else { return [] }
        let keys: [String: UInt32] = [
            "spacebar": 49, "return_or_enter": 36,
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37,
            "j": 38, "k": 40, "n": 45, "m": 46
        ]
        let modifierBits: [String: UInt32] = ["command": UInt32(cmdKey), "option": UInt32(optionKey),
                                              "control": UInt32(controlKey), "shift": UInt32(shiftKey)]
        var result: [HotkeyBinding] = []
        for rule in rules where (rule["enabled"] as? Bool) != false {
            for manipulator in rule["manipulators"] as? [[String: Any]] ?? [] {
                guard manipulator["type"] as? String == "basic",
                      manipulator["conditions"] == nil || (manipulator["conditions"] as? [Any])?.isEmpty == true,
                      let from = manipulator["from"] as? [String: Any],
                      Set(from.keys).isSubset(of: ["key_code", "modifiers"]),
                      let key = from["key_code"] as? String, let keyCode = keys[key],
                      let modifiers = from["modifiers"] as? [String: Any],
                      Set(modifiers.keys).isSubset(of: ["mandatory", "optional"]),
                      let mandatory = modifiers["mandatory"] as? [String], !mandatory.isEmpty,
                      modifiers["optional"] == nil || (modifiers["optional"] as? [Any])?.isEmpty == true,
                      mandatory.allSatisfy({ modifierBits[$0] != nil }),
                      ["to", "to_if_alone", "to_if_held_down", "to_after_key_up"].contains(where: {
                          !(manipulator[$0] as? [[String: Any]] ?? []).isEmpty
                      }) else { continue }
                let bits = mandatory.reduce(UInt32(0)) { $0 | modifierBits[$1]! }
                let binding = HotkeyBinding(keyCode: keyCode, modifiers: bits)
                if !result.contains(binding) { result.append(binding) }
            }
        }
        return result
    }

    private static func shortcutPreferences(for bundleID: String) -> [String: Any]? {
        guard bundleID == "org.pqrs.Karabiner-Core-Service" else {
            return UserDefaults(suiteName: bundleID)?.dictionaryRepresentation()
        }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/karabiner/karabiner.json")
        // Do not turn a malformed or unexpectedly large user configuration into startup work.
        let limit = 4_000_000
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit,
              let data = try? Data(contentsOf: url), data.count <= limit else { return nil }
        return ["configuration": data]
    }

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
                         defaults: (String) -> [String: Any]? = { shortcutPreferences(for: $0) },
                         isRunning: (String) -> Bool = { id in NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == id } }) -> [String] {
        var warnings: [String] = []
        for app in knownApps where isRunning(app.bundleID) {
            let theirs = app.bindings(defaults(app.bundleID))
            for binding in bindings where theirs.contains(binding) {
                warnings.append(L("\(app.displayName) 앱도 \(binding.label) 단축키를 사용합니다. \(app.consequence) \(app.settingsHint)", "\(app.displayName) also uses \(binding.label). \(app.consequence) \(app.settingsHint)"))
            }
        }
        return warnings
    }
}
