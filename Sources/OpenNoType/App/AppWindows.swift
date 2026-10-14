import AppKit
import SwiftUI

/// Keep the first SwiftUI window off screen while retaining its scene and reopen action.
@MainActor
final class AppWindows {
    private(set) weak var window: NSWindow?
    private let isPreview: Bool
    private let hasSurface: @MainActor (NSWindow) -> Bool
    private let schedule: @MainActor (@escaping @MainActor () -> Void) -> Void
    private let activate: @MainActor () -> Void
    private var handledInitialWindow = false
    private var suppressInitialWindow = true
    private var openWindow: (() -> Void)?

    init(isPreview: Bool? = nil,
         hasSurface: (@MainActor (NSWindow) -> Bool)? = nil,
         schedule: (@MainActor (@escaping @MainActor () -> Void) -> Void)? = nil,
         activate: (@MainActor () -> Void)? = nil) {
        self.isPreview = isPreview ?? AppLaunch.isPreview
        self.hasSurface = hasSurface ?? Self.hasSurface
        self.schedule = schedule ?? { action in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { action() }
        }
        self.activate = activate ?? { NSApp?.activate(ignoringOtherApps: true) }
    }

    static func isMainWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel) else { return false }
        if let identifier = window.identifier { return identifier.rawValue == "main" }
        return window.canBecomeMain && window.level == .normal
    }

    func connectWindowOpening(_ open: @escaping () -> Void) { openWindow = open }

    /// The accessor runs before the first visible frame, including a restored login window.
    func attach(_ window: NSWindow) {
        guard Self.isMainWindow(window) else { return }
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
        window?.alphaValue = 1
        openWindow?()
        window?.makeKeyAndOrderFront(nil)
        activate()
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

    func makeNSView(context: Context) -> WindowAccessorView { WindowAccessorView(windows: windows) }
    func updateNSView(_ view: WindowAccessorView, context: Context) { }

    final class WindowAccessorView: NSView {
        let windows: AppWindows
        init(windows: AppWindows) {
            self.windows = windows
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { windows.attach(window) }
        }
    }
}
