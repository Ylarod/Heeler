import SwiftUI
import UIKit

/// Which way a swipe across an iPad sidebar turns its lists: to the one
/// after the shown list in the switch, or the one before it.
enum SidebarListSwipeDirection {
    case next
    case previous
}

extension View {
    /// Switches an iPad sidebar's lists with a horizontal swipe that starts
    /// off their rows: over a section header, the space below the rows, or
    /// an empty list. A row keeps its own swipe actions, so a swipe that
    /// starts on one never switches.
    ///
    /// SwiftUI gestures never see a touch in a List's empty space, which
    /// belongs to its collection view, so UIKit recognizers on the column
    /// watch instead, alongside the list's own scrolling.
    func sidebarListSwipe(
        _ onSwipe: @escaping @MainActor (SidebarListSwipeDirection) -> Void
    ) -> some View {
        background { SidebarListSwipeInstaller(onSwipe: onSwipe) }
    }
}

private struct SidebarListSwipeInstaller: UIViewRepresentable {
    let onSwipe: @MainActor (SidebarListSwipeDirection) -> Void

    func makeUIView(context: Context) -> InstallerView { InstallerView(onSwipe: onSwipe) }

    func updateUIView(_ view: InstallerView, context: Context) {
        view.onSwipe = onSwipe
    }

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        var onSwipe: @MainActor (SidebarListSwipeDirection) -> Void
        private var recognizer: UIPanGestureRecognizer?

        /// How far, or how fast, a released swipe must have gone to switch.
        private static let distance: CGFloat = 60
        private static let speed: CGFloat = 500

        init(onSwipe: @escaping @MainActor (SidebarListSwipeDirection) -> Void) {
            self.onSwipe = onSwipe
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            // The column's own view, which holds the lists: this view lies
            // behind them and receives no touches itself.
            guard window != nil, let host = hostView() else { return }
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
            recognizer.delegate = self
            host.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
        }

        private func hostView() -> UIView? {
            var responder: UIResponder? = next
            while let current = responder {
                if let controller = current as? UIViewController { return controller.view }
                responder = current.next
            }
            return nil
        }

        @objc private func didPan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let distance = recognizer.translation(in: self).x
            let speed = recognizer.velocity(in: self).x
            guard abs(distance) >= Self.distance || abs(speed) >= Self.speed else { return }
            // Like turning a page: a swipe toward the leading edge brings
            // in what follows.
            let towardLeft = (abs(distance) >= Self.distance ? distance : speed) < 0
            let towardLeading = towardLeft == (effectiveUserInterfaceLayoutDirection == .leftToRight)
            onSwipe(towardLeading ? .next : .previous)
        }

        /// The delegate method, which `UIView` also declares for its own
        /// recognizers; this view has none.
        override func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                let host = pan.view
            else { return false }
            let velocity = pan.velocity(in: host)
            guard abs(velocity.x) > abs(velocity.y) * 2 else { return false }
            let start = pan.location(in: host)
            // Only over the lists, not the switch above them or the foot.
            guard bounds.contains(convert(start, from: host)) else { return false }
            return !startsOnRow(start, in: host)
        }

        /// Whether a point lies on a row of the list on show. Not judged by
        /// the touched view: the list's scroll edge effect lies over its rows.
        private func startsOnRow(_ point: CGPoint, in host: UIView) -> Bool {
            Self.collectionViews(in: host).contains { list in
                isShown(list, below: host)
                    && list.indexPathForItem(at: list.convert(point, from: host)) != nil
            }
        }

        /// A sidebar keeps its other list built but invisible and untouchable;
        /// see `SidebarListShown`.
        private func isShown(_ view: UIView, below host: UIView) -> Bool {
            var current: UIView? = view
            while let view = current, view !== host {
                if view.isHidden || view.alpha < 0.01 || !view.isUserInteractionEnabled {
                    return false
                }
                current = view.superview
            }
            return true
        }

        private static func collectionViews(in view: UIView) -> [UICollectionView] {
            if let list = view as? UICollectionView { return [list] }
            return view.subviews.flatMap { collectionViews(in: $0) }
        }

        /// Alongside the list's scrolling only: once the swipe is under way,
        /// a header's button under the finger must not fire as well.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            other.view is UIScrollView && other is UIPanGestureRecognizer
        }
    }
}
