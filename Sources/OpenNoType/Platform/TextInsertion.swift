import AppKit
import ApplicationServices
import Carbon
import OpenNoTypeCore
import os

struct InputTarget {
    let pid: pid_t
    let bundleID: String?
    let bundleURL: URL?
    /// The focused accessibility element at capture time. Apps that do not answer accessibility
    /// queries (some Electron apps) still produce a target; only keyboard paste is available for them.
    let element: AXUIElement?
    let originalValue: String?
    let range: CFRange?
    let selectedText: String?
    let context: String?
    /// The focused element was a password field; nothing was read from it and nothing may be written to it.
    let secureField: Bool

    init(pid: pid_t, bundleID: String?, bundleURL: URL? = nil, element: AXUIElement?,
         originalValue: String?, range: CFRange?, selectedText: String?, context: String?, secureField: Bool = false) {
        self.pid = pid; self.bundleID = bundleID; self.bundleURL = bundleURL; self.element = element
        self.originalValue = originalValue; self.range = range; self.selectedText = selectedText; self.context = context
        self.secureField = secureField
    }

    var snapshot: InsertionSnapshot? { InsertionSnapshot(original: originalValue, range: range) }
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
           CorrectionLearner.proposedCorrection(original: originalInsertion, edited: edited) == nil { return nil }
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

/// Where the user's focus is, relative to the app captured when recording started.
enum TargetRelation: String, Equatable {
    /// Same app in front and the same element focused.
    case sameElement
    /// Same app in front, another element focused (the user moved the caret inside the app).
    case sameApp
    /// Another third-party app is in front.
    case otherApp
    /// OpenNoType itself is in front.
    case ownApp
    /// Secure keyboard entry is active or a password field is focused.
    case secureInput
    /// The captured app is no longer running.
    case gone
}

/// Read-only platform operations used by capture and rewrite validation. Tests supply synthetic
/// elements and observations without reading another app, requesting permissions, or pasting.
@MainActor
struct InputTargetEnvironment {
    struct Application: Equatable {
        let pid: pid_t
        let bundleID: String?
        let bundleURL: URL?
    }

    var frontmostApplication: () -> Application?
    var focused: () -> AXUIElement?
    var focusedIn: (pid_t) async -> AXUIElement?
    var elementPID: (AXUIElement) -> pid_t?
    var secureInputActive: () -> Bool
    var isSecureField: (AXUIElement) -> Bool
    var value: (AXUIElement) -> String?
    var selectedRange: (AXUIElement) -> CFRange?
    var selectedText: (AXUIElement) -> String?
}

@MainActor
final class TextInsertion {
    private static var pasteInProgress = false
    private static let log = Logger(subsystem: "app.opennotype.mac", category: "insertion")
    private static let textLikeRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField", "AXWebArea", kAXGroupRole
    ]
    /// Roles that never take typed or pasted text. Focus rests on them after a click in Chromium apps
    /// (a "send" button, for example); a posted Cmd-V would vanish there without any trace.
    static let nonTextRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXMenuItem", "AXMenuButton", "AXPopUpButton", "AXSlider",
        "AXLink", "AXImage", "AXDisclosureTriangle", "AXIncrementor", "AXScrollBar", "AXTabGroup", "AXToolbar"
    ]
    /// Unknown or missing roles (apps that expose little accessibility) still get the paste.
    static func acceptsKeyboardText(role: String?) -> Bool { role.map { !nonTextRoles.contains($0) } ?? true }
    static var permitted: Bool { AXIsProcessTrusted() }
    static var secureInputActive: Bool { IsSecureEventInputEnabled() }

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
    private static func isSecureField(_ element: AXUIElement) -> Bool {
        attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
    }
    /// Keyboard paste lands wherever the caret is; only elements that can hold a caret qualify.
    private static func isTextLike(_ element: AXUIElement) -> Bool {
        guard !isSecureField(element), let role = attribute(element, kAXRoleAttribute) as? String else { return false }
        return textLikeRoles.contains(role)
    }
    private static func focusedElement(of parent: AXUIElement) -> AXUIElement? {
        guard let raw = attribute(parent, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }
    static func focused() -> AXUIElement? {
        guard permitted else { return nil }
        return focusedElement(of: AXUIElementCreateSystemWide())
    }
    private static func elementPID(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }
    private static var targetEnvironment: InputTargetEnvironment {
        InputTargetEnvironment(frontmostApplication: {
            NSWorkspace.shared.frontmostApplication.map {
                .init(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier, bundleURL: $0.bundleURL)
            }
        }, focused: focused, focusedIn: focused(in:), elementPID: elementPID,
           secureInputActive: { secureInputActive }, isSecureField: isSecureField, value: value,
           selectedRange: selectedRange, selectedText: { attribute($0, kAXSelectedTextAttribute) as? String })
    }
    /// Electron apps enable their accessibility tree lazily; the first query can fail with
    /// kAXErrorCannotComplete. Ask the application element as well and retry once, briefly.
    static func focused(in pid: pid_t) async -> AXUIElement? {
        guard permitted else { return nil }
        for attempt in 0..<2 {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
            for parent in [AXUIElementCreateSystemWide(), AXUIElementCreateApplication(pid)] {
                if let element = focusedElement(of: parent), elementPID(element) == pid {
                    return element
                }
            }
            if attempt == 0 { await uncancellablePause(0.04) }
        }
        return nil
    }
    /// Chromium-based apps (Electron shells and Chromium browsers) acknowledge accessibility writes
    /// without applying them, or apply them late from a cached tree. Keyboard paste is the only safe route.
    static func usesChromiumRuntime(bundleURL: URL?) -> Bool {
        guard let bundleURL else { return false }
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: frameworks.path) else { return false }
        return names.contains { $0.hasPrefix("Electron Framework") || $0.localizedCaseInsensitiveContains("Chrom") }
    }
    static func policy(for target: InputTarget) -> InsertionPolicy {
        .forBundleID(target.bundleID, usesChromium: usesChromiumRuntime(bundleURL: target.bundleURL))
    }
    /// Chromium reports placeholder text and trailing line breaks through AXValue and drops them once
    /// the field is edited (observed in Claude desktop), so a prefix + text + suffix comparison never
    /// matches after a paste there. Paste-only targets are therefore acknowledged by the looser
    /// "changed and contains the text" check; native fields (paste-then-accessibility) keep the exact comparison.
    static func expectsExactValue(policy: InsertionPolicy, sameField: Bool) -> Bool {
        sameField && policy != .pasteOnly
    }
    /// Decides whether a field value proves the text arrived. With a pre-insertion snapshot the value
    /// must match exactly; without one, any readable value that changed and contains the text counts.
    static func acknowledgement(expected: String?, original: String?, text: String) -> (String?) -> Bool {
        { current in
            if let expected { return current == expected }
            guard let current, current != original else { return false }
            return current.contains(text)
        }
    }

    /// Captures the frontmost third-party app and, when available, its focused text element.
    /// A focus change or an element owned by a different app invalidates the entire capture.
    static func capture(allowedContextApps: Set<String>, environment: InputTargetEnvironment? = nil) async -> InputTarget? {
        let environment = environment ?? targetEnvironment
        guard let app = environment.frontmostApplication(),
              app.pid != ProcessInfo.processInfo.processIdentifier,
              app.bundleID != Bundle.main.bundleIdentifier else { return nil }
        func secureTarget() -> InputTarget {
            InputTarget(pid: app.pid, bundleID: app.bundleID, bundleURL: app.bundleURL,
                               element: nil, originalValue: nil, range: nil, selectedText: nil, context: nil, secureField: true)
        }
        guard !environment.secureInputActive() else { return secureTarget() }
        let element = await environment.focusedIn(app.pid)
        func belongsToCapturedApp() -> Bool {
            environment.frontmostApplication() == app &&
                (element.map { environment.elementPID($0) == app.pid } ?? true)
        }
        // Check ownership before reading any field content or applying the app's context allowance.
        guard belongsToCapturedApp() else { return nil }
        guard !environment.secureInputActive(), !(element.map(environment.isSecureField) ?? false) else { return secureTarget() }
        let text = element.flatMap(environment.value)
        let range = element.flatMap(environment.selectedRange)
        let selectedText = element.flatMap(environment.selectedText)
        guard belongsToCapturedApp() else { return nil }
        guard !environment.secureInputActive(), !(element.map(environment.isSecureField) ?? false) else { return secureTarget() }
        var context: String?
        if let bundle = app.bundleID, allowedContextApps.contains(bundle),
           let snapshot = InsertionSnapshot(original: text, range: range) {
            context = String(snapshot.prefix.suffix(1_000))
        }
        return InputTarget(pid: app.pid, bundleID: app.bundleID, bundleURL: app.bundleURL,
                           element: element, originalValue: text, range: range,
                           selectedText: selectedText, context: context)
    }

    static func relation(to target: InputTarget) -> TargetRelation {
        guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else { return .gone }
        guard !secureInputActive else { return .secureInput }
        guard let front = NSWorkspace.shared.frontmostApplication else { return .otherApp }
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier { return .ownApp }
        guard front.processIdentifier == target.pid else { return .otherApp }
        let current = focused()
        if let current, isSecureField(current) { return .secureInput }
        if let current, let element = target.element, elementPID(current) == target.pid,
           elementPID(element) == target.pid, CFEqual(current, element) { return .sameElement }
        // An app that exposes no focused element at all (GPU-rendered editors such as Zed) offers
        // nothing to compare: with the app still in front, nothing observable has changed.
        if current == nil, target.element == nil { return .sameElement }
        return .sameApp
    }

    /// Support diagnostics intentionally exclude text, selection contents, titles, and clipboard data.
    static func diagnosticSummary(target: InputTarget?) -> String {
        let app = NSWorkspace.shared.frontmostApplication
        let secureEventInput = secureInputActive
        let element = secureEventInput ? nil : focused()
        let secureField = element.map { isSecureField($0) } ?? false
        guard !secureEventInput, !secureField else {
            return "trusted=\(permitted), secure=true, app=\(app?.bundleIdentifier ?? "unknown"), role=secure, value=skipped, range=skipped, captured=\(target != nil), snapshot=skipped, relation=secureInput"
        }
        let role = element.flatMap { attribute($0, kAXRoleAttribute) as? String } ?? "unavailable"
        let hasValue = element.map { value($0) != nil } ?? false
        let hasRange = element.map { selectedRange($0) != nil } ?? false
        let snapshotValid = target?.snapshot != nil
        let relationCode = target.map { Self.relation(to: $0).rawValue } ?? "none"
        let policyCode = target.map { Self.policy(for: $0).rawValue } ?? "none"
        return "trusted=\(permitted), secure=false, app=\(app?.bundleIdentifier ?? "unknown"), role=\(role), value=\(hasValue), range=\(hasRange), captured=\(target != nil), element=\(target?.element != nil), snapshot=\(snapshotValid), relation=\(relationCode), policy=\(policyCode)"
    }

    /// True while the captured element is still the focused element of the frontmost app.
    static func isCurrent(_ target: InputTarget, unchanged: Bool = false) -> Bool {
        if unchanged { return targetIsUnchanged(target) }
        guard target.element != nil, relation(to: target) == .sameElement else { return false }
        return true
    }

    /// Rewrite output belongs only to the exact field and selection used to create its request.
    /// Run this again immediately before an AX write or key dispatch, after any clipboard work.
    static func targetIsUnchanged(_ target: InputTarget, environment: InputTargetEnvironment? = nil) -> Bool {
        let environment = environment ?? targetEnvironment
        guard !target.secureField, let element = target.element, let snapshot = target.snapshot else { return false }
        func sameFocusedElement() -> Bool {
            guard !environment.secureInputActive(), environment.frontmostApplication()?.pid == target.pid,
                  environment.elementPID(element) == target.pid, let current = environment.focused(),
                  environment.elementPID(current) == target.pid, CFEqual(current, element),
                  !environment.isSecureField(current) else { return false }
            return true
        }
        guard sameFocusedElement(), environment.value(element) == snapshot.original,
              let range = environment.selectedRange(element),
              range.location == snapshot.range.location, range.length == snapshot.range.length else { return false }
        return sameFocusedElement()
    }

    /// Brings the captured app back to the front when another app (for example one that reacted to
    /// the same global shortcut) took over. Returns true when the target app is frontmost afterwards.
    static func bringToFront(_ target: InputTarget, isCancelled: @escaping @MainActor () -> Bool) async -> Bool {
        let own = ProcessInfo.processInfo.processIdentifier
        func frontmostIsTarget() -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid }
        if frontmostIsTarget() { return true }
        guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else { return false }
        for attempt in 0..<2 {
            if attempt == 0 {
                app.activate(options: [])
            } else if NSWorkspace.shared.frontmostApplication?.processIdentifier == own || NSApp.isActive {
                // macOS 14 cooperative activation: an active app may hand activation to another app.
                app.activate(from: .current, options: [])
            } else {
                NSApp.activate(ignoringOtherApps: true)
                await uncancellablePause(0.05)
                app.activate(from: .current, options: [])
            }
            let started = ProcessInfo.processInfo.systemUptime
            repeat {
                await uncancellablePause(0.05)
                if frontmostIsTarget() { return true }
                if isCancelled() { return false }
            } while ProcessInfo.processInfo.systemUptime - started < 0.5
        }
        return frontmostIsTarget()
    }

    static func insert(_ text: String, at target: InputTarget,
                       requiresUnchangedTarget: Bool = false,
                       isCancelled: @escaping @MainActor () -> Bool = { false },
                       trace: (@MainActor (String) -> Void)? = nil) async -> Bool {
        await insertOutcome(text, at: target, requiresUnchangedTarget: requiresUnchangedTarget,
                            isCancelled: isCancelled, trace: trace).isConfirmed
    }

    static func insertOutcome(_ text: String, at target: InputTarget,
                              requiresUnchangedTarget: Bool = false,
                              isCancelled: @escaping @MainActor () -> Bool = { false },
                              trace: (@MainActor (String) -> Void)? = nil) async -> InsertionOutcome {
        let emit: @MainActor (String) -> Void = { line in
            log.notice("\(line, privacy: .public)")
            trace?(line)
        }
        func blocked(_ reason: InsertionBlockReason) -> InsertionOutcome {
            let outcome = InsertionOutcome.notSubmitted(reason)
            emit(outcome.diagnosticCode)
            return outcome
        }
        let cancelled = { Task.isCancelled || isCancelled() }
        guard !text.isEmpty else { return blocked(.emptyText) }
        guard !pasteInProgress else { return blocked(.busy) }
        guard !cancelled() else { return blocked(.cancelled) }
        // The own-process guard must stay ahead of every environment-dependent check: unit tests use
        // the test process as a stand-in target and rely on this outcome without Accessibility access.
        guard target.pid != ProcessInfo.processInfo.processIdentifier else { return blocked(.noTarget) }
        guard permitted else { return blocked(.permissionMissing) }
        guard !target.secureField, !secureInputActive else { return blocked(.secureInput) }
        guard target.element.map({ elementPID($0) == target.pid }) ?? true else { return blocked(.targetChanged) }
        let snapshot = target.snapshot
        guard !requiresUnchangedTarget || snapshot != nil else { return blocked(.targetChanged) }
        // Without a snapshot only a single keyboard paste is attempted. Rewrite still requires a
        // readable snapshot so its original selection can be checked before any submission.
        var policy = snapshot == nil ? InsertionPolicy.pasteOnly : Self.policy(for: target)
        emit("policy=\(policy.rawValue),snapshot=\(snapshot != nil)")

        // Another app may have taken the front (for example a launcher bound to the same shortcut).
        // Keyboard paste follows focus, so make sure the captured app is in front before dispatching.
        let inFront = await bringToFront(target, isCancelled: isCancelled)
        guard !cancelled() else { return blocked(.cancelled) }
        let relation = Self.relation(to: target)
        emit("front=\(inFront), relation=\(relation.rawValue)")
        guard !requiresUnchangedTarget || targetIsUnchanged(target) else { return blocked(.targetChanged) }
        var pasteElement = target.element
        switch relation {
        case .gone: return blocked(.targetChanged)
        case .secureInput: return blocked(.secureInput)
        case .sameApp:
            // The caret moved inside the app: paste goes to the current field, so verify that one.
            guard let current = focused(), elementPID(current) == target.pid, isTextLike(current) else { return blocked(.targetChanged) }
            pasteElement = current
            policy = .pasteOnly
        case .sameElement:
            // Focus resting on a button or similar (common after a click in Chromium apps) would swallow the paste.
            if let element = target.element, !acceptsKeyboardText(role: attribute(element, kAXRoleAttribute) as? String) {
                return blocked(.noTextField)
            }
        case .otherApp, .ownApp: break
        }
        // Without the target app in front, only a direct accessibility write can reach the captured field.
        guard inFront || (policy == .pasteThenAccessibility && target.element != nil) else { return blocked(.targetChanged) }

        let expected = snapshot?.expectedValue(inserting: text)
        let now = { ProcessInfo.processInfo.systemUptime }
        let axVerification = InsertionVerification(readValue: { target.element.flatMap { value($0) } }, now: now, pause: uncancellablePause)
        let axAcknowledged = acknowledgement(expected: expected, original: target.originalValue, text: text)
        let outcome = await InsertionDelivery.perform(policy: policy, accessibility: {
            guard let element = target.element else { emit("ax.element=missing"); return .unavailableOrRejected }
            var settable = DarwinBoolean(false)
            let queryStatus = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
            emit("ax.settable.status=\(queryStatus.rawValue),allowed=\(settable.boolValue)")
            guard queryStatus == .success, settable.boolValue else { return .unavailableOrRejected }
            guard !cancelled() else { return .blocked(.cancelled) }
            guard !requiresUnchangedTarget || targetIsUnchanged(target) else { return .blocked(.targetChanged) }
            let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            emit("ax.write.status=\(status.rawValue)")
            // A messaging timeout means the write may still be applied later; verify instead of pasting.
            let observed = expected.map { value(element) == $0 } ?? false
            return accessibilitySubmission(status: status, alreadyObserved: observed)
        }, verifyAccessibility: {
            await axVerification.wait(method: .accessibility, isCancelled: cancelled, acknowledged: axAcknowledged)
        }, paste: {
            // Keyboard paste follows the key window: without the app in front, leave the clipboard alone
            // and let the accessibility fallback reach the captured field directly.
            guard inFront else { emit("paste.skipped=notInFront"); return .notSubmitted(.targetChanged) }
            let element = pasteElement
            let original = element.flatMap { value($0) }
            let sameField: Bool = {
                guard let element, let captured = target.element else { return false }
                return CFEqual(element, captured)
            }()
            let verification = InsertionVerification(readValue: { element.flatMap { value($0) } }, now: now, pause: uncancellablePause)
            let exact = expectsExactValue(policy: policy, sameField: sameField) ? expected : nil
            let acknowledged = acknowledgement(expected: exact, original: sameField ? target.originalValue : original, text: text)
            return await paste(text, at: target, verification: verification, acknowledged: acknowledged,
                               requiresUnchangedTarget: requiresUnchangedTarget,
                               isCancelled: cancelled, trace: emit)
        }, isCancelled: cancelled)
        emit(outcome.diagnosticCode)
        return outcome
    }

    static func accessibilitySubmission(status: AXError, alreadyObserved: Bool = false) -> AccessibilitySubmission {
        if alreadyObserved { return .alreadyObserved }
        switch status {
        case .success: return .accepted
        case .attributeUnsupported, .invalidUIElement, .illegalArgument, .apiDisabled, .notImplemented:
            return .unavailableOrRejected
        default:
            // This includes cannotComplete and unknown failures: a second submission is unsafe.
            return .submissionUncertain
        }
    }

    private static func paste(_ text: String, at target: InputTarget,
                              verification: InsertionVerification,
                              acknowledged: (String?) -> Bool,
                              requiresUnchangedTarget: Bool,
                              isCancelled: @escaping @MainActor () -> Bool,
                              trace: @MainActor (String) -> Void) async -> InsertionOutcome {
        // Construct both events before touching the clipboard, so an allocation failure cannot destroy it.
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return .notSubmitted(.eventsUnavailable)
        }
        guard !isCancelled() else { return .notSubmitted(.cancelled) }
        guard !secureInputActive else { return .notSubmitted(.secureInput) }
        guard !requiresUnchangedTarget || targetIsUnchanged(target) else { return .notSubmitted(.targetChanged) }
        let pasteboard = NSPasteboard.general
        let revisionBeforeSnapshot = pasteboard.changeCount
        guard let clipboard = ClipboardTransaction(pasteboard: pasteboard) else {
            let changed = pasteboard.changeCount != revisionBeforeSnapshot
            trace("clipboard.snapshot=\(changed ? "changed" : "unpreservable")")
            return .notSubmitted(changed ? .clipboardChanged : .clipboardUnavailable)
        }
        trace("clipboard.snapshot=ready,skipped=\(clipboard.skippedRepresentations)")
        down.flags = .maskCommand; up.flags = .maskCommand
        pasteInProgress = true
        defer {
            let restored = clipboard.restore()
            trace("clipboard.restore=\(restored)")
            pasteInProgress = false
        }
        guard !isCancelled() else { return .notSubmitted(.cancelled) }
        guard clipboard.install(text) else {
            trace("clipboard.install=failed")
            return .notSubmitted(.clipboardWriteFailed)
        }
        trace("clipboard.install=ready")
        // Snapshotting lazy clipboard representations can take time. Recheck immediately before dispatch.
        guard !isCancelled() else { return .notSubmitted(.cancelled) }
        guard clipboard.ownsContents else { return .notSubmitted(.clipboardChanged) }
        // Keyboard paste follows the key window; an app that is not in front has none, so a posted
        // Cmd-V would be dropped or land somewhere else. Only dispatch while the target is frontmost.
        guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else {
            return .notSubmitted(.targetChanged)
        }
        if secureInputActive || (focused().map { isSecureField($0) } ?? false) { return .notSubmitted(.secureInput) }
        guard !requiresUnchangedTarget || targetIsUnchanged(target) else { return .notSubmitted(.targetChanged) }
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        trace("paste.posted")
        return await verification.wait(method: .paste, isCancelled: isCancelled, acknowledged: acknowledged)
    }

    static func uncancellablePause(_ seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { continuation.resume() }
        }
    }

    static func editedInsertion(original: String, target: InputTarget) -> String? {
        guard isCurrent(target), let element = target.element, let snapshot = target.snapshot,
              let current = value(element), let selection = selectedRange(element) else { return nil }
        return snapshot.editedText(inserting: original, current: current, selection: selection)
    }

    static func observationShouldStop(original: String, target: InputTarget) -> Bool {
        guard isCurrent(target), let element = target.element, let snapshot = target.snapshot,
              let current = value(element), let selection = selectedRange(element) else { return true }
        return !snapshot.observationIsBounded(inserting: original, current: current, selection: selection)
    }
}

/// Best-effort compare-and-restore: NSPasteboard has no cross-process atomic compare-and-swap API.
/// All local mutation steps are synchronous on MainActor and newer external copies always take priority.
/// Secondary representations that cannot be read (promised or owner-provided data) or exceed the size
/// budget are skipped, but an item that would lose every representation refuses the transaction: the
/// user's clipboard is never replaced by nothing.
@MainActor
final class ClipboardTransaction {
    private static let ownerType = NSPasteboard.PasteboardType("app.opennotype.clipboard-transaction")
    private static let maximumSnapshotBytes = 32_000_000
    private let pasteboard: NSPasteboard
    private let saved: [NSPasteboardItem]
    private let initialChangeCount: Int
    private let token = UUID().uuidString
    private var ownedChangeCount: Int?
    private var requiresToken = false
    /// Number of secondary representations that could not be preserved for restoration.
    let skippedRepresentations: Int

    init?(pasteboard: NSPasteboard) {
        let initial = pasteboard.changeCount
        guard let items = pasteboard.pasteboardItems else {
            // A truly empty pasteboard is safe; an unreadable populated one must remain untouched.
            guard pasteboard.types?.isEmpty != false else { return nil }
            self.pasteboard = pasteboard; saved = []; initialChangeCount = initial; skippedRepresentations = 0
            return
        }
        var snapshot: [NSPasteboardItem] = []
        var byteCount = 0
        var skipped = 0
        for item in items {
            let copy = NSPasteboardItem()
            var copiedAny = false
            for type in item.types {
                guard let data = item.data(forType: type), byteCount + data.count <= Self.maximumSnapshotBytes,
                      copy.setData(data, forType: type) else { skipped += 1; continue }
                byteCount += data.count
                copiedAny = true
            }
            // Nothing of this item could be kept: refuse rather than restore an emptier clipboard.
            guard copiedAny || item.types.isEmpty else { return nil }
            if copiedAny { snapshot.append(copy) }
        }
        // A copy that raced with the snapshot must not be replaced by a stale restoration.
        guard pasteboard.changeCount == initial else { return nil }
        self.pasteboard = pasteboard; saved = snapshot; initialChangeCount = initial
        skippedRepresentations = skipped
    }

    var ownsContents: Bool {
        guard let revision = ownedChangeCount, pasteboard.changeCount == revision else { return false }
        if requiresToken, pasteboard.string(forType: Self.ownerType) != token { return false }
        return pasteboard.changeCount == revision
    }

    func install(_ text: String) -> Bool {
        guard ownedChangeCount == nil, pasteboard.changeCount == initialChangeCount else { return false }
        let item = NSPasteboardItem()
        // nspasteboard.org markers: clipboard managers skip transient/concealed items, so the dictated
        // text does not end up in their history while it passes through the clipboard.
        guard item.setString(text, forType: .string), item.setString(token, forType: Self.ownerType),
              item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType")),
              item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) else { return false }
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
