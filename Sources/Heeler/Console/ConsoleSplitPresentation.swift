import SwiftUI

/// Layout policy uses scene bounds; the split style itself stays constant.
struct ConsoleSplitPresentation: Equatable {
    struct ColumnWidth: Equatable {
        let minimum: CGFloat
        let ideal: CGFloat
        let maximum: CGFloat?
    }

    let hasUsableSize: Bool
    let usesRegularColumns: Bool
    let isLandscape: Bool
    let defaultVisibility: NavigationSplitViewVisibility
    let sidebarWidth: ColumnWidth

    init(
        horizontalSizeClass: UserInterfaceSizeClass?, size: CGSize,
        safeAreaInsets: EdgeInsets = EdgeInsets()
    ) {
        let width = size.width + safeAreaInsets.leading + safeAreaInsets.trailing
        let height = size.height + safeAreaInsets.top + safeAreaInsets.bottom
        // Insets must not turn an initial zero-sized layout pass into a valid seed.
        hasUsableSize = size.width > 0 && size.height > 0
            && width.isFinite && height.isFinite
        usesRegularColumns = horizontalSizeClass == .regular
        isLandscape = hasUsableSize && width > height
        guard hasUsableSize, horizontalSizeClass == .regular else {
            defaultVisibility = .automatic
            sidebarWidth = ColumnWidth(minimum: 320, ideal: 380, maximum: nil)
            return
        }
        if isLandscape {
            defaultVisibility = .all
            sidebarWidth = ColumnWidth(minimum: 320, ideal: 380, maximum: 440)
        } else {
            defaultVisibility = .detailOnly
            sidebarWidth = ColumnWidth(minimum: 320, ideal: 380, maximum: 400)
        }
    }
}

/// Only user deviations from a layout default carry across policy changes.
struct ConsoleSplitVisibilityState {
    private(set) var visibility: NavigationSplitViewVisibility = .automatic
    private(set) var userVisibility: NavigationSplitViewVisibility?
    private(set) var reportedSidebarVisibility: Bool?
    private var appliedPresentation: ConsoleSplitPresentation?

    /// A concrete report wins; an applied concrete request is the fallback when
    /// SwiftUI does not echo programmatic visibility changes through the binding.
    var isSidebarVisible: Bool? {
        reportedSidebarVisibility ?? Self.sidebarVisibility(for: visibility)
    }

    var showsAgentsAction: Bool { isSidebarVisible != true }

    mutating func update(from presentation: ConsoleSplitPresentation) {
        guard presentation.hasUsableSize, presentation != appliedPresentation else { return }
        reportedSidebarVisibility = nil
        appliedPresentation = presentation
        visibility = userVisibility ?? presentation.defaultVisibility
    }

    mutating func systemDidChangeVisibility(
        _ newVisibility: NavigationSplitViewVisibility,
        presentation: ConsoleSplitPresentation
    ) {
        // A callback from a different layout must not pin the outgoing column state.
        guard presentation.hasUsableSize, presentation == appliedPresentation else { return }
        reportedSidebarVisibility = Self.sidebarVisibility(for: newVisibility)
        let changed = visibility != newVisibility
        visibility = newVisibility
        // Automatic is a policy, not a report that the sidebar is visible.
        // Compact stack navigation also must not become a regular-width preference.
        // A same-value acknowledgement in portrait must not erase a landscape hide.
        if changed, presentation.usesRegularColumns, reportedSidebarVisibility != nil {
            userVisibility = newVisibility == presentation.defaultVisibility ? nil : newVisibility
        }
    }

    mutating func showSidebar() {
        guard showsAgentsAction else { return }
        visibility = .all
        reportedSidebarVisibility = nil
        userVisibility = appliedPresentation?.defaultVisibility == .all ? nil : .all
    }

    /// A pick from the sidebar that portrait shows only on request returns
    /// to the detail alone, as a pick on iPhone pushes to it: side by side,
    /// the terminal would keep only what the sidebar leaves of the width.
    mutating func selectionDidOpenDetail() {
        guard let appliedPresentation, appliedPresentation.usesRegularColumns,
            appliedPresentation.defaultVisibility == .detailOnly,
            isSidebarVisible == true
        else { return }
        visibility = .detailOnly
        reportedSidebarVisibility = nil
        userVisibility = nil
    }

    private static func sidebarVisibility(for visibility: NavigationSplitViewVisibility) -> Bool? {
        switch visibility {
        case .all, .doubleColumn: true
        case .detailOnly: false
        default: nil
        }
    }
}
