import AppKit
import ApplicationServices
import Carbon
import OpenNoTypeCore

struct InputTarget {
    let pid: pid_t
    let bundleID: String?
    let element: AXUIElement
    let originalValue: String?
    let range: CFRange?
    let selectedText: String?
    let context: String?
}

/// Accessibility ranges use UTF-16 offsets, not Swift Character counts.
struct InsertionSnapshot {
    let original: String
    let range: NSRange
    let prefix: String
    let suffix: String

    init?(original: String?, range: CFRange?) {
        guard let original, let range, range.location >= 0, range.length >= 0 else { return nil }
        let source = original as NSString
        guard range.location <= source.length, range.length <= source.length - range.location,
              Self.isScalarBoundary(range.location, in: source),
              Self.isScalarBoundary(range.location + range.length, in: source),
              Range(NSRange(location: range.location, length: range.length), in: original) != nil else { return nil }
        self.original = original
        self.range = NSRange(location: range.location, length: range.length)
        prefix = source.substring(to: range.location)
        suffix = source.substring(from: range.location + range.length)
    }

    func expectedValue(inserting text: String) -> String { prefix + text + suffix }

    private static func isScalarBoundary(_ offset: Int, in text: NSString) -> Bool {
        guard offset > 0, offset < text.length else { return true }
        return !((0xD800...0xDBFF).contains(text.character(at: offset - 1)) &&
                 (0xDC00...0xDFFF).contains(text.character(at: offset)))
    }

    func editedText(inserting originalInsertion: String, current: String, selection: CFRange) -> String? {
        guard observationIsBounded(inserting: originalInsertion, current: current, selection: selection) else { return nil }
        let source = current as NSString
        let prefixLength = (prefix as NSString).length
        let suffixLength = (suffix as NSString).length
        let span = NSRange(location: prefixLength, length: source.length - prefixLength - suffixLength)
        guard Range(span, in: current) != nil else { return nil }
        let edited = source.substring(with: span)
        guard edited != originalInsertion, !edited.isEmpty, edited.count <= 2_000 else { return nil }
        // Typing more after the inserted text is a new composition, not a correction to learn.
        guard !edited.hasPrefix(originalInsertion) else { return nil }
        // Empty fields have no outside anchors. Only a validated single-word replacement can
        // identify the original insertion there; never return the field as a broad review candidate.
        if prefix.isEmpty && suffix.isEmpty,
           CorrectionLearner.suggestion(original: originalInsertion, edited: edited) == nil { return nil }
        return edited
    }

    func observationIsBounded(inserting originalInsertion: String, current: String, selection: CFRange) -> Bool {
        guard !originalInsertion.isEmpty, originalInsertion.count <= 2_000,
              current.hasPrefix(prefix), current.hasSuffix(suffix) else { return false }
        let source = current as NSString
        let start = (prefix as NSString).length
        let end = source.length - (suffix as NSString).length
        guard start <= end, end - start <= 8_000,
              selection.location >= start, selection.length >= 0, selection.location <= end,
              selection.length <= end - selection.location else { return false }
        let span = NSRange(location: start, length: end - start)
        guard Range(span, in: current) != nil else { return false }
        let candidate = source.substring(with: span)
        guard candidate.count <= 2_000 else { return false }
        if candidate != originalInsertion, candidate.hasPrefix(originalInsertion) { return false }
        // The tracked insertion span contracts/expands with a bounded edit; unrelated trailing
        // composition is rejected above, including in initially empty messenger input fields.
        return true
    }
}

@MainActor
final class TextInsertion {
    private static var pasteInProgress = false
    static var permitted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func value(_ element: AXUIElement) -> String? { attribute(element, kAXValueAttribute) as? String }
    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let raw = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range) else { return nil }
        return range
    }
    static func focused() -> AXUIElement? {
        guard permitted, let raw = attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }
    static func capture(allowedContextApps: Set<String>) -> InputTarget? {
        guard !IsSecureEventInputEnabled(), let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier, let element = focused(),
              attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { return nil }
        let text = value(element)
        let range = selectedRange(element)
        var context: String?
        if let bundle = app.bundleIdentifier, allowedContextApps.contains(bundle),
           let snapshot = InsertionSnapshot(original: text, range: range) {
            context = String(snapshot.prefix.suffix(1_000))
        }
        return InputTarget(pid: app.processIdentifier, bundleID: app.bundleIdentifier, element: element,
            originalValue: text, range: range, selectedText: attribute(element, kAXSelectedTextAttribute) as? String, context: context)
    }
    static func isCurrent(_ target: InputTarget, unchanged: Bool = false) -> Bool {
        guard !IsSecureEventInputEnabled(), NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
              let element = focused(), CFEqual(element, target.element),
              attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { return false }
        if unchanged {
            guard let snapshot = InsertionSnapshot(original: target.originalValue, range: target.range),
                  let now = selectedRange(element), value(element) == snapshot.original,
                  now.location == snapshot.range.location, now.length == snapshot.range.length else { return false }
        }
        return true
    }

    static func insert(_ text: String, at target: InputTarget,
                       isCancelled: @escaping @MainActor () -> Bool = { false }) async -> Bool {
        guard !text.isEmpty, !pasteInProgress, !Task.isCancelled, !isCancelled(),
              let snapshot = InsertionSnapshot(original: target.originalValue, range: target.range),
              isCurrent(target, unchanged: true) else { return false }
        let expected = snapshot.expectedValue(inserting: text)
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(target.element, kAXSelectedTextAttribute as CFString, &settable) == .success,
           settable.boolValue {
            guard !Task.isCancelled, !isCancelled(), isCurrent(target, unchanged: true) else { return false }
            let status = AXUIElementSetAttributeValue(target.element, kAXSelectedTextAttribute as CFString, text as CFString)
            if status == .success {
                // A successful AX submission must never be retried with Cmd-V: delivery may be asynchronous.
                return await waitForInsertion(expected, at: target, timeout: 1.0, isCancelled: isCancelled)
            }
            if value(target.element) == expected { return !Task.isCancelled && !isCancelled() }
        }

        // Construct both events before touching the clipboard, so an allocation failure cannot destroy it.
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false),
              !Task.isCancelled, !isCancelled(), isCurrent(target, unchanged: true),
              let clipboard = ClipboardTransaction(pasteboard: .general) else { return false }
        down.flags = .maskCommand; up.flags = .maskCommand
        pasteInProgress = true
        defer { clipboard.restore(); pasteInProgress = false }
        guard !Task.isCancelled, !isCancelled(), isCurrent(target, unchanged: true), clipboard.install(text) else { return false }
        // Snapshotting lazy clipboard representations can take time. Recheck immediately before dispatch.
        guard !Task.isCancelled, !isCancelled(), clipboard.ownsContents,
              isCurrent(target, unchanged: true) else { return false }
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)

        // Once Cmd-V is submitted it cannot be recalled. Keep the clipboard lease alive independently
        // of task cancellation until the exact edit is visible, or a bounded delivery deadline elapses.
        let started = ProcessInfo.processInfo.systemUptime
        var acknowledged = false
        repeat {
            await uncancellablePause(0.05)
            if value(target.element) == expected { acknowledged = true }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            if acknowledged && elapsed >= 0.2 { break }
            if elapsed >= 3.0 { break }
        } while true
        return acknowledged && !Task.isCancelled && !isCancelled()
    }

    private static func waitForInsertion(_ expected: String, at target: InputTarget, timeout: TimeInterval,
                                         isCancelled: @escaping @MainActor () -> Bool) async -> Bool {
        let started = ProcessInfo.processInfo.systemUptime
        repeat {
            if value(target.element) == expected { return !Task.isCancelled && !isCancelled() }
            if Task.isCancelled || isCancelled() { return false }
            await uncancellablePause(0.05)
        } while ProcessInfo.processInfo.systemUptime - started < timeout
        return value(target.element) == expected && !Task.isCancelled && !isCancelled()
    }

    static func uncancellablePause(_ seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { continuation.resume() }
        }
    }

    static func editedInsertion(original: String, target: InputTarget) -> String? {
        guard isCurrent(target), let snapshot = InsertionSnapshot(original: target.originalValue, range: target.range),
              let current = value(target.element), let selection = selectedRange(target.element) else { return nil }
        return snapshot.editedText(inserting: original, current: current, selection: selection)
    }

    static func observationShouldStop(original: String, target: InputTarget) -> Bool {
        guard isCurrent(target), let snapshot = InsertionSnapshot(original: target.originalValue, range: target.range),
              let current = value(target.element), let selection = selectedRange(target.element) else { return true }
        return !snapshot.observationIsBounded(inserting: original, current: current, selection: selection)
    }
}

/// Best-effort compare-and-restore: NSPasteboard has no cross-process atomic compare-and-swap API.
/// All local mutation steps are synchronous on MainActor and newer external copies always take priority.
@MainActor
final class ClipboardTransaction {
    private static let ownerType = NSPasteboard.PasteboardType("app.opennotype.clipboard-transaction")
    private let pasteboard: NSPasteboard
    private let saved: [NSPasteboardItem]
    private let initialChangeCount: Int
    private let token = UUID().uuidString
    private var ownedChangeCount: Int?
    private var requiresToken = false

    init?(pasteboard: NSPasteboard) {
        let initial = pasteboard.changeCount
        guard let items = pasteboard.pasteboardItems else {
            // A truly empty pasteboard is safe; an unreadable populated one must remain untouched.
            guard pasteboard.types?.isEmpty != false else { return nil }
            self.pasteboard = pasteboard; saved = []; initialChangeCount = initial
            return
        }
        var snapshot: [NSPasteboardItem] = []
        var byteCount = 0
        for item in items {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                byteCount += data.count
                guard byteCount <= 32_000_000, copy.setData(data, forType: type) else { return nil }
            }
            snapshot.append(copy)
        }
        guard pasteboard.changeCount == initial else { return nil }
        self.pasteboard = pasteboard; saved = snapshot; initialChangeCount = initial
    }

    var ownsContents: Bool {
        guard let revision = ownedChangeCount, pasteboard.changeCount == revision else { return false }
        if requiresToken, pasteboard.string(forType: Self.ownerType) != token { return false }
        return pasteboard.changeCount == revision
    }

    func install(_ text: String) -> Bool {
        guard ownedChangeCount == nil, pasteboard.changeCount == initialChangeCount else { return false }
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string), item.setString(token, forType: Self.ownerType) else { return false }
        let cleared = pasteboard.clearContents()
        ownedChangeCount = cleared
        guard pasteboard.changeCount == cleared else { ownedChangeCount = nil; return false }
        guard pasteboard.writeObjects([item]) else { restore(); return false }
        let revision = pasteboard.changeCount
        guard pasteboard.string(forType: Self.ownerType) == token, pasteboard.changeCount == revision else {
            ownedChangeCount = nil; return false
        }
        ownedChangeCount = revision; requiresToken = true
        return true
    }

    @discardableResult
    func restore() -> Bool {
        guard ownsContents else { ownedChangeCount = nil; return true }
        let cleared = pasteboard.clearContents()
        ownedChangeCount = nil
        guard pasteboard.changeCount == cleared else { return true }
        if saved.isEmpty { return true }
        return pasteboard.writeObjects(saved)
    }
}
