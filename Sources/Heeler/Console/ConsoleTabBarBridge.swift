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
/// instead, as the status bar above it does.
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
        var chromeScheme: ColorScheme? {
            didSet {
                guard chromeScheme != oldValue else { return }
                applyChromeScheme()
            }
        }

        private var hasSettledSafeArea = false

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
            guard window != nil else { return }
            applyChromeScheme()
            guard !hasSettledSafeArea else { return }
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
        }
    }
}
