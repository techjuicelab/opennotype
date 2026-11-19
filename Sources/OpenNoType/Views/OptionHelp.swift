import SwiftUI
import OpenNoTypeCore
import AppKit

/// Shared presentation keeps only one option explanation open at a time.
@MainActor
@Observable
final class OptionHelpPresentation {
    static let shared = OptionHelpPresentation()
    var activeID: UUID?
}

struct OptionHelp: View {
    let title: String
    let message: String
    @State private var id = UUID()
    @State private var presentation = OptionHelpPresentation.shared
    @State private var explanationHeight: CGFloat = 24
    @State private var restoresFocusAfterDismissal = false
    @State private var escapeMonitor: Any?
    @State private var isHovered = false
    @FocusState private var buttonFocused: Bool

    private var isActive: Bool { presentation.activeID == id }

    var body: some View {
        Button {
            if isActive { closeAndReturnFocus() }
            else {
                restoresFocusAfterDismissal = true
                presentation.activeID = id
            }
        } label: {
            Image(systemName: isActive ? "questionmark.circle.fill" : "questionmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(isActive ? AppTheme.accentForeground : AppTheme.textSecondary)
                .opacity(isHovered || isActive || buttonFocused ? 0.95 : 0.45)
                .frame(width: 26, height: 26)
                .background(isHovered && !isActive ? AppTheme.hoverBackground : .clear, in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
        // Reading an explanation never mutates application data, even when its page is read-only.
        .environment(\.isEnabled, true)
        .tint(AppTheme.accentForeground)
        .focused($buttonFocused)
        .accessibilityLabel(L("\(title) 도움말", "Help for \(title)"))
        .help(L("\(title) 설명 보기", "About \(title)"))
        .popover(isPresented: Binding(
            get: { presentation.activeID == id },
            set: { presented in
                guard !presented, presentation.activeID == id else { return }
                presentation.activeID = nil
            }
        ), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 8)
                    Button(action: closeAndReturnFocus) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(AppIconButtonStyle(size: 26, bordered: false))
                    .accessibilityLabel(L("도움말 닫기", "Close help"))
                    .keyboardShortcut(.cancelAction)
                }
                Divider()
                ScrollView {
                    explanation.background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: OptionHelpHeightKey.self, value: geometry.size.height)
                        }
                    }
                }
                .frame(height: min(explanationHeight, 360))
                .onPreferenceChange(OptionHelpHeightKey.self) { explanationHeight = max(24, ceil($0)) }
            }
            .padding(AppLayout.panelInset)
            .frame(width: 380)
            .onExitCommand(perform: closeAndReturnFocus)
            .onAppear {
                // Handle Escape before NSPopover restores an unrelated prior responder.
                escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
                    if event.type != .keyDown {
                        // Clicking another control in the manager keeps that control's focus.
                        if event.window?.isMainWindow == true { restoresFocusAfterDismissal = false }
                        return event
                    }
                    guard event.keyCode == 53, presentation.activeID == id else { return event }
                    closeAndReturnFocus()
                    return nil
                }
            }
            .onDisappear(perform: removeEscapeMonitor)
        }
        .onChange(of: presentation.activeID) { oldID, newID in
            guard oldID == id, newID != id else { return }
            removeEscapeMonitor()
            if newID == nil, restoresFocusAfterDismissal {
                restoresFocusAfterDismissal = false
                DispatchQueue.main.async { buttonFocused = true }
            }
        }
        .onDisappear {
            removeEscapeMonitor()
            if presentation.activeID == id { presentation.activeID = nil }
        }
    }

    private var paragraphs: [String] {
        message
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                if index == 0 {
                    Text(paragraph)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    Text(paragraph)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(AppTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func closeAndReturnFocus() {
        guard presentation.activeID == id else { return }
        restoresFocusAfterDismissal = true
        presentation.activeID = nil
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }
}

private struct OptionHelpHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct OptionHelpLabel: View {
    let title: String
    let help: String

    init(_ title: String, help: String) {
        self.title = title
        self.help = help
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 13))
            OptionHelp(title: title, message: help)
        }
    }
}

/// Disable only the value control so that explanations stay available.
struct OptionToggle: View {
    let title: String
    let help: String
    @Binding var isOn: Bool
    var isEnabled: Bool

    init(_ title: String, help: String, isOn: Binding<Bool>, isEnabled: Bool = true) {
        self.title = title
        self.help = help
        self._isOn = isOn
        self.isEnabled = isEnabled
    }

    var body: some View {
        SettingsRow(title, help: help) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!isEnabled)
        }
    }
}
