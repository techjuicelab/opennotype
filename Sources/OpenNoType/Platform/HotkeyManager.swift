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
        let names: [UInt32: String] = [49:"Space", 0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U", 34:"I", 35:"P", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 36:"Return"]
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
    private var references: [UUID] = []
    private let backend: HotkeyRegistrationBackend
    private var handler: EventHandlerRef?
    private var handlerReady = false
    private(set) var registeredBindings: [HotkeyBinding]?
    init(backend: HotkeyRegistrationBackend? = nil, installSystemHandler: Bool = true) {
        self.backend = backend ?? CarbonHotkeyBackend()
        guard installSystemHandler else { handlerReady = true; return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(pointer).takeUnretainedValue()
            let index = Int(identifier.id) - 1
            DispatchQueue.main.async {
                if InputMode.allCases.indices.contains(index) { manager.onPress?(InputMode.allCases[index]) }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        handlerReady = status == noErr && handler != nil
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
