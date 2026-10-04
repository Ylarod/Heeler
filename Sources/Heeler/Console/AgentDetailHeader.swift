import SwiftUI

/// An iPhone's way back from a pushed Agent, which the edge swipe alone
/// never showed (#396). Separate glass pieces float over the terminal:
/// Back, the Agent's name, any trailing actions in one capsule, and at the
/// far end a fold button that stays put. Folding leaves only that button,
/// so the header can cover almost no output.
///
/// Trailing actions take `AgentDetailHeaderButton`s.
struct AgentDetailHeader<Actions: View>: View {
    static var controlSize: CGFloat { 44 }

    let title: String
    let subtitle: String
    let palette: TerminalThemePalette
    @Binding var isExpanded: Bool
    let onBack: () -> Void
    let actions: Actions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        subtitle: String,
        palette: TerminalThemePalette,
        isExpanded: Binding<Bool>,
        onBack: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.palette = palette
        _isExpanded = isExpanded
        self.onBack = onBack
        self.actions = actions()
    }

    private var hasActions: Bool { Actions.self != EmptyView.self }

    var body: some View {
        HStack(spacing: 8) {
            if isExpanded {
                Group {
                    AgentDetailHeaderButton("Back", systemImage: "chevron.left", action: onBack)
                        .headerGlass(in: .circle)
                    titleBlock
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(-1)
                    if hasActions {
                        HStack(spacing: 0) { actions }
                            .fixedSize()
                            .headerGlass(in: .capsule)
                    }
                }
                .transition(
                    .scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            }
            foldButton
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .foregroundStyle(palette.foreground)
    }

    /// Stays at the far end in both states.
    private var foldButton: some View {
        AgentDetailHeaderButton(
            isExpanded ? "Hide Header" : "Show Header",
            // Points the way the header goes: folding into this button at
            // the trailing end, or unfolding back out to the leading side.
            systemImage: isExpanded ? "arrow.right.to.line" : "arrow.left.to.line"
        ) {
            withAnimation(reduceMotion ? nil : .snappy) {
                isExpanded.toggle()
            }
        }
        .headerGlass(in: .circle)
    }

    /// On glass like the buttons: bare text over output stays unreadable
    /// however strong a halo it gets.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(palette.foreground.opacity(0.65))
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: Self.controlSize)
        .headerGlass(in: .capsule)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension AgentDetailHeader where Actions == EmptyView {
    init(
        title: String,
        subtitle: String,
        palette: TerminalThemePalette,
        isExpanded: Binding<Bool>,
        onBack: @escaping () -> Void
    ) {
        self.init(
            title: title, subtitle: subtitle, palette: palette, isExpanded: isExpanded,
            onBack: onBack, actions: { EmptyView() })
    }
}

/// An icon button inside `AgentDetailHeader`. It has no surface of its own:
/// the header puts Back and the fold button on glass circles, and its
/// trailing actions together on one glass capsule.
struct AgentDetailHeaderButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(
                    width: AgentDetailHeader<EmptyView>.controlSize,
                    height: AgentDetailHeader<EmptyView>.controlSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension View {
    /// Liquid Glass where the system has it, a blur before that.
    @ViewBuilder
    fileprivate func headerGlass(in shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}
