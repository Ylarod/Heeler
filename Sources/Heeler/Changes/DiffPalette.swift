import UIKit

/// The diff's colours. Green additions and red removals follow GitHub. With
/// Differentiate Without Color on, the diff switches to Heeler's blue and
/// mauve, which stay apart under red-green colour blindness. Code keeps the
/// label colour on every row: the sign, the line numbers, the washes, and a
/// changed word's outline carry each change. Opaque washes keep contrast
/// stable on every surface.
struct DiffPalette: Sendable {
    struct Change: Sendable {
        /// The sign, the line numbers, and a changed word's outline.
        let ink: UIColor
        /// The line's wash.
        let line: UIColor
        /// The line-number gutter's deeper wash.
        let gutter: UIColor
        /// A changed word's fill.
        let word: UIColor
    }

    let added: Change
    let removed: Change

    static let github = DiffPalette(
        added: Change(
            ink: adaptive(light: 0x116329, dark: 0x3FB950),
            line: adaptive(light: 0xE6FFEC, dark: 0x0B2411),
            gutter: adaptive(light: 0xCCFFD8, dark: 0x10321A),
            word: adaptive(light: 0xABF2BC, dark: 0x1A5427)),
        removed: Change(
            ink: adaptive(light: 0xB42318, dark: 0xFF7B72),
            line: adaptive(light: 0xFFEBE9, dark: 0x2E1111),
            gutter: adaptive(light: 0xFFD7D5, dark: 0x451918),
            word: adaptive(light: 0xFFC5C0, dark: 0x6E2521)))

    static let blueMauve = DiffPalette(
        added: Change(
            ink: adaptive(light: 0x0B4F8A, dark: 0x9ECDFB),
            line: adaptive(light: 0xEAF3FC, dark: 0x112B41),
            gutter: adaptive(light: 0xD5E7F9, dark: 0x163852),
            word: adaptive(light: 0xB9D8F5, dark: 0x1F4E73)),
        removed: Change(
            ink: adaptive(light: 0x8A215B, dark: 0xF1B5D8),
            line: adaptive(light: 0xFBEFF6, dark: 0x3B2032),
            gutter: adaptive(light: 0xF5DCEA, dark: 0x4A2940),
            word: adaptive(light: 0xEDC0DA, dark: 0x6B3558)))

    /// Code on every row: the label colour at 92% in dark and 88% in light.
    static let code = adaptive(light: 0x000000, lightAlpha: 0.88, dark: 0xFFFFFF, darkAlpha: 0.92)
    /// Context line numbers: the secondary label, raised to 74% in light so
    /// the small digits keep 4.5:1.
    static let contextNumber = adaptive(
        light: 0x3C3C43, lightAlpha: 0.74, dark: 0xEBEBF5, darkAlpha: 0.6)
    static let hunkBand = adaptive(light: 0xF6F8FA, dark: 0x111214)
    /// Hunk band text: the secondary label.
    static let hunkText = contextNumber
    /// The diagonals across a side-by-side cell that has no line.
    static let hatch = adaptive(light: 0x000000, lightAlpha: 0.07, dark: 0xFFFFFF, darkAlpha: 0.06)
    static let background = UIColor.systemBackground

    static func current(differentiatingWithoutColor: Bool) -> DiffPalette {
        differentiatingWithoutColor ? .blueMauve : .github
    }

    func change(_ kind: DiffLine.Kind) -> Change? {
        switch kind {
        case .added: added
        case .removed: removed
        case .context: nil
        }
    }

    /// The sign's and line numbers' colour.
    func ink(for kind: DiffLine.Kind) -> UIColor {
        change(kind)?.ink ?? Self.contextNumber
    }

    func background(for kind: DiffLine.Kind) -> UIColor {
        change(kind)?.line ?? Self.background
    }

    func gutter(for kind: DiffLine.Kind) -> UIColor {
        change(kind)?.gutter ?? Self.background
    }

    static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
        adaptive(light: light, lightAlpha: 1, dark: dark, darkAlpha: 1)
    }

    static func adaptive(
        light: UInt32, lightAlpha: CGFloat, dark: UInt32, darkAlpha: CGFloat
    ) -> UIColor {
        UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let rgb = isDark ? dark : light
            return UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: isDark ? darkAlpha : lightAlpha)
        }
    }
}
