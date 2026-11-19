import AppKit
import SwiftUI
import OpenNoTypeCore

/// Shared geometry for the manager, data pages, settings and auxiliary surfaces.
enum AppLayout {
    static let pageInset: CGFloat = 24
    static let panelInset: CGFloat = 16
    static let panelSpacing: CGFloat = 16
    static let rowHeight: CGFloat = 44
    static let statusRowHeight: CGFloat = 56
    static let controlHeight: CGFloat = 32
    static let primaryControlHeight: CGFloat = 36
    static let helpHitArea: CGFloat = 28
    static let contentMaxWidth: CGFloat = 1184
    static let sidebarWidth: CGFloat = 208
    static let toolbarHeight: CGFloat = 52
    static let valueColumnWidth: CGFloat = 240
    static let cornerRadius: CGFloat = 10
}

enum AppTypography {
    static let pageTitle: Font = .system(size: 22, weight: .semibold)
    static let sectionTitle: Font = .system(size: 15, weight: .semibold)
    static let body: Font = .system(size: 13)
    static let caption: Font = .system(size: 12)
    static let utility: Font = .system(size: 12, design: .monospaced)
}

enum AppTheme {
    static let accent = adaptive(0x326B58, 0xA0D8BC)
    static let accentForeground = accent
    static let info = adaptive(0x2D6AA3, 0x82B8EC)
    static let warm = adaptive(0x8B5219, 0xF2BE80)
    static let destructive = adaptive(0xB93838, 0xFFA8A8)
    static let pageBackground = adaptive(0xF8F9FA, 0x1E262E)
    static let panelBackground = adaptive(0xFFFFFF, 0x232C35)
    static let sidebarBackground = adaptive(0xF5F6F7, 0x1B222A)
    static let hoverBackground = adaptive(0xECEFF2, 0x2C3743)
    static let surfaceSubtle = adaptive(0xF1F4F6, 0x28323D)
    static let keycapBackground = adaptive(0xF2F4F7, 0x2A343F)
    static let keycapBorder = adaptive(0xCFD6DD, 0x455362)
    static let separator = adaptive(0xDCE1E6, 0x3B4856)
    static let textPrimary = adaptive(0x222A31, 0xEDF2F6)
    static let textSecondary = adaptive(0x58646F, 0xB0BDC8)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

struct AppPageHeader: View {
    let title: String
    let help: String?
    let subtitle: String?

    init(_ title: String, help: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.help = help
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(AppTypography.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                if let help { OptionHelp(title: title, message: help) }
            }
            if let subtitle { Text(subtitle).font(AppTypography.caption).foregroundStyle(.secondary) }
        }
    }
}

/// Explanations stay available while only the control is disabled by its owner.
struct SettingsRow<Content: View>: View {
    let title: String
    let help: String?
    let state: String?
    @ViewBuilder var content: Content

    init(_ title: String, help: String? = nil, state: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.help = help
        self.state = state
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(AppTypography.body).fixedSize(horizontal: false, vertical: true)
                    if let help { OptionHelp(title: title, message: help) }
                }
                if let state, !state.isEmpty {
                    Text(state).font(AppTypography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { content }
                .labelsHidden().frame(width: AppLayout.valueColumnWidth, alignment: .trailing)
                .frame(minHeight: AppLayout.controlHeight)
        }
        .padding(.vertical, 6)
        .frame(minHeight: state?.isEmpty == false ? AppLayout.statusRowHeight : AppLayout.rowHeight)
    }
}

struct SettingsGroupHeading: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 4).padding(.bottom, 4)
    }
}

struct AppActionButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        AppActionButtonBody(configuration: configuration, primary: primary)
    }
}

private struct AppActionButtonBody: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    let configuration: ButtonStyle.Configuration
    let primary: Bool

    var body: some View {
        let destructive = configuration.role == .destructive
        let backgroundColor: Color = {
            if primary { return destructive ? AppTheme.destructive : AppTheme.accent }
            if isHovered && isEnabled {
                return destructive ? AppTheme.destructive.opacity(0.08) : AppTheme.hoverBackground
            }
            return AppTheme.panelBackground
        }()
        let borderColor: Color = {
            if primary { return .clear }
            if isHovered && isEnabled {
                return destructive ? AppTheme.destructive.opacity(0.45) : AppTheme.keycapBorder
            }
            return AppTheme.separator
        }()
        return configuration.label
            .font(AppTypography.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(minHeight: primary ? AppLayout.primaryControlHeight : AppLayout.controlHeight)
            .foregroundStyle(primary ? Color(nsColor: .controlBackgroundColor) : destructive ? AppTheme.destructive : AppTheme.textPrimary)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .fill(primary && isHovered && isEnabled && !configuration.isPressed ? Color.white.opacity(0.08) : .clear)
            )
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 1))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.76 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isHovered = $0 }
    }
}

/// Compact square icon button that avoids AppActionButtonStyle's horizontal text padding.
struct AppIconButtonStyle: ButtonStyle {
    var size: CGFloat = AppLayout.controlHeight
    var bordered: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        AppIconButtonBody(configuration: configuration, size: size, bordered: bordered)
    }
}

private struct AppIconButtonBody: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    let configuration: ButtonStyle.Configuration
    let size: CGFloat
    let bordered: Bool

    var body: some View {
        let destructive = configuration.role == .destructive
        let backgroundColor: Color = {
            if isHovered && isEnabled {
                return destructive ? AppTheme.destructive.opacity(0.10) : AppTheme.hoverBackground
            }
            return bordered ? AppTheme.panelBackground : .clear
        }()
        let borderColor: Color = {
            guard bordered else { return .clear }
            if isHovered && isEnabled {
                return destructive ? AppTheme.destructive.opacity(0.45) : AppTheme.keycapBorder
            }
            return AppTheme.separator
        }()
        return configuration.label
            .font(.system(size: 13))
            .frame(width: size, height: size)
            .foregroundStyle(destructive ? AppTheme.destructive : AppTheme.textPrimary)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 1))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.72 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isHovered = $0 }
    }
}

/// Unified copy button with crisp in-place confirmation that resets automatically.
struct CopyActionButton: View {
    let title: String
    var copiedTitle: String = L("복사됨", "Copied")
    let text: String
    var primary: Bool = false
    var disabled: Bool = false
    var onError: ((String) -> Void)? = nil
    var onCopied: (() -> Void)? = nil
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            performCopy()
        } label: {
            Label(copied ? copiedTitle : title, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(AppActionButtonStyle(primary: primary))
        .disabled(disabled || text.isEmpty)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: copied)
        .onChange(of: text) { _, _ in
            resetTask?.cancel(); resetTask = nil; copied = false
        }
        .onDisappear {
            resetTask?.cancel(); resetTask = nil
        }
    }

    private func performCopy() {
        guard !disabled, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(text, forType: .string) {
            copied = true
            onCopied?()
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .milliseconds(1800))
                guard !Task.isCancelled else { return }
                copied = false
            }
        } else {
            onError?(L("복사하지 못했습니다. 텍스트를 선택해 직접 복사해 주세요.", "Could not copy the text. Select it and copy it manually."))
        }
    }
}

/// Visual keycap presentation for keyboard shortcuts.
struct ShortcutKeycap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(AppTypography.utility)
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppTheme.keycapBackground, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.keycapBorder, lineWidth: 1))
            .textSelection(.enabled)
    }
}

extension View {
    /// Applies shared visual tokens to modal sheets so every sheet matches the manager window.
    func appSheetStyle() -> some View {
        self
            .background(AppTheme.pageBackground)
            .font(AppTypography.body)
            .buttonStyle(AppActionButtonStyle())
            .tint(AppTheme.accent)
            .controlSize(.regular)
    }
}
