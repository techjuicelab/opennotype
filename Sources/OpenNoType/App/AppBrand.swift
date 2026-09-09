import AppKit

@MainActor
enum AppBrand {
    static let icon: NSImage = {
        // Packaged apps keep the icon in Contents/Resources. Do not rely on SwiftPM's
        // absolute .build fallback, which is unavailable on another Mac.
        let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        guard let url, let image = NSImage(contentsOf: url) else {
            preconditionFailure("OpenNoType AppIcon.icns is missing from the app resources.")
        }
        return image
    }()

    private static let idleMenuBarImage = makeMenuBarImage(isRecording: false)
    private static let recordingMenuBarImage = makeMenuBarImage(isRecording: true)

    static func menuBarImage(isRecording: Bool) -> NSImage {
        isRecording ? recordingMenuBarImage : idleMenuBarImage
    }

    private static func makeMenuBarImage(isRecording: Bool) -> NSImage {
        // The three voice bars and cradle match the symbol on the selected keycap.
        // Draw a vector template so macOS can adapt it to menu bar contrast and scale.
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            for rect in [
                NSRect(x: 3.5, y: 8, width: 2.5, height: 5.5),
                NSRect(x: 7.25, y: 6.5, width: 2.5, height: 9.5),
                NSRect(x: 11, y: 8, width: 2.5, height: 5.5)
            ] {
                NSBezierPath(roundedRect: rect, xRadius: 1.25, yRadius: 1.25).fill()
            }
            let cradle = NSBezierPath()
            cradle.lineWidth = 2
            cradle.lineCapStyle = .round
            cradle.move(to: NSPoint(x: 2.5, y: 7.5))
            cradle.curve(to: NSPoint(x: 8.5, y: 3.5),
                         controlPoint1: NSPoint(x: 3, y: 5),
                         controlPoint2: NSPoint(x: 5.5, y: 3.5))
            cradle.curve(to: NSPoint(x: 14.5, y: 7.5),
                         controlPoint1: NSPoint(x: 11.5, y: 3.5),
                         controlPoint2: NSPoint(x: 14, y: 5))
            cradle.move(to: NSPoint(x: 8.5, y: 3.5))
            cradle.line(to: NSPoint(x: 8.5, y: 1.5))
            cradle.stroke()
            if isRecording {
                NSBezierPath(ovalIn: NSRect(x: 17.5, y: 12.5, width: 3.5, height: 3.5)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = isRecording ? "OpenNoType — 녹음 중" : "OpenNoType"
        return image
    }
}
