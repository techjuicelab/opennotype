import AppKit
import Carbon
import OpenNoTypeCore

struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    static let defaults: [HotkeyBinding] = [
        .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey)),
        .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | controlKey)),
        .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | controlKey | shiftKey))
    ]
    /// The separately installed prompt test app must not react to the normal app's shortcuts.
    static let promptTestDefaults: [HotkeyBinding] = [kVK_ANSI_D, kVK_ANSI_T, kVK_ANSI_R, kVK_ANSI_P].map {
        .init(keyCode: UInt32($0), modifiers: UInt32(controlKey | optionKey | cmdKey))
    }
    /// Preserve all three existing shortcuts when adding prompt composition. If its new
    /// default is already assigned, choose a free combination for the new mode only.
    static func addingPromptShortcut(to legacy: [HotkeyBinding]) -> [HotkeyBinding] {
        let candidates = [defaults[3]] + [
            UInt32(optionKey | controlKey | shiftKey | cmdKey),
            UInt32(optionKey | controlKey | cmdKey),
            UInt32(controlKey | shiftKey | cmdKey)
        ].map { HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: $0) }
        guard let available = candidates.first(where: { !legacy.contains($0) }) else { return legacy }
        return legacy + [available]
    }
    var label: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        let names: [UInt32: String] = [
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_Escape): "⎋",
            UInt32(kVK_Home): "Home",
            UInt32(kVK_End): "End",
            UInt32(kVK_PageUp): "PgUp",
            UInt32(kVK_PageDown): "PgDn",
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_Z): "Z", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_Q): "Q",
            UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_R): "R", UInt32(kVK_ANSI_Y): "Y",
            UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_L): "L", UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K",
            UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_M): "M",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5", UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
            UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Semicolon): ";",
            UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",",
            UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Slash): "/",
            UInt32(kVK_ANSI_Grave): "`",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
            UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
            UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
            UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18", UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
            UInt32(kVK_ANSI_Keypad0): "Num0", UInt32(kVK_ANSI_Keypad1): "Num1",
            UInt32(kVK_ANSI_Keypad2): "Num2", UInt32(kVK_ANSI_Keypad3): "Num3",
            UInt32(kVK_ANSI_Keypad4): "Num4", UInt32(kVK_ANSI_Keypad5): "Num5",
            UInt32(kVK_ANSI_Keypad6): "Num6", UInt32(kVK_ANSI_Keypad7): "Num7",
            UInt32(kVK_ANSI_Keypad8): "Num8", UInt32(kVK_ANSI_Keypad9): "Num9",
            UInt32(kVK_ANSI_KeypadDecimal): "Num.", UInt32(kVK_ANSI_KeypadMultiply): "Num*",
            UInt32(kVK_ANSI_KeypadPlus): "Num+", UInt32(kVK_ANSI_KeypadDivide): "Num/",
            UInt32(kVK_ANSI_KeypadMinus): "Num-", UInt32(kVK_ANSI_KeypadEquals): "Num=",
            UInt32(kVK_ANSI_KeypadEnter): "Enter", UInt32(kVK_ANSI_KeypadClear): "Clear"
        ]
        return text + (names[keyCode] ?? "Key \(keyCode)")
    }
    static func from(_ event: NSEvent) -> HotkeyBinding? {
        var flags: UInt32 = 0
        if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
        if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
        guard flags & UInt32(optionKey | cmdKey | controlKey) != 0 else { return nil }
        return .init(keyCode: UInt32(event.keyCode), modifiers: flags)
    }
}

@MainActor
protocol HotkeyRegistrationBackend: AnyObject {
    func register(_ binding: HotkeyBinding, index: Int) throws -> UUID
    func unregister(_ token: UUID)
}

@MainActor
private final class CarbonHotkeyBackend: HotkeyRegistrationBackend {
    private var references: [UUID: EventHotKeyRef] = [:]
    func register(_ binding: HotkeyBinding, index: Int) throws -> UUID {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers,
            EventHotKeyID(signature: 0x4F4E5459, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { throw HotkeyManager.HotkeyError.conflict(binding.label, restored: false) }
        let token = UUID()
        references[token] = reference
        return token
    }
    func unregister(_ token: UUID) {
        if let reference = references.removeValue(forKey: token) { UnregisterEventHotKey(reference) }
    }
}

@MainActor
final class HotkeyManager {
    var onPress: ((InputMode) -> Void)?
    var onActivation: ((InputMode, ShortcutActivationAction) -> Void)?
    var activationMode: ShortcutActivationMode = .toggle {
        didSet { if activationMode != oldValue { activationPolicy.cancelGesture() } }
    }
    private var activationPolicy = ShortcutActivationPolicy()
    private var references: [UUID] = []
    private let backend: HotkeyRegistrationBackend
    private var handler: EventHandlerRef?
    private var handlerReady = false
    private(set) var registeredBindings: [HotkeyBinding]?
    init(backend: HotkeyRegistrationBackend? = nil, installSystemHandler: Bool = true) {
        self.backend = backend ?? CarbonHotkeyBackend()
        guard installSystemHandler else { handlerReady = true; return }
        var specs = [kEventHotKeyPressed, kEventHotKeyReleased].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(pointer).takeUnretainedValue()
            let index = Int(identifier.id) - 1
            let isPressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let eventTime = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async {
                if InputMode.allCases.indices.contains(index) {
                    manager.handleKeyEvent(InputMode.allCases[index], isPressed: isPressed, at: eventTime)
                }
            }
            return noErr
        }, specs.count, &specs, Unmanaged.passUnretained(self).toOpaque(), &handler)
        handlerReady = status == noErr && handler != nil
    }
    func updateRecordingState(_ state: ShortcutRecordingState) {
        deliver(activationPolicy.updateRecordingState(state))
    }
    func handleKeyEvent(_ mode: InputMode, isPressed: Bool, at time: TimeInterval) {
        let event = isPressed
            ? activationPolicy.press(mode, activation: activationMode, at: time)
            : activationPolicy.release(mode, at: time)
        deliver(event)
    }
    private func deliver(_ event: ShortcutActivationEvent?) {
        guard let event else { return }
        if let onActivation { onActivation(event.mode, event.action) }
        else { onPress?(event.mode) }
    }
    func register(_ bindings: [HotkeyBinding]) throws {
        guard handlerReady else { throw HotkeyError.handlerUnavailable }
        guard bindings.count == InputMode.allCases.count,
              Set(bindings.map { "\($0.keyCode):\($0.modifiers)" }).count == bindings.count else { throw HotkeyError.duplicate }
        let previous = registeredBindings
        unregister()
        do { try install(bindings); registeredBindings = bindings }
        catch {
            unregister()
            let label: String
            if case HotkeyError.conflict(let key, _) = error { label = key }
            else { label = L("단축키", "Shortcut") }
            guard let previous else { throw HotkeyError.conflict(label, restored: false) }
            do { try install(previous); registeredBindings = previous }
            catch { unregister(); throw HotkeyError.rollbackFailed(label) }
            throw HotkeyError.conflict(label, restored: true)
        }
    }
    private func install(_ bindings: [HotkeyBinding]) throws {
        for (index, binding) in bindings.enumerated() {
            references.append(try backend.register(binding, index: index))
        }
    }
    private func unregister() {
        activationPolicy.resetPressedKeys()
        references.forEach { backend.unregister($0) }
        references.removeAll()
        registeredBindings = nil
    }
    enum HotkeyError: LocalizedError, Equatable {
        case duplicate, conflict(String, restored: Bool), rollbackFailed(String), handlerUnavailable
        var errorDescription: String? {
            switch self {
            case .duplicate: L("모드마다 다른 단축키를 지정해 주세요.", "Choose a different shortcut for each mode.")
            case .conflict(let key, true): L("\(key)을 등록하지 못해 이전 단축키를 복원했습니다. 다른 조합을 선택해 주세요.", "Could not register \(key). The previous shortcuts were restored. Choose another combination.")
            case .conflict(let key, false): L("\(key)을 등록하지 못했습니다. 단축키가 등록되지 않았으므로 설정에서 다른 조합을 선택해 주세요.", "Could not register \(key). No shortcuts are registered. Choose another combination in Settings.")
            case .rollbackFailed(let key): L("\(key) 등록과 이전 단축키 복원이 실패했습니다. 설정에서 단축키를 다시 지정해 주세요.", "Registration of \(key) and restoration both failed. Set your shortcuts again in Settings.")
            case .handlerUnavailable: L("단축키 이벤트를 준비하지 못했습니다. 앱을 다시 실행해 주세요.", "Shortcut events could not be prepared. Relaunch the app.")
            }
        }
    }
}
