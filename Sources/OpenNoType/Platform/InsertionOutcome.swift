import Foundation

enum InsertionMethod: String, Equatable {
    case accessibility, paste
}

enum InsertionPolicy: String, Equatable {
    /// Keyboard paste first. A direct accessibility write is tried only when the paste route itself is
    /// unavailable: the clipboard cannot be preserved, key events cannot be built, or the app is not in
    /// front. Keyboard paste reaches every app that accepts typing, whereas accessibility writes are
    /// silently ignored by many editors (Electron, terminals, GPU-rendered and custom text views) and
    /// nothing visible happens after a "successful" write there.
    case pasteThenAccessibility
    /// Keyboard paste only: the app is known to acknowledge accessibility writes without applying them,
    /// or to apply them late from a cached tree, so a fallback write could duplicate the text.
    case pasteOnly

    /// Apps where an accessibility text write reports success but leaves the visible editor unchanged
    /// or applies it late from a cached tree (Electron/Chromium editors and browsers, GPU-rendered
    /// terminals). Reproduced in Antigravity and Claude desktop; reported for Codex; the terminal and
    /// messenger entries come from the reference app's field notes. Unknown Chromium-based apps are
    /// detected separately by `TextInsertion.usesChromiumRuntime`.
    static let pasteOnlyBundleIDs: Set<String> = [
        "com.google.antigravity", "com.openai.codex",
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "org.alacritty", "net.kovidgoyal.kitty", "com.github.wez.wezterm",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord",
        "com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium", "com.brave.Browser",
        "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"
    ]

    static func forBundleID(_ bundleID: String?, usesChromium: Bool = false) -> Self {
        if let bundleID, pasteOnlyBundleIDs.contains(bundleID) { return .pasteOnly }
        return usesChromium ? .pasteOnly : .pasteThenAccessibility
    }
}

enum InsertionBlockReason: String, Equatable, CaseIterable {
    case emptyText, busy, cancelled
    /// No other app was captured, or the captured process is this app itself.
    case noTarget
    /// Keyboard focus rests on a control that never takes text (a button, a link, a menu), so a paste
    /// would vanish without a trace.
    case noTextField
    /// Accessibility access is not granted, so neither AX writes nor synthesized key events can reach any app.
    case permissionMissing
    /// The captured app could not be brought back to the front, or it has quit.
    case targetChanged
    /// Secure keyboard entry is active or a password field is focused.
    case secureInput
    case eventsUnavailable, clipboardUnavailable, clipboardChanged, clipboardWriteFailed

    /// The paste route was unavailable but nothing was dispatched, so a direct accessibility write may
    /// still deliver the text without any risk of a duplicate.
    var allowsAccessibilityFallback: Bool {
        switch self {
        case .targetChanged, .eventsUnavailable, .clipboardUnavailable, .clipboardChanged, .clipboardWriteFailed: true
        case .emptyText, .busy, .cancelled, .noTarget, .noTextField, .permissionMissing, .secureInput: false
        }
    }
}

enum InsertionVerificationFailure: String, Equatable {
    case timedOut, cancelled
}

enum InsertionOutcome: Equatable {
    /// No successful AX submission or keyboard paste dispatch took place.
    case notSubmitted(InsertionBlockReason)
    case confirmed(InsertionMethod)
    /// A submitted edit may still arrive; this outcome must not trigger an automatic retry.
    case submittedUnverified(InsertionMethod, InsertionVerificationFailure)

    var isConfirmed: Bool {
        if case .confirmed = self { return true }
        return false
    }

    /// The text was handed to the target app; only the acknowledgement is missing.
    var wasSubmitted: Bool {
        if case .notSubmitted = self { return false }
        return true
    }

    /// Contains only fixed diagnostic codes, never user text or clipboard representations.
    var diagnosticCode: String {
        switch self {
        case .notSubmitted(let reason): "notSubmitted.\(reason.rawValue)"
        case .confirmed(let method): "confirmed.\(method.rawValue)"
        case .submittedUnverified(let method, let reason): "submittedUnverified.\(method.rawValue).\(reason.rawValue)"
        }
    }
}

enum AccessibilitySubmission: Equatable {
    case blocked(InsertionBlockReason)
    case accepted
    /// The messaging call did not acknowledge the write; it may still arrive later.
    case submissionUncertain
    case alreadyObserved
    case unavailableOrRejected
}

/// Paste is the primary route for every app. A posted paste is final: an unverified paste must never
/// be followed by an accessibility write, and once an AX write was accepted or may have reached the
/// app, only observation is safe. An unchanged field at the deadline cannot prove that a queued edit
/// will never arrive.
@MainActor
enum InsertionDelivery {
    static func perform(policy: InsertionPolicy = .pasteThenAccessibility,
                        accessibility: () -> AccessibilitySubmission,
                        verifyAccessibility: () async -> InsertionOutcome,
                        paste: () async -> InsertionOutcome,
                        isCancelled: () -> Bool) async -> InsertionOutcome {
        // The shared focus/cancellation checks and paste safeguards remain in the caller.
        let pasted = await paste()
        guard policy == .pasteThenAccessibility, case .notSubmitted(let reason) = pasted,
              reason.allowsAccessibilityFallback else { return pasted }
        switch accessibility() {
        case .blocked(let reason): return .notSubmitted(reason)
        case .accepted, .submissionUncertain:
            return await verifyAccessibility()
        case .alreadyObserved:
            return isCancelled() ? .submittedUnverified(.accessibility, .cancelled) : .confirmed(.accessibility)
        case .unavailableOrRejected:
            // The field takes neither route: the paste failure is the actionable explanation.
            return pasted
        }
    }
}

/// Read-only observation and time are injectable so delayed/missing acknowledgements need no AX access.
@MainActor
struct InsertionVerification {
    var readValue: () -> String?
    var now: () -> TimeInterval
    var pause: (TimeInterval) async -> Void

    func wait(for expected: String, method: InsertionMethod,
              isCancelled: () -> Bool) async -> InsertionOutcome {
        await wait(method: method, isCancelled: isCancelled) { $0 == expected }
    }

    /// `acknowledged` receives the current field value (nil when unreadable) and decides whether the
    /// edit is visible. Callers without a pre-insertion snapshot pass a looser predicate.
    func wait(method: InsertionMethod, isCancelled: () -> Bool,
              acknowledged: (String?) -> Bool) async -> InsertionOutcome {
        let started = now()
        if method == .accessibility {
            repeat {
                if acknowledged(readValue()) {
                    return isCancelled() ? .submittedUnverified(method, .cancelled) : .confirmed(method)
                }
                if isCancelled() { return .submittedUnverified(method, .cancelled) }
                await pause(0.05)
            } while now() - started < 1.0
            if isCancelled() { return .submittedUnverified(method, .cancelled) }
            return acknowledged(readValue()) ? .confirmed(method) : .submittedUnverified(method, .timedOut)
        }

        // A posted Cmd-V cannot be recalled. Preserve the clipboard lease across cancellation,
        // until the exact edit is visible (at least 0.2 seconds) or three seconds elapse.
        var seen = false
        repeat {
            await pause(0.05)
            if acknowledged(readValue()) { seen = true }
            let elapsed = now() - started
            if seen && elapsed >= 0.2 { break }
            if elapsed >= 3.0 { break }
        } while true
        if isCancelled() { return .submittedUnverified(method, .cancelled) }
        return seen ? .confirmed(method) : .submittedUnverified(method, .timedOut)
    }
}
