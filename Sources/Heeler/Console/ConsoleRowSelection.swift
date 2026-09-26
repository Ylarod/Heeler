import SwiftUI
import UIKit

/// How the Console's sidebar lists show the row on stage beside them.
///
/// `List(selection:)` would paint the system selection: a full-width band
/// in the tint, which is system blue while the list has keyboard focus, and
/// it flips the row's hierarchical text to white. Neither suits a list set
/// beside a terminal, so the sidebar draws the app's own quiet selection,
/// the same neutral fill the terminal drawer uses, inside the row's shape.
enum ConsoleRowSelection {
    static let fill = Color(uiColor: .tertiarySystemFill)
}

/// A rounded, inset fill behind a selected sidebar row; nothing elsewhere.
/// Compact width keeps no persistent selection, so the list's own press
/// highlight is left alone there.
struct ConsoleRowSelectionBackground: ViewModifier {
    let isSelected: Bool
    @Environment(\.isSidebarColumn) private var isSidebarColumn

    func body(content: Content) -> some View {
        if isSidebarColumn {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            content.listRowBackground(
                shape
                    .fill(isSelected ? ConsoleRowSelection.fill : Color.clear)
                    .background(ListRowFocusHalo(shape: shape))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3))
        } else {
            content
        }
    }
}

/// Keeps a sidebar row's text in its normal colors while selected: the list
/// raises a selected row's background prominence, which turns hierarchical
/// styles such as the Host name's `.secondary` white.
struct ConsoleRowSelectionContent: ViewModifier {
    @Environment(\.isSidebarColumn) private var isSidebarColumn

    func body(content: Content) -> some View {
        if isSidebarColumn {
            content
                .environment(\.backgroundProminence, .standard)
                .foregroundStyle(Color.primary)
        } else {
            content
        }
    }
}

/// The ring a hardware keyboard's focus draws around a sidebar row takes
/// the list's tint; neutral, it frames the selection instead of shouting
/// system blue beside the terminal.
struct ConsoleSidebarListTint: ViewModifier {
    @Environment(\.isSidebarColumn) private var isSidebarColumn

    func body(content: Content) -> some View {
        content.tint(isSidebarColumn ? Color(uiColor: .systemGray) : nil)
    }
}

/// Fits a plain list row's keyboard focus ring to `shape`, drawn where this
/// view sits in the row's background. A plain list rings the whole cell, a
/// square band across the sidebar around the rounded, inset row it frames.
struct ListRowFocusHalo<S: Shape>: UIViewRepresentable {
    let shape: S

    func makeUIView(context: Context) -> HaloView {
        HaloView()
    }

    func updateUIView(_ view: HaloView, context: Context) {
        let shape = shape
        view.makePath = { shape.path(in: $0).cgPath }
    }

    final class HaloView: UIView {
        var makePath: ((CGRect) -> CGPath)? {
            didSet { setNeedsLayout() }
        }

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is unavailable")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyHalo()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyHalo()
        }

        private var cell: UICollectionViewCell? {
            var view = superview
            while let current = view {
                if let cell = current as? UICollectionViewCell { return cell }
                view = current.superview
            }
            return nil
        }

        /// The halo takes the cell's coordinate space.
        private func applyHalo() {
            guard window != nil, let makePath, let cell, !bounds.isEmpty else { return }
            let origin = convert(bounds.origin, to: cell)
            var transform = CGAffineTransform(translationX: origin.x, y: origin.y)
            guard let path = makePath(CGRect(origin: .zero, size: bounds.size))
                .copy(using: &transform)
            else { return }
            cell.focusEffect = UIFocusHaloEffect(path: UIBezierPath(cgPath: path))
        }
    }
}

/// A sidebar row's context menu. Lifting the list cell shows what the cell
/// is beside the terminal: a clear background, so the row's text floats
/// over the glass and past the sidebar's edge. The sidebar lifts a card of
/// the row instead; compact width keeps the system's lifted row.
struct ConsoleRowContextMenu<MenuItems: View, Preview: View>: ViewModifier {
    private static var previewWidth: CGFloat { 340 }

    private let menuItems: MenuItems
    private let preview: Preview
    @Environment(\.isSidebarColumn) private var isSidebarColumn

    init(@ViewBuilder menuItems: () -> MenuItems, @ViewBuilder preview: () -> Preview) {
        self.menuItems = menuItems()
        self.preview = preview()
    }

    func body(content: Content) -> some View {
        if isSidebarColumn {
            content.contextMenu {
                menuItems
            } preview: {
                preview
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(width: Self.previewWidth, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
            }
        } else {
            content.contextMenu { menuItems }
        }
    }
}
