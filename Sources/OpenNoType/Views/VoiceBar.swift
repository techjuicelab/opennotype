import AppKit
import SwiftUI
import OpenNoTypeCore

@MainActor
final class VoiceBarController {
    private let panel: NSPanel
    init(model: AppModel) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 448, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: VoiceBar(model: model))
        model.onPhaseChange = { [weak self, weak model] in
            guard let self, let model else { return }
            if model.phase != .idle || model.transientMessage != nil {
                let warningHeight: CGFloat = model.isBusy && model.transientMessage != nil ? 56 : 0
                let previewHeight: CGFloat = model.isLocalPreviewActive ? 72 : 0
                self.panel.setContentSize(NSSize(width: 448, height: 80 + warningHeight + previewHeight))
                if let screen = NSScreen.main {
                    self.panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 224, y: screen.visibleFrame.minY + 32))
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
        VStack(alignment: .leading, spacing: 8) {
            if !model.isBusy, let message = model.transientMessage {
                // Outcome summary after work ended: no controls and no focus activation.
                HStack(spacing: 12) {
                    Image(systemName: "info.circle").font(.system(size: 16, weight: .medium))
                    Text(message).font(AppTypography.body).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 36)
            } else {
                workControls
                if let message = model.transientMessage {
                    // Warnings expand below the fixed status/time/control row.
                    Text(message).font(AppTypography.caption).foregroundStyle(.orange).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(message)
                }
            }
            if model.isLocalPreviewActive {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("미리보기 · 확정 결과 아님", "Preview · Not the final result"))
                        .font(AppTypography.caption).foregroundStyle(.white.opacity(0.65))
                    Text(model.localPreviewText.isEmpty
                         ? L("최근 발화 미리보기 준비 중…", "Preparing recent speech preview…") : model.localPreviewText)
                        .font(AppTypography.body).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(L("최근 발화 미리보기, 확정 결과 아님", "Recent speech preview, not the final result"))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(AppLayout.panelInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(red: 0.10, green: 0.115, blue: 0.12).opacity(0.97), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1))
        .padding(4)
    }

    private var workControls: some View {
        HStack(spacing: 12) {
            Button(action: model.cancel) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .frame(width: AppLayout.controlHeight, height: AppLayout.controlHeight)
            }
            .buttonStyle(.plain).accessibilityLabel(L("녹음 또는 처리 취소", "Cancel recording or processing"))
            if model.phase == .starting || model.phase == .processing {
                ProgressView().controlSize(.small).tint(.white).frame(width: 64, height: 36)
            } else {
                HStack(spacing: 4) {
                    ForEach(0..<11, id: \.self) { index in
                        Capsule().fill(Color.white.opacity(0.9))
                            .frame(width: 2, height: 4 + model.level * Double(12 + (index * 7 % 21)))
                    }
                }.frame(width: 64, height: 36)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: model.level)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.status).font(AppTypography.body)
                if let seconds = model.countdown {
                    Text(L("\(seconds)초 후 자동 종료", "Stops automatically in \(seconds)s"))
                        .font(AppTypography.utility.weight(.semibold)).foregroundStyle(.orange)
                } else {
                    Text(String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60))
                        .font(AppTypography.utility).foregroundStyle(.white.opacity(0.65))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            if model.isRecording {
                Button(action: model.stop) {
                    Image(systemName: "stop.fill").font(.system(size: 12))
                        .frame(width: AppLayout.primaryControlHeight, height: AppLayout.primaryControlHeight)
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).accessibilityLabel(L("녹음 종료 후 처리", "Finish recording and process"))
            }
        }
    }
}
