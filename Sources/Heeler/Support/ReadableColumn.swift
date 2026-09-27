import SwiftUI
import UIKit

extension View {
    /// Narrows a tab's NavigationStack to a centered readable column in a
    /// wide window, about the width its pages had as form sheets.
    ///
    /// Apply it to the stack. It widens the stack's safe area, so the bar's
    /// title and buttons move in with the content and every pushed page
    /// shares the column, while scroll views still span the window: their
    /// backgrounds reach its edges and the margins scroll too. Compact width
    /// is left alone. Each List or Form page adds `readableColumnPage()`.
    func readableColumn() -> some View {
        modifier(ReadableColumn())
    }

    /// Lines a List or Form's cards up under the bar's title inside a
    /// `readableColumn()`; anywhere else it does nothing. A page that sets
    /// its own horizontal `contentMargins` passes them as `contentMargin`:
    /// the column's safe area absorbs them rather than adding to them.
    func readableColumnPage(contentMargin: CGFloat = 0) -> some View {
        modifier(ReadableColumnPage(contentMargin: contentMargin))
    }
}

struct ReadableColumn: ViewModifier {
    /// The column's width, the bar and the List's own margins included:
    /// inset-grouped cards come out 680 points wide on an iPad.
    static let width: CGFloat = 720

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var availableWidth: CGFloat = 0

    func body(content: Content) -> some View {
        let inset = horizontalSizeClass == .regular ? Self.sideInset(forWidth: availableWidth) : 0
        content
            .environment(\.isInReadableColumn, inset > 0)
            // `safeAreaPadding` stops at the stack: its pages and bar live
            // in UIKit, so the inset goes onto the navigation controller.
            .background { NavigationColumnInset(horizontal: inset) }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing
            } action: { width in
                availableWidth = width
            }
    }

    /// Each side's share of what a `width` column leaves over.
    static func sideInset(forWidth width: CGFloat) -> CGFloat {
        max(0, ((width - Self.width) / 2).rounded(.down))
    }
}

private struct ReadableColumnPage: ViewModifier {
    /// Past a safe area inset, List cards keep 16 points from it while the
    /// bar keeps the iPad's 20: the title would sit this far right of them.
    static let titleOffset: CGFloat = 4

    let contentMargin: CGFloat
    @Environment(\.isInReadableColumn) private var isInReadableColumn

    func body(content: Content) -> some View {
        // Zero rather than a branch, so a rotation keeps the list's state.
        content.safeAreaPadding(
            .horizontal, isInReadableColumn ? Self.titleOffset + contentMargin : 0)
    }
}

extension EnvironmentValues {
    @Entry fileprivate var isInReadableColumn = false
}

/// Sets the horizontal additional safe area of the NavigationStack it sits
/// behind. SwiftUI hosts the stack's navigation controller beside this one,
/// under the same parent.
private struct NavigationColumnInset: UIViewControllerRepresentable {
    let horizontal: CGFloat

    func makeUIViewController(context: Context) -> Anchor { Anchor() }

    func updateUIViewController(_ anchor: Anchor, context: Context) {
        anchor.horizontal = horizontal
    }

    final class Anchor: UIViewController {
        var horizontal: CGFloat = 0 {
            didSet { if horizontal != oldValue { apply() } }
        }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        private func apply() {
            guard let navigation = parent?.children.lazy.compactMap({ $0 as? UINavigationController }).first
            else { return }
            var insets = navigation.additionalSafeAreaInsets
            guard insets.left != horizontal || insets.right != horizontal else { return }
            insets.left = horizontal
            insets.right = horizontal
            navigation.additionalSafeAreaInsets = insets
        }
    }
}
