import AppKit
import SwiftUI
import OpenNoTypeCore

struct VoiceBarSavedPosition: Codable, Equatable {
    var xCenterRatio: Double
    var bottomOffset: Double
}

/// Pure, testable geometry and per-display position helper for the floating HUD.
enum VoiceBarLayout {
    static let margin: CGFloat = 12
    static let defaultBottomOffset: CGFloat = 28

    static func panelSize(
        isBusy: Bool,
        hasWarning: Bool,
        hasPreview: Bool,
        transientMessage: String?,
        offersResultCopy: Bool,
        isTranslationMode: Bool
    ) -> NSSize {
        if !isBusy, let message = transientMessage {
            if offersResultCopy {
                return NSSize(width: 448, height: 80)
            }
            let isLong = message.count > 34
            return NSSize(width: isLong ? 404 : 324, height: isLong ? 68 : 60)
        }
        if hasWarning || hasPreview {
            let warningHeight: CGFloat = hasWarning ? 52 : 0
            let previewHeight: CGFloat = hasPreview ? 68 : 0
            return NSSize(width: 444, height: 60 + warningHeight + previewHeight)
        }
        let width: CGFloat = isTranslationMode ? 412 : 376
        return NSSize(width: width, height: 60)
    }

    static func resolveOrigin(
        panelSize: NSSize,
        visibleFrame: NSRect,
        saved: VoiceBarSavedPosition?
    ) -> NSPoint {
        let rawX: CGFloat
        let rawY: CGFloat
        if let saved {
            rawX = visibleFrame.minX + visibleFrame.width * saved.xCenterRatio - panelSize.width / 2
            rawY = visibleFrame.minY + saved.bottomOffset
        } else {
            rawX = visibleFrame.midX - panelSize.width / 2
            rawY = visibleFrame.minY + defaultBottomOffset
        }
        return clamp(origin: NSPoint(x: rawX, y: rawY), panelSize: panelSize, visibleFrame: visibleFrame)
    }

    static func anchorResize(
        currentFrame: NSRect,
        newSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        let rawX = currentFrame.midX - newSize.width / 2
        let rawY = currentFrame.minY
        return clamp(origin: NSPoint(x: rawX, y: rawY), panelSize: newSize, visibleFrame: visibleFrame)
    }

    static func clamp(origin: NSPoint, panelSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - panelSize.width - margin)
        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - panelSize.height - margin)
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    static func savedPosition(for frame: NSRect, in visibleFrame: NSRect) -> VoiceBarSavedPosition {
        let ratio = visibleFrame.width > 0 ? Double((frame.midX - visibleFrame.minX) / visibleFrame.width) : 0.5
        let clampedRatio = min(max(ratio, 0.05), 0.95)
        let bottomOffset = max(Double(margin), Double(frame.minY - visibleFrame.minY))
        return VoiceBarSavedPosition(xCenterRatio: clampedRatio, bottomOffset: bottomOffset)
    }
}

@MainActor
final class VoiceBarPositionStore {
    private let defaults: UserDefaults
    private let storageKey = "voicebar.positions.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func position(for displayKey: String) -> VoiceBarSavedPosition? {
        allPositions()[displayKey]
    }

    func save(_ position: VoiceBarSavedPosition, for displayKey: String) {
        var stored = allPositions()
        stored[displayKey] = position
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: storageKey)
        }
    }

    func clear(for displayKey: String) {
        var stored = allPositions()
        stored.removeValue(forKey: displayKey)
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func allPositions() -> [String: VoiceBarSavedPosition] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: VoiceBarSavedPosition].self, from: data) else {
            return [:]
        }
        return decoded
    }
}

@MainActor
final class VoiceBarController {
    private let panel: NSPanel
    private let positionStore = VoiceBarPositionStore()
    private var moveObserver: NSObjectProtocol?
    private var isProgrammaticMove = false
    private var activeDisplayKey: String?

    init(model: AppModel) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 376, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: VoiceBar(model: model, onResetPosition: { [weak self] in
            self?.resetCurrentDisplayPosition()
        }))

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordManualMove() }
        }

        model.onPhaseChange = { [weak self, weak model] in
            guard let self, let model else { return }
            self.updatePresentation(for: model)
        }
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
    }

    private func updatePresentation(for model: AppModel) {
        let shouldShow = model.phase != .idle || model.transientMessage != nil
        guard shouldShow else {
            panel.orderOut(nil)
            return
        }

        let hasWarning = model.isBusy && model.transientMessage != nil
        let hasPreview = model.isLocalPreviewActive
        let offersCopy = !model.isBusy && model.transientOffersResultCopy && model.copyableLatestResult != nil
        let size = VoiceBarLayout.panelSize(
            isBusy: model.isBusy,
            hasWarning: hasWarning,
            hasPreview: hasPreview,
            transientMessage: model.transientMessage,
            offersResultCopy: offersCopy,
            isTranslationMode: model.voiceBarModeKind == .translation
        )

        let wasVisible = panel.isVisible
        let screen = wasVisible
            ? (panel.screen ?? preferredScreen())
            : preferredScreen()

        isProgrammaticMove = true
        defer { isProgrammaticMove = false }

        if let screen {
            let key = displayKey(for: screen)
            activeDisplayKey = key
            let origin: NSPoint
            if wasVisible {
                origin = VoiceBarLayout.anchorResize(
                    currentFrame: panel.frame,
                    newSize: size,
                    visibleFrame: screen.visibleFrame
                )
            } else {
                let saved = positionStore.position(for: key)
                origin = VoiceBarLayout.resolveOrigin(
                    panelSize: size,
                    visibleFrame: screen.visibleFrame,
                    saved: saved
                )
            }
            panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        } else {
            panel.setContentSize(size)
        }
        panel.orderFrontRegardless()
    }

    private func recordManualMove() {
        guard !isProgrammaticMove, panel.isVisible, let screen = panel.screen else { return }
        let key = displayKey(for: screen)
        activeDisplayKey = key
        let saved = VoiceBarLayout.savedPosition(for: panel.frame, in: screen.visibleFrame)
        positionStore.save(saved, for: key)
    }

    private func resetCurrentDisplayPosition() {
        guard let screen = panel.screen ?? preferredScreen() else { return }
        let key = displayKey(for: screen)
        positionStore.clear(for: key)
        isProgrammaticMove = true
        defer { isProgrammaticMove = false }
        let origin = VoiceBarLayout.resolveOrigin(
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame,
            saved: nil
        )
        panel.setFrameOrigin(origin)
    }

    private func preferredScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func displayKey(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        let frame = screen.frame
        return "display-\(Int(frame.width))x\(Int(frame.height))"
    }
}

private struct VisualEffectBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

private struct VoiceBar: View {
    @Bindable var model: AppModel
    var onResetPosition: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copiedResult = false
    @State private var cancelHovered = false
    @State private var stopHovered = false
    @State private var copyHovered = false
    @State private var openHovered = false

    private var isExpanded: Bool {
        (model.isBusy && (model.transientMessage != nil || model.isLocalPreviewActive))
            || (!model.isBusy && model.transientOffersResultCopy && model.copyableLatestResult != nil)
    }

    private var cornerRadius: CGFloat {
        isExpanded ? 16 : 26
    }

    private var modeAccent: Color {
        switch model.voiceBarModeKind {
        case .dictation: Color(red: 0.45, green: 0.85, blue: 0.68)
        case .quickLocal: Color(red: 0.36, green: 0.88, blue: 0.78)
        case .translation: Color(red: 0.96, green: 0.74, blue: 0.42)
        case .rewrite: Color(red: 0.50, green: 0.76, blue: 0.98)
        case .prompt: Color(red: 0.76, green: 0.65, blue: 0.98)
        case .enrolling: Color(red: 0.45, green: 0.85, blue: 0.68)
        }
    }

    private var borderTint: Color {
        if !model.isBusy, model.transientMessage != nil {
            switch model.transientSeverity {
            case .success: return Color(red: 0.45, green: 0.85, blue: 0.68).opacity(0.45)
            case .info: return .white.opacity(0.18)
            case .warning: return Color(red: 0.96, green: 0.68, blue: 0.32).opacity(0.50)
            }
        }
        if model.countdown != nil || (model.isBusy && model.transientMessage != nil) {
            return Color(red: 0.96, green: 0.68, blue: 0.32).opacity(0.45)
        }
        return .white.opacity(0.16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.isBusy, let message = model.transientMessage {
                outcomeToast(message)
            } else {
                activeRow
                if let message = model.transientMessage {
                    Divider().overlay(.white.opacity(0.10))
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.34))
                            .padding(.top, 1)
                        Text(message)
                            .font(AppTypography.caption)
                            .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.48))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel(message)
                }
            }
            if model.isLocalPreviewActive {
                Divider().overlay(.white.opacity(0.10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("미리보기 · 확정 결과 아님", "Preview · Not the final result"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                    Text(model.localPreviewText.isEmpty
                         ? L("최근 발화 미리보기 준비 중…", "Preparing recent speech preview…")
                         : model.localPreviewText)
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(L("최근 발화 미리보기, 확정 결과 아님", "Recent speech preview, not the final result"))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background {
            ZStack {
                VisualEffectBackdrop()
                Color(red: 0.08, green: 0.10, blue: 0.12).opacity(0.76)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderTint, lineWidth: 1)
        )
        .padding(3)
        .onTapGesture(count: 2) { onResetPosition() }
        .onChange(of: model.copyableLatestResult) { _, _ in copiedResult = false }
        .onChange(of: model.transientMessage) { _, _ in copiedResult = false }
    }

    private func outcomeToast(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: severityIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(severityColor)
            Text(message)
                .font(AppTypography.body)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.transientOffersResultCopy, let copyable = model.copyableLatestResult {
                HStack(spacing: 6) {
                    Button {
                        NSPasteboard.general.clearContents()
                        copiedResult = NSPasteboard.general.setString(copyable, forType: .string)
                    } label: {
                        Label(copiedResult ? L("복사됨", "Copied") : L("복사", "Copy"),
                              systemImage: copiedResult ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(
                                (copiedResult ? Color(red: 0.45, green: 0.85, blue: 0.68).opacity(0.26)
                                 : .white.opacity(copyHovered ? 0.24 : 0.16)),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { copyHovered = $0 }
                    .accessibilityLabel(L("결과 복사", "Copy result"))

                    Button {
                        model.page = .home
                        model.showManager?()
                    } label: {
                        Text(L("열기", "Open"))
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(.white.opacity(openHovered ? 0.18 : 0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .onHover { openHovered = $0 }
                    .accessibilityLabel(L("OpenNoType 창 열기", "Open OpenNoType"))
                }
            }
        }
        .frame(minHeight: 30)
    }

    private var severityIcon: String {
        switch model.transientSeverity {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private var severityColor: Color {
        switch model.transientSeverity {
        case .success: Color(red: 0.45, green: 0.85, blue: 0.68)
        case .info: Color(red: 0.56, green: 0.78, blue: 0.98)
        case .warning: Color(red: 0.98, green: 0.72, blue: 0.34)
        }
    }

    private var activeRow: some View {
        HStack(spacing: 10) {
            Button(action: model.cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(cancelHovered ? 1.0 : 0.72))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(cancelHovered ? 0.18 : 0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .onHover { cancelHovered = $0 }
            .help(L("취소", "Cancel"))
            .accessibilityLabel(L("녹음 또는 처리 취소", "Cancel recording or processing"))

            modeBadge

            if model.phase == .starting || model.phase == .processing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text(model.status)
                        .font(AppTypography.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else {
                waveformMeter
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    if let seconds = model.countdown {
                        Text(L("\(seconds)초 남음", "\(seconds)s left"))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.34))
                    } else {
                        Text(String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
                .accessibilityLabel(model.status)
            }

            if model.isRecording {
                Button(action: model.stop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                        .frame(width: 30, height: 30)
                        .background(modeAccent.opacity(stopHovered ? 1.0 : 0.90), in: Circle())
                }
                .buttonStyle(.plain)
                .onHover { stopHovered = $0 }
                .help(L("녹음 종료 후 처리", "Finish recording and process"))
                .accessibilityLabel(L("녹음 종료 후 처리", "Finish recording and process"))
            }
        }
        .frame(height: 34)
    }

    private var modeBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: model.voiceBarModeIcon)
                .font(.system(size: 10, weight: .semibold))
            Text(model.voiceBarModeLabel)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(modeAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(modeAccent.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(modeAccent.opacity(0.28), lineWidth: 0.75))
    }

    private var waveformMeter: some View {
        let samples = model.levelHistory
        let count = samples.count
        return HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { index in
                let normalizedIndex = count > 1 ? Double(index) / Double(count - 1) : 0.5
                // Gentle bell envelope gives an organic studio-meter silhouette.
                let envelope = 0.55 + 0.45 * sin(normalizedIndex * .pi)
                let sample = max(0.0, min(1.0, samples[index]))
                let barHeight = 4.0 + sample * 22.0 * envelope
                Capsule()
                    .fill(modeAccent.opacity(0.42 + sample * 0.58))
                    .frame(width: 2.5, height: barHeight)
            }
        }
        .frame(height: 28)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: samples)
        .accessibilityHidden(true)
    }
}
