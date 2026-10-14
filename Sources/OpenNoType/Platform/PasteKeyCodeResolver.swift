import Carbon
import CoreGraphics

/// Resolves the key equivalent with Command held, including layouts whose Command layer differs.
/// TIS is not thread safe and UI applications must query it on the main thread.
@MainActor
enum PasteKeyCodeResolver {
    static let fallback = CGKeyCode(kVK_ANSI_V)

    static func current() -> CGKeyCode {
        // This returns the layout used by an input method too, rather than its composition mode.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return fallback
        }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        return resolve(layoutData: data, keyboardType: UInt32(LMGetKbdType()))
    }

    static func resolve(layoutData: CFData?, keyboardType: UInt32) -> CGKeyCode {
        guard let layoutData, CFDataGetLength(layoutData) >= MemoryLayout<UCKeyboardLayout>.size,
              let bytes = CFDataGetBytePtr(layoutData) else { return fallback }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        return resolve { keyCode in
            // Each key is independent. Do not carry a dead-key state into the next candidate.
            var deadKeyState: UInt32 = 0
            var count = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), UInt32(cmdKey >> 8),
                                        keyboardType, OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                        &deadKeyState, characters.count, &count, &characters)
            guard status == noErr, count == 1 else { return nil }
            return characters[0]
        }
    }

    /// Injectable translation keeps mapping failures testable without changing the user's input source.
    static func resolve(translating: (CGKeyCode) -> UniChar?) -> CGKeyCode {
        for keyCode in CGKeyCode(0)..<128 {
            if let character = translating(keyCode), character == 0x76 || character == 0x56 {
                return keyCode
            }
        }
        // Preserve the existing paste behavior when the selected layout cannot be interpreted.
        return fallback
    }
}
