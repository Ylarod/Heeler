import SwiftUI
import UIKit

/// What the Console's regular-width floating tab bar needs from UIKit,
/// which SwiftUI offers no handle for. Lives in a list tab's content, so the
/// tab bar controller it reaches is the Console's own.
///
/// A tab shown for the first time after launch is laid out with the
/// floating bar inside its top safe area: its split view starts a bar's
/// height too low, until a later visit or a rotation recomputes it. A change
/// of the bar's visibility recomputes it at once.
///
/// The bar's glass also ignores `toolbarColorScheme(_:for: .tabBar)`, so
/// over a dark terminal it renders a light glass on near-black: a flat gray
/// pill with dark labels. The bar takes the terminal's chrome scheme here
/// instead, as the status bar above it does, and gives it back when the
/// list tab leaves the screen.
struct ConsoleTabBarBridge: UIViewRepresentable {
    /// The scheme the floating bar renders in; nil follows the app.
    let chromeScheme: ColorScheme?

    func makeUIView(context: Context) -> BridgeView {
        BridgeView()
    }

    func updateUIView(_ view: BridgeView, context: Context) {
        view.chromeScheme = chromeScheme
    }

    final class BridgeView: UIView {
        /// The bridge that last styled each tab bar controller's chrome. A
        /// tab switch can bring the arriving tab's bridge into the window
        /// before the leaving one goes; only the owner resets the style.
        private static let owners =
            NSMapTable<UITabBarController, BridgeView>.weakToWeakObjects()

        var chromeScheme: ColorScheme? {
            didSet {
                guard chromeScheme != oldValue else { return }
                applyChromeScheme()
            }
        }

        private var hasSettledSafeArea = false
        private weak var styledController: UITabBarController?

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
            // Leaving for Hosts or Settings, whose bar follows the app.
            guard window != nil else { return resetChromeScheme() }
            applyChromeScheme()
            // The floating bar is regular width's; a compact bar sits at the
            // bottom, outside the safe area in question.
            guard !hasSettledSafeArea, traitCollection.horizontalSizeClass == .regular
            else { return }
            hasSettledSafeArea = true
            // After the layout pass that attached this tab; toggling during
            // it leaves the stale inset in place.
            Task { @MainActor [weak self] in self?.settleSafeArea() }
        }

        /// The bar's views can be rebuilt by a rotation or size change.
        override func layoutSubviews() {
            super.layoutSubviews()
            applyChromeScheme()
        }

        private var tabBarController: UITabBarController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UITabBarController { return controller }
                responder = current.next
            }
            return nil
        }

        /// Hides and shows the bar within one turn of the run loop, so
        /// nothing renders in between and the visibility ends where it was.
        private func settleSafeArea() {
            guard window != nil, let controller = tabBarController else { return }
            let isHidden = controller.isTabBarHidden
            controller.setTabBarHidden(!isHidden, animated: false)
            controller.setTabBarHidden(isHidden, animated: false)
        }

        /// Every view of the tab bar controller except the one holding the
        /// selected tab's content (this view's own ancestor) is bar chrome.
        /// Only the tab on screen may style it; the others are out of the
        /// window.
        private func applyChromeScheme() {
            guard window != nil, let controller = tabBarController else { return }
            let style: UIUserInterfaceStyle =
                switch chromeScheme {
                case .dark: .dark
                case .light: .light
                default: .unspecified
                }
            for chrome in controller.view.subviews where !isDescendant(of: chrome) {
                if chrome.overrideUserInterfaceStyle != style {
                    chrome.overrideUserInterfaceStyle = style
                }
            }
            styledController = controller
            Self.owners.setObject(self, forKey: controller)
        }

        private func resetChromeScheme() {
            guard let controller = styledController,
                Self.owners.object(forKey: controller) === self
            else { return }
            for chrome in controller.view.subviews
            where chrome.overrideUserInterfaceStyle != .unspecified {
                chrome.overrideUserInterfaceStyle = .unspecified
            }
            Self.owners.removeObject(forKey: controller)
            styledController = nil
        }
    }
}

/// Lets a sidebar's bar rise past the floating tab bar when the two do not
/// meet. UIKit sets each split view column below the bar across the whole
/// window, so beside a centered bar that clears the sidebar the list's
/// title and buttons still start a bar's height under the status bar. The
/// column gives that inset back whenever the bar's pill lies clear of it,
/// and keeps it where the pill reaches over the column, as in portrait.
///
/// Only a column that reaches the window's top: a sidebar floating as an
/// inset card, as on iPadOS 26, keeps the system's placement.
struct SidebarTabBarClearance: UIViewRepresentable {
    /// The split view's size. Resizing a window recenters the bar without
    /// resizing the sidebar, which alone would never lay this view out.
    let containerSize: CGSize

    func makeUIView(context: Context) -> ClearanceView { ClearanceView() }

    func updateUIView(_ view: ClearanceView, context: Context) {
        view.containerSize = containerSize
    }

    final class ClearanceView: UIView {
        var containerSize: CGSize = .zero {
            didSet { if containerSize != oldValue { setNeedsLayout() } }
        }

        /// The column whose inset this view last gave back.
        private weak var adjustedColumn: UINavigationController?
        private var isRecheckScheduled = false

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
            if window == nil { restoreColumn() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateClearance()
            // The bar lays itself out apart from the columns and may settle
            // after this pass; look again once it has.
            guard !isRecheckScheduled else { return }
            isRecheckScheduled = true
            Task { @MainActor [weak self] in
                self?.isRecheckScheduled = false
                self?.updateClearance()
            }
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            setNeedsLayout()
        }

        private func updateClearance() {
            guard let window, let column = sidebarColumn() else { return }
            if let adjustedColumn, adjustedColumn !== column { restoreColumn() }
            let additional = column.additionalSafeAreaInsets.top
            let safeTop = column.view.safeAreaInsets.top
            // A safe area never goes below zero, so once the inherited inset
            // shrinks under what was given back (the bar settling after
            // launch), the inset in effect no longer says what it inherits.
            // Give nothing back for one pass to read it afresh.
            if safeTop <= 0, additional < 0, window.safeAreaInsets.top > 0 {
                column.additionalSafeAreaInsets.top = 0
                adjustedColumn = nil
                return
            }
            let inherited = safeTop - additional
            let target = givenBackInset(for: column, in: window, inherited: inherited)
            guard abs(target - additional) > 0.5 else { return }
            column.additionalSafeAreaInsets.top = target
            adjustedColumn = target == 0 ? nil : column
        }

        /// The negative inset that returns the tab bar's share of the
        /// column's top safe area, or zero where the bar needs it.
        private func givenBackInset(
            for column: UINavigationController, in window: UIWindow, inherited: CGFloat
        ) -> CGFloat {
            guard let tabs = column.tabBarController,
                tabs.traitCollection.horizontalSizeClass == .regular,
                !tabs.isTabBarHidden
            else { return 0 }
            let columnFrame = column.view.convert(column.view.bounds, to: window)
            let statusBar = window.safeAreaInsets.top
            // A floating card below the window's top keeps its placement.
            guard columnFrame.minY <= statusBar else { return 0 }
            let cleared = statusBar - columnFrame.minY
            guard inherited > cleared,
                let pill = Self.floatingBarPill(in: tabs, window: window, above: inherited)
            else { return 0 }
            let gap: CGFloat = 8
            let meets =
                pill.maxX + gap > columnFrame.minX && pill.minX - gap < columnFrame.maxX
            return meets ? 0 : cleared - inherited
        }

        /// The floating tab bar's visible pill: the outermost chrome views
        /// narrower than the window within the column's top inset. The
        /// bar's own container spans the window, so its width says nothing.
        private static func floatingBarPill(
            in tabs: UITabBarController, window: UIWindow, above limit: CGFloat
        ) -> CGRect? {
            let content = tabs.selectedViewController?.view
            var pill: CGRect?
            func visit(_ view: UIView) {
                guard !view.isHidden, view.alpha > 0.01 else { return }
                let frame = view.convert(view.bounds, to: window)
                if frame.width > 0, frame.height > 0, frame.width < window.bounds.width * 0.9 {
                    if frame.maxY <= limit { pill = pill.map { $0.union(frame) } ?? frame }
                    return
                }
                view.subviews.forEach(visit)
            }
            for chrome in tabs.view.subviews {
                if let content, content.isDescendant(of: chrome) { continue }
                visit(chrome)
            }
            return pill
        }

        /// The navigation controller of the split view column holding this
        /// view.
        private func sidebarColumn() -> UINavigationController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let column = current as? UINavigationController,
                    column.parent is UISplitViewController
                {
                    return column
                }
                responder = current.next
            }
            return nil
        }

        private func restoreColumn() {
            guard let column = adjustedColumn else { return }
            if column.additionalSafeAreaInsets.top != 0 {
                column.additionalSafeAreaInsets.top = 0
            }
            adjustedColumn = nil
        }
    }
}
