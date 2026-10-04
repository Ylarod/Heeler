import SwiftUI

/// An iPhone's way back from a pushed Agent, which the edge swipe alone
/// never showed (#396). Separate glass pieces float over the terminal:
/// Back, the Agent's name, any trailing actions in one capsule, and at the
/// far end a fold button that stays put. Folding leaves only that button,
/// so the header can cover almost no output.
///
/// Trailing actions are plain values rather than views, so a screen can
/// leave out the ones it cannot offer and the capsule goes with the last.
struct AgentDetailHeader: View {
    static let controlSize: CGFloat = 44
    /// Buttons sharing the actions capsule sit closer than standalone ones.
    private static let capsuleButtonWidth: CGFloat = 36
    private static let capsuleInset: CGFloat = (controlSize - capsuleButtonWidth) / 2

    let title: String
    let subtitle: String
    let palette: TerminalThemePalette
    @Binding var isExpanded: Bool
    let onBack: () -> Void
    var actions: [AgentDetailHeaderAction] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            if isExpanded {
                Group {
                    AgentDetailHeaderButton("Back", systemImage: "chevron.left", action: onBack)
                        .headerGlass(in: .circle)
                    titleBlock
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(-1)
                }
                .transition(
                    .scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            }
            if isExpanded, !actions.isEmpty {
                HStack(spacing: 0) {
                    ForEach(actions) { action in
                        AgentDetailHeaderButton(
                            action.title, systemImage: action.systemImage,
                            width: Self.capsuleButtonWidth, action: action.perform)
                    }
                }
                .padding(.horizontal, Self.capsuleInset)
                .fixedSize()
                .headerGlass(in: .capsule)
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
            // A window's top bar, which is what this shows and hides: put
            // away while it is out, filled in while it is folded.
            systemImage: isExpanded
                ? "menubar.arrow.up.rectangle" : "inset.filled.topthird.rectangle"
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
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(palette.foreground.opacity(0.65))
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: Self.controlSize)
        .headerGlass(in: .capsule)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One of `AgentDetailHeader`'s trailing buttons.
struct AgentDetailHeaderAction: Identifiable {
    let title: LocalizedStringKey
    let systemImage: String
    let perform: () -> Void

    var id: String { systemImage }
}

/// An icon button inside `AgentDetailHeader`. It has no surface of its own:
/// the header puts Back and the fold button on glass circles, and its
/// trailing actions together on one glass capsule.
struct AgentDetailHeaderButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let width: CGFloat
    let action: () -> Void

    init(
        _ title: LocalizedStringKey, systemImage: String,
        width: CGFloat = AgentDetailHeader.controlSize, action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.width = width
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: width, height: AgentDetailHeader.controlSize)
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
