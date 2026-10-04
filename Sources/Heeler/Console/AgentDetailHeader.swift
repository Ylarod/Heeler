import SwiftUI

/// An iPhone's way back from a pushed Agent, which the edge swipe alone
/// never showed (#396). It floats over the terminal, docked to the leading
/// edge: a handle that stays put, then Back, the Agent's name, and any
/// trailing actions, which all fold into the handle so the header covers no
/// more output than the Workspace drawer's handle does.
///
/// Trailing actions take `AgentDetailHeaderButton`s. Without them the
/// header hugs its title; with them it spans the width, the title takes
/// what the buttons leave, and the buttons sit at the far end.
struct AgentDetailHeader<Actions: View>: View {
    static var height: CGFloat { 48 }

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
        HStack(spacing: 0) {
            handle
            if isExpanded {
                HStack(spacing: 10) {
                    AgentDetailHeaderButton("Back", systemImage: "chevron.left", action: onBack)
                    titleBlock
                        .frame(maxWidth: hasActions ? .infinity : nil, alignment: .leading)
                    if hasActions {
                        HStack(spacing: 4) { actions }
                            .fixedSize()
                    }
                }
                // Circular buttons at the end want the same margin as Back
                // has from the handle; text wants a little more.
                .padding(.trailing, hasActions ? 6 : 16)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(height: Self.height)
        .clipShape(AgentDetailHeaderSurface.shape)
        .background { AgentDetailHeaderSurface(palette: palette) }
        .foregroundStyle(palette.foreground)
    }

    /// Stays against the edge in both states; its glyph says which way the
    /// header will go.
    private var handle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: isExpanded ? "chevron.compact.left" : "chevron.compact.right")
                .font(.system(size: 15, weight: .semibold))
                .opacity(TerminalFloatingButtonStyle.iconOpacity)
                .frame(width: TerminalEdgeTabBackground.width, height: Self.height)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide Header" : "Show Header")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(palette.foreground.opacity(0.6))
        }
        .lineLimit(1)
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

/// A round icon button inside `AgentDetailHeader`: Back, and the actions
/// at its trailing end. It takes the header's foreground.
struct AgentDetailHeaderButton: View {
    static var size: CGFloat { 36 }

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
                .font(.system(size: 16, weight: .semibold))
                .frame(width: Self.size, height: Self.size)
                .background(.foreground.opacity(0.1), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// The header's surface: the trailing-edge tabs' shape mirrored onto the
/// leading edge, with their border and shadow over a blur, so output
/// passing beneath the Agent's name reads as texture instead of text
/// competing with it.
private struct AgentDetailHeaderSurface: View {
    /// Squared off against the screen, rounded on the side facing the terminal.
    static let shape = UnevenRoundedRectangle(
        topLeadingRadius: 0,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: TerminalEdgeTabBackground.cornerRadius,
        topTrailingRadius: TerminalEdgeTabBackground.cornerRadius,
        style: .continuous)

    let palette: TerminalThemePalette

    var body: some View {
        Self.shape
            .fill(.ultraThinMaterial)
            .overlay {
                Self.shape
                    .fill(palette.background.mix(with: palette.foreground, by: 0.16).opacity(0.5))
            }
            .overlay {
                Self.shape.strokeBorder(palette.foreground.opacity(0.2), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .allowsHitTesting(false)
    }
}
