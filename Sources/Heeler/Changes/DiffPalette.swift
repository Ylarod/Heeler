import UIKit

/// Blue additions and mauve removals form their own vocabulary, independent
/// of Agent Status. Opaque washes keep text contrast stable on every surface.
enum DiffPalette {
    static let addedInk = adaptive(light: 0x0B4F8A, dark: 0x9ECDFB)
    static let addedBackground = adaptive(light: 0xEAF3FC, dark: 0x112B41)
    static let removedInk = adaptive(light: 0x8A215B, dark: 0xF1B5D8)
    static let removedBackground = adaptive(light: 0xFBEFF6, dark: 0x3B2032)
    /// Neutral fill for a side-by-side cell that has no line.
    static let blankBackground = UIColor.secondarySystemBackground

    static func ink(for kind: DiffLine.Kind) -> UIColor {
        switch kind {
        case .added: addedInk
        case .removed: removedInk
        case .context: .label
        }
    }

    static func background(for kind: DiffLine.Kind) -> UIColor {
        switch kind {
        case .added: addedBackground
        case .removed: removedBackground
        case .context: .systemBackground
        }
    }

    static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1)
        }
    }
}
