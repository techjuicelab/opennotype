import Carbon
import CoreGraphics

/// Constructs events without posting them, so the shortcut protocol can be tested without UI access.
enum PasteKeyEvents {
    @MainActor
    static func make(keyCode: CGKeyCode? = nil) -> [CGEvent]? {
        let keyCode = keyCode ?? PasteKeyCodeResolver.current()
        // Keep a held recording shortcut out of the generated paste's modifier state.
        guard let source = CGEventSource(stateID: .privateState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false) else { return nil }
        // Remappers track modifiers from flagsChanged, not flags on ordinary key events.
        // Preserve the native left-Command device flag and send its press/release explicitly.
        down.flags = commandDown.flags
        up.flags = commandDown.flags
        return [commandDown, down, up, commandUp]
    }
}
