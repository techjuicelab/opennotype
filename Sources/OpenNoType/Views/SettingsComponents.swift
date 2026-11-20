import SwiftUI
import OpenNoTypeCore

/// A settings card: icon badge, title and one-line subtitle, optional header actions, then rows.
struct SettingsCard<Trailing: View, Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var help: String?
    var badge: (kind: StatusBadge.Kind, text: String)?
    var emphasized = false
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(icon: String, title: String, subtitle: String? = nil, help: String? = nil,
         badge: (kind: StatusBadge.Kind, text: String)? = nil, emphasized: Bool = false,
         @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon; self.title = title; self.subtitle = subtitle; self.help = help
        self.badge = badge; self.emphasized = emphasized
        self.trailing = trailing; self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(emphasized ? AppTheme.accentForeground : AppTheme.textSecondary)
                    .frame(width: AppLayout.cardHeaderIconSize, height: AppLayout.cardHeaderIconSize)
                    .background(AppTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(AppTypography.sectionTitle).foregroundStyle(AppTheme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        if let badge { StatusBadge(kind: badge.kind, text: badge.text) }
                        if let help { OptionHelp(title: title, message: help) }
                    }
                    if let subtitle {
                        Text(subtitle).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) { trailing() }
                    .controlSize(.regular)
            }
            VStack(alignment: .leading, spacing: 0) { content() }
        }
        .padding(AppLayout.panelInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: AppLayout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppLayout.cornerRadius).stroke(AppTheme.separator, lineWidth: 1))
    }
}

extension SettingsCard where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, help: String? = nil,
         badge: (kind: StatusBadge.Kind, text: String)? = nil, emphasized: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(icon: icon, title: title, subtitle: subtitle, help: help, badge: badge, emphasized: emphasized,
                  trailing: { EmptyView() }, content: content)
    }
}

enum SettingsItemState: Equatable {
    case neutral(String), accent(String), warning(String), error(String)

    var text: String {
        switch self { case .neutral(let t), .accent(let t), .warning(let t), .error(let t): t }
    }
    var color: Color {
        switch self {
        case .neutral: AppTheme.textSecondary
        case .accent: AppTheme.accentForeground
        case .warning: AppTheme.warm
        case .error: AppTheme.destructive
        }
    }
    /// Existing status sentences are informational unless the caller says otherwise.
    static func from(_ text: String?) -> Self? {
        guard let text, !text.isEmpty else { return nil }
        return .neutral(text)
    }
}

/// Title with a one-line explanation on the left and a naturally sized control on the right.
/// Detailed policy text stays available behind the optional help button.
struct SettingsItem<Trailing: View>: View {
    let title: String
    var detail: String?
    var help: String?
    var state: SettingsItemState?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, detail: String? = nil, help: String? = nil, state: SettingsItemState? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.detail = detail; self.help = help; self.state = state; self.trailing = trailing
    }

    var body: some View {
        // When controls leave too little room for the text, they move below it instead of squeezing it.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                SettingsItemText(title: title, detail: detail, help: help, state: state)
                    .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                controls
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsItemText(title: title, detail: detail, help: help, state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                controls
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: AppLayout.rowHeight)
    }

    private var controls: some View {
        HStack(spacing: 8) { trailing() }
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// A row whose control needs the full card width, such as a segmented choice or a slider.
struct SettingsStackedItem<Content: View>: View {
    let title: String
    var detail: String?
    var help: String?
    var state: SettingsItemState?
    var accessory: AnyView?
    @ViewBuilder var content: () -> Content

    init(_ title: String, detail: String? = nil, help: String? = nil, state: SettingsItemState? = nil,
         accessory: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.detail = detail; self.help = help; self.state = state
        self.accessory = accessory; self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                SettingsItemText(title: title, detail: nil, help: help, state: nil)
                Spacer(minLength: 8)
                if let accessory { accessory }
            }
            content().labelsHidden()
            if let detail {
                Text(detail).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let state {
                Text(state.text).font(AppTypography.caption).foregroundStyle(state.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct SettingsItemText: View {
    let title: String
    let detail: String?
    let help: String?
    let state: SettingsItemState?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title).font(AppTypography.body).foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let help { OptionHelp(title: title, message: help) }
            }
            if let detail {
                Text(detail).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let state {
                Text(state.text).font(AppTypography.caption).foregroundStyle(state.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Rows separated by dividers, without a divider after the last row.
struct SettingsRows<Content: View>: View {
    @ViewBuilder var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        _VariadicView.Tree(DividedRowsLayout()) { content }
    }
}

private struct DividedRowsLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != last { Divider() }
            }
        }
    }
}

/// An inline group that starts collapsed and summarizes its contents in the header.
struct SettingsDisclosure<Content: View>: View {
    let title: String
    var summary: String?
    @Binding var isExpanded: Bool
    var indentContent = true
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(title).font(AppTypography.body).foregroundStyle(AppTheme.textPrimary)
                    Spacer(minLength: 8)
                    if let summary { Text(summary).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary) }
                }
                .frame(minHeight: AppLayout.rowHeight)
                .padding(.horizontal, 6)
                .background(hovered ? AppTheme.hoverBackground.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, -6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .accessibilityValue(isExpanded ? L("펼쳐짐", "Expanded") : L("접힘", "Collapsed"))
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) { content() }
                    .padding(.leading, indentContent ? 17 : 0)
                    .transition(.opacity)
            }
        }
    }
}

struct StatusBadge: View {
    enum Kind { case neutral, accent, info, warning, error }
    let kind: Kind
    let text: String
    var systemImage: String?
    @Environment(\.colorScheme) private var colorScheme

    init(kind: Kind, text: String, systemImage: String? = nil) {
        self.kind = kind; self.text = text; self.systemImage = systemImage
    }

    private var tint: Color {
        switch kind {
        case .neutral: AppTheme.textSecondary
        case .accent: AppTheme.accentForeground
        case .info: AppTheme.info
        case .warning: AppTheme.warm
        case .error: AppTheme.destructive
        }
    }

    var body: some View {
        let dark = colorScheme == .dark
        HStack(spacing: 3.5) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)) }
            Text(text).font(AppTypography.badge).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .frame(minHeight: 20)
        .background(kind == .neutral ? AnyShapeStyle(AppTheme.surfaceSubtle) : AnyShapeStyle(tint.opacity(dark ? 0.18 : 0.13)), in: Capsule())
        .overlay(Capsule().stroke(kind == .neutral ? AppTheme.separator.opacity(0.8) : tint.opacity(dark ? 0.34 : 0.26), lineWidth: 1))
        .fixedSize()
    }
}

/// Five settings sections with icons. Falls back to short labels, then a menu, when space runs out.
struct SettingsTabBar: View {
    @Binding var selection: SettingsSection
    var newModelCandidateCount = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            track(compact: false).frame(minWidth: 640)
            track(compact: true).frame(minWidth: 460)
            HStack(spacing: 8) {
                Picker(L("설정 분류", "Settings category"), selection: $selection) {
                    ForEach(SettingsSection.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.menu).fixedSize()
                if newModelCandidateCount > 0 {
                    StatusBadge(kind: .accent, text: L("새 후보 \(newModelCandidateCount)", "\(newModelCandidateCount) new"))
                }
            }
        }
    }

    private func track(compact: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(SettingsSection.allCases) { section in
                SettingsTabItem(section: section, compact: compact, selected: selection == section,
                                showsDot: section == .aiModels && newModelCandidateCount > 0) { selection = section }
            }
        }
        .padding(4)
        .background(AppTheme.tabTrackBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.separator.opacity(0.7), lineWidth: 1))
    }
}

private struct SettingsTabItem: View {
    let section: SettingsSection
    let compact: Bool
    let selected: Bool
    let showsDot: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? AppTheme.accentForeground : AppTheme.textSecondary)
                    .overlay(alignment: .topTrailing) {
                        if showsDot {
                            Circle().fill(AppTheme.accentForeground).frame(width: 6, height: 6)
                                .overlay(Circle().stroke(selected ? AppTheme.tabSelectedBackground : AppTheme.tabTrackBackground, lineWidth: 1.5))
                                .offset(x: 4, y: -4)
                        }
                    }
                Text(compact ? section.tabTitle : section.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected || hovered ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(selected ? AppTheme.tabSelectedBackground : hovered ? AppTheme.hoverBackground.opacity(0.7) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? AppTheme.accent.opacity(colorScheme == .dark ? 0.35 : 0.45) : .clear, lineWidth: 1))
            .shadow(color: selected ? .black.opacity(colorScheme == .dark ? 0.24 : 0.06) : .clear, radius: 2, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Lays out children left to right and wraps them onto new rows.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + verticalSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + horizontalSpacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + horizontalSpacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// A segmented choice in the tab bar's visual language. Native segmented pickers drop icons and
/// stretch into a thin bar; this keeps icons and falls back to a menu when the labels do not fit.
struct SettingsSegmentedPicker<Value: Hashable & Identifiable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    var icon: ((Value) -> String?)?
    var isEnabled = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            track
            Picker(title, selection: $selection) {
                ForEach(options) { Text(label($0)).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
        }
        .disabled(!isEnabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var track: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                SegmentButton(title: label(option), icon: icon?(option), selected: selection == option, enabled: isEnabled) { selection = option }
            }
        }
        .padding(3)
        .background(AppTheme.tabTrackBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.separator.opacity(0.7), lineWidth: 1))
    }
}

private struct SegmentButton: View {
    let title: String
    let icon: String?
    let selected: Bool
    var enabled = true
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .medium)) }
                Text(title).font(.system(size: 12.5, weight: selected ? .semibold : .regular)).lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .opacity(enabled ? 1 : 0.55)
            .foregroundStyle(selected ? AppTheme.textPrimary : hovered ? AppTheme.textPrimary : AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(selected ? AppTheme.tabSelectedBackground : hovered ? AppTheme.hoverBackground.opacity(0.7) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? AppTheme.accent.opacity(colorScheme == .dark ? 0.35 : 0.40) : .clear, lineWidth: 1))
            .shadow(color: selected ? .black.opacity(colorScheme == .dark ? 0.24 : 0.06) : .clear, radius: 2, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A lightweight navigation link for rows whose main control is a switch.
struct SettingsLinkButton: View {
    let title: String
    var systemImage = "chevron.right"
    let action: () -> Void
    @State private var hovered = false

    init(_ title: String, systemImage: String = "chevron.right", action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
            }
            .font(AppTypography.caption.weight(.medium))
            .foregroundStyle(AppTheme.accentForeground)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(hovered ? AppTheme.hoverBackground : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .padding(.trailing, 4)
    }
}

/// Places a label's icon after its title, matching disclosure buttons such as "Change ⌄".
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.title; configuration.icon.font(.system(size: 10, weight: .semibold)) }
    }
}
