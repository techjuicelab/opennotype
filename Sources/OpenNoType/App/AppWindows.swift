import AppKit
import SwiftUI

/// Keep the first SwiftUI window off screen while retaining its scene and reopen action,
/// and fall back to an AppKit-hosted manager window when macOS login-item launch skips
/// instantiating the SwiftUI Window scene.
@MainActor
final class AppWindows {
    private(set) weak var window: NSWindow?
    private var fallbackWindow: NSWindow?
    private let isPreview: Bool
    private let hasSurface: @MainActor (NSWindow) -> Bool
    private let schedule: @MainActor (@escaping @MainActor () -> Void) -> Void
    private let activate: @MainActor () -> Void
    private let existingWindows: @MainActor () -> [NSWindow]
    private var handledInitialWindow = false
    private var suppressInitialWindow = true
    private var openWindow: (() -> Void)?
    private var makeFallbackWindow: (@MainActor () -> NSWindow)?
    private var showGeneration = 0

    init(isPreview: Bool? = nil,
         hasSurface: (@MainActor (NSWindow) -> Bool)? = nil,
         schedule: (@MainActor (@escaping @MainActor () -> Void) -> Void)? = nil,
         activate: (@MainActor () -> Void)? = nil,
         existingWindows: (@MainActor () -> [NSWindow])? = nil) {
        self.isPreview = isPreview ?? AppLaunch.isPreview
        self.hasSurface = hasSurface ?? Self.hasSurface
        self.schedule = schedule ?? { action in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { action() }
        }
        self.activate = activate ?? {
            NSApp?.unhide(nil)
            NSApp?.activate(ignoringOtherApps: true)
        }
        self.existingWindows = existingWindows ?? {
            NSApp?.isRunning == true ? (NSApp?.windows ?? []) : []
        }
    }

    static func isMainWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel) else { return false }
        if let identifier = window.identifier { return identifier.rawValue == "main" }
        return window.canBecomeMain && window.level == .normal
    }

    func connectWindowOpening(_ open: @escaping () -> Void) { openWindow = open }

    func connectFallbackWindowFactory(_ factory: @escaping @MainActor () -> NSWindow) {
        makeFallbackWindow = factory
    }

    /// Lets the first-ever launch show the setup manager once while returning launches stay menu-bar quiet.
    @discardableResult
    func allowInitialWindowForFreshInstall(
        isFreshInstall: Bool = true,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let markerKey = "app.didShowInitialManager.v1"
        guard isFreshInstall, !defaults.bool(forKey: markerKey) else { return false }
        defaults.set(true, forKey: markerKey)
        suppressInitialWindow = false
        return true
    }

    /// The accessor runs before the first visible frame, including a restored login window.
    func attach(_ window: NSWindow) {
        guard Self.isMainWindow(window) else { return }
        if let fallbackWindow, fallbackWindow !== window {
            // A fallback manager window is already owned; suppress any duplicate SwiftUI window.
            window.isRestorable = false
            window.close()
            return
        }
        self.window = window
        guard !isPreview else { return }
        window.isRestorable = false
        guard !handledInitialWindow else { return }
        handledInitialWindow = true
        guard suppressInitialWindow else { return }
        window.alphaValue = 0
        orderOutAfterFirstFrame(window)
    }

    func show() {
        // An explicit open wins even if the first frame is still being prepared.
        suppressInitialWindow = false
        showGeneration += 1
        let generation = showGeneration

        if window == nil, let existing = findExistingMainWindow() {
            attach(existing)
        }

        if let existing = window {
            openWindow?()
            present(existing)
            return
        }

        if let openWindow {
            openWindow()
            if window == nil, let existing = findExistingMainWindow() {
                attach(existing)
            }
            if let existing = window {
                present(existing)
                return
            }
            // SwiftUI may materialize its Window asynchronously on a later runloop turn;
            // fall back to an AppKit-owned window if SwiftUI still does not produce one.
            activate()
            ensureWindowAfterOpenRequest(generation: generation, attempt: 0)
            return
        }

        // macOS login-item launch of an LSUIElement app can skip creating the SwiftUI Window scene,
        // leaving both window and openWindow nil. Materialize a retained AppKit manager window directly.
        if let fallback = createFallbackWindow() {
            present(fallback)
        } else {
            activate()
        }
    }

    private func findExistingMainWindow() -> NSWindow? {
        if let fallbackWindow { return fallbackWindow }
        return existingWindows().first { Self.isMainWindow($0) }
    }

    private func createFallbackWindow() -> NSWindow? {
        if let fallbackWindow {
            self.window = fallbackWindow
            return fallbackWindow
        }
        guard let created = makeFallbackWindow?() else { return nil }
        created.isRestorable = false
        created.isReleasedWhenClosed = false
        fallbackWindow = created
        self.window = created
        handledInitialWindow = true
        return created
    }

    private func present(_ window: NSWindow) {
        window.alphaValue = 1
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if !window.collectionBehavior.contains(.canJoinAllSpaces) {
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
        activate()
        window.makeKeyAndOrderFront(nil)
        if NSApp?.isRunning == true {
            window.orderFrontRegardless()
        }
    }

    private func ensureWindowAfterOpenRequest(generation: Int, attempt: Int) {
        guard showGeneration == generation else { return }
        if window == nil, let existing = findExistingMainWindow() {
            attach(existing)
        }
        if let existing = window {
            present(existing)
            return
        }
        guard attempt < 10 else {
            if let fallback = createFallbackWindow() {
                present(fallback)
            }
            return
        }
        schedule { [weak self] in
            guard let self else { return }
            self.ensureWindowAfterOpenRequest(generation: generation, attempt: attempt + 1)
        }
    }

    private func orderOutAfterFirstFrame(_ window: NSWindow, attempt: Int = 0) {
        guard suppressInitialWindow else { return }
        guard hasSurface(window) else {
            guard attempt < 60 else {
                // Do not strand an invisible window if WindowServer never creates its surface.
                window.alphaValue = 1
                return
            }
            schedule { [weak self, weak window] in
                guard let self, let window else { return }
                self.orderOutAfterFirstFrame(window, attempt: attempt + 1)
            }
            return
        }
        // Ordering out before the first composite can leave later opens with a 0x0 surface.
        // Restore alpha while ordered in so a subsequent explicit open draws normally.
        window.alphaValue = 1
        window.orderOut(nil)
    }

    private static func hasSurface(_ window: NSWindow) -> Bool {
        guard window.windowNumber > 0,
              let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]],
              let bounds = list.first?[kCGWindowBounds as String] as? [String: Any] else { return false }
        return (bounds["Width"] as? Double ?? 0) > 0 && (bounds["Height"] as? Double ?? 0) > 0
    }
}

struct ManagerWindowAccessor: NSViewRepresentable {
    let windows: AppWindows
    var appearanceName: String = "system"

    func makeNSView(context: Context) -> WindowAccessorView {
        WindowAccessorView(windows: windows, appearanceName: appearanceName)
    }

    func updateNSView(_ view: WindowAccessorView, context: Context) {
        view.applyAppearance(appearanceName)
    }

    final class WindowAccessorView: NSView {
        let windows: AppWindows
        private var appearanceName: String

        init(windows: AppWindows, appearanceName: String) {
            self.windows = windows
            self.appearanceName = appearanceName
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                windows.attach(window)
                applyAppearance(appearanceName)
            }
        }

        func applyAppearance(_ name: String) {
            appearanceName = name
            guard let window else { return }
            switch name {
            case "dark":
                window.appearance = NSAppearance(named: .darkAqua)
            case "light":
                window.appearance = NSAppearance(named: .aqua)
            default:
                window.appearance = nil
            }
        }
    }
}
