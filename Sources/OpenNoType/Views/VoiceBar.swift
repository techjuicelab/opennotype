import AppKit
import SwiftUI

@MainActor
final class VoiceBarController {
    private let panel: NSPanel
    init(model: AppModel) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 450, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: VoiceBar(model: model))
        model.onPhaseChange = { [weak self, weak model] in
            guard let self, let model else { return }
            if model.isBusy || model.transientMessage != nil {
                if let screen = NSScreen.main {
                    self.panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 225, y: screen.visibleFrame.minY + 34))
                }
                self.panel.orderFrontRegardless()
            } else { self.panel.orderOut(nil) }
        }
    }
}

private struct VoiceBar: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 16) {
            if !model.isBusy, let message = model.transientMessage {
                // Outcome summary after work ended: no buttons, no level meter, never a window.
                Image(systemName: "info.circle").font(.system(size: 16, weight: .medium))
                Text(message).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
            Button(action: model.cancel) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 30) }
                .buttonStyle(.plain).accessibilityLabel("녹음 또는 처리 취소")
            if model.phase == .processing { ProgressView().controlSize(.small).tint(.white) }
            else {
                HStack(spacing: 3) {
                    ForEach(0..<11, id: \.self) { index in
                        Capsule().fill(Color.white.opacity(0.9))
                            .frame(width: 3, height: 5 + model.level * Double(12 + (index * 7 % 21)))
                    }
                }.frame(width: 66, height: 36)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: model.level)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(model.status).font(.system(size: 12, weight: .medium))
                if let seconds = model.countdown {
                    Text("\(seconds)초 후 자동 종료").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.orange)
                } else {
                    Text(String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            if model.isRecording {
                Button(action: model.stop) { Image(systemName: "stop.fill").font(.system(size: 12)).frame(width: 36, height: 36).background(.white.opacity(0.15), in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel("녹음 종료 후 처리")
            }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color(red: 0.10, green: 0.115, blue: 0.12).opacity(0.97), in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.12), lineWidth: 1))
        .padding(4)
    }
}
