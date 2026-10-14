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
    @FocusState private var buttonFocused: Bool

    var body: some View {
        Button {
            if presentation.activeID == id { closeAndReturnFocus() }
            else {
                restoresFocusAfterDismissal = true
                presentation.activeID = id
            }
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
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
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .tint(AppTheme.accentForeground)
                    .accessibilityLabel(L("도움말 닫기", "Close help"))
                    .keyboardShortcut(.cancelAction)
                }
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
            .padding(18)
            .frame(width: 350)
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

    private var explanation: some View {
        Text(message)
            .font(.system(size: 13))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
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
        HStack(spacing: 2) {
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
        HStack(spacing: 12) {
            OptionHelpLabel(title, help: help)
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .disabled(!isEnabled)
        }
    }
}
