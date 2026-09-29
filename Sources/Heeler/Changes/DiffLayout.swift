import Foundation
import Observation
import SwiftUI
import UIKit

/// How a file diff lays out. Side by Side is the default; Unified is the
/// remembered alternative. The choice is app-wide.
enum DiffLayout: String, CaseIterable, Identifiable, Hashable, Sendable {
    case sideBySide
    case unified

    var id: Self { self }

    var title: String {
        switch self {
        case .sideBySide: "Side by Side"
        case .unified: "Unified"
        }
    }
}

/// Whether the layout control is offered. Below the column threshold it
/// stays on screen, disabled, so the remembered choice is still visible.
enum DiffLayoutToggle: Equatable, Sendable {
    case hidden
    case disabled
    case enabled
}

struct DiffLayoutDecision: Equatable, Sendable {
    var layout: DiffLayout
    var toggle: DiffLayoutToggle
}

/// Column threshold for Side by Side. The usable width excludes the area
/// under a floating sidebar. At the default text size the threshold sits
/// above 1056 pt (a 13-inch iPad landscape beside a sidebar at its 320 pt
/// minimum) and below the full 1376 pt width.
enum DiffLayoutPolicy {
    /// Text columns each side must fit before Side by Side is offered.
    static let minimumColumnsPerSide = 50
    /// Padding, one line-number column, spacing and the glyph, in columns.
    /// About 72 pt at the default size (12 + 4×8 + 8 + 12 + 8).
    static let gutterColumnsPerSide = 7
    /// SF Mono's advance at the 16 pt callout size (0.618 em). The research
    /// note's 10.51 pt at 17 pt is the same ratio. `@ScaledMetric` grows
    /// this with Dynamic Type.
    static let defaultColumnWidth: CGFloat = 9.89

    static func requiredWidth(columnWidth: CGFloat) -> CGFloat {
        CGFloat(2 * (minimumColumnsPerSide + gutterColumnsPerSide)) * columnWidth
    }

    static func usableWidth(width: CGFloat, leadingInset: CGFloat, trailingInset: CGFloat) -> CGFloat {
        width - leadingInset - trailingInset
    }

    static func resolve(
        preference: DiffLayout,
        offersSideBySide: Bool,
        usableWidth: CGFloat,
        columnWidth: CGFloat
    ) -> DiffLayoutDecision {
        guard offersSideBySide else {
            return DiffLayoutDecision(layout: .unified, toggle: .hidden)
        }
        guard usableWidth >= requiredWidth(columnWidth: columnWidth) else {
            return DiffLayoutDecision(layout: .unified, toggle: .disabled)
        }
        return DiffLayoutDecision(layout: preference, toggle: .enabled)
    }
}

/// App-wide Side by Side or Unified choice. A Changes presentation lasts
/// for one Checkout, so the remembered choice lives here rather than on
/// `ChangesStore`. Views read it through the `diffLayoutSettings` environment
/// value, falling back to ``shared`` outside tests and demo mode.
@MainActor
@Observable
final class DiffLayoutSettings {
    private static let defaultsKey = "changes.diff-layout"

    private(set) var layout: DiffLayout
    let offersSideBySide: Bool
    @ObservationIgnored private nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, offersSideBySide: Bool) {
        self.defaults = defaults
        self.offersSideBySide = offersSideBySide
        layout =
            defaults.string(forKey: Self.defaultsKey)
            .flatMap(DiffLayout.init(rawValue:)) ?? .sideBySide
    }

    /// Production value. Tests and demo mode inject their own instance.
    static let shared = DiffLayoutSettings(
        offersSideBySide: UIDevice.current.userInterfaceIdiom == .pad)

    func select(_ layout: DiffLayout) {
        guard layout != self.layout else { return }
        self.layout = layout
        defaults.set(layout.rawValue, forKey: Self.defaultsKey)
    }
}

extension EnvironmentValues {
    @Entry var diffLayoutSettings: DiffLayoutSettings? = nil
}
