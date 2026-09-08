import AppKit
import Carbon
import OpenNoTypeCore

struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    static let defaults: [HotkeyBinding] = [
        .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey)),
        .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | controlKey))
    ]
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
final class HotkeyManager {
    var onPress: ((InputMode) -> Void)?
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var active = HotkeyBinding.defaults
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
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
    }
    func register(_ bindings: [HotkeyBinding]) throws {
        guard bindings.count == 3, Set(bindings.map { "\($0.keyCode):\($0.modifiers)" }).count == 3 else { throw HotkeyError.duplicate }
        let previous = active
        unregister()
        do { try install(bindings); active = bindings }
        catch { unregister(); try? install(previous); throw error }
    }
    private func install(_ bindings: [HotkeyBinding]) throws {
        for (index, binding) in bindings.enumerated() {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, EventHotKeyID(signature: 0x4F4E5459, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else { throw HotkeyError.conflict(binding.label) }
            references.append(reference)
        }
    }
    private func unregister() { references.forEach { UnregisterEventHotKey($0) }; references.removeAll() }
    enum HotkeyError: LocalizedError {
        case duplicate, conflict(String)
        var errorDescription: String? {
            switch self {
            case .duplicate: "모드마다 다른 단축키를 지정해 주세요."
            case .conflict(let key): "\(key)을 등록하지 못했습니다. 다른 조합을 선택해 주세요. 이전 단축키를 유지합니다."
            }
        }
    }
}
