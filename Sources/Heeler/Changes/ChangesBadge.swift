import Foundation
import UIKit

/// The Agent switcher's glance at the Checkout's Changes: the line totals of
/// the latest read, the same numbers the Changes header shows for it. Nil
/// whenever that read cannot vouch for them: nothing read yet, a clean
/// Checkout, a failed read, a refresh that timed out keeping older content,
/// or line counts git could not produce.
///
/// A count that is only a lower bound keeps its visible text and says
/// "At least" to VoiceOver alone: the header carries the visible qualifier,
/// and the badge has no room for one.
struct ChangesBadge: Equatable {
    /// How a count is written: exactly as the header writes it, or shortened
    /// from 10,000 when the switcher row has no room for the exact form.
    enum Style: CaseIterable {
        case exact
        case compact
    }

    let totals: ChangesTotals
    /// The Host capped its status output, so file counts are lower bounds.
    let isStatusTruncated: Bool

    init?(phase: ChangesStore.Phase, timedOutKeepingContent: Bool) {
        guard case .loaded(let changes) = phase, !timedOutKeepingContent, !changes.isClean,
            changes.totals.linesAreAvailable
        else { return nil }
        totals = changes.totals
        isStatusTruncated = changes.isStatusTruncated
    }

    func addedText(_ style: Style = .exact, locale: Locale = .current) -> String {
        "+" + Self.count(totals.added, style: style, locale: locale)
    }

    /// The minus sign is U+2212, as in the header.
    func removedText(_ style: Style = .exact, locale: Locale = .current) -> String {
        "\u{2212}" + Self.count(totals.removed, style: style, locale: locale)
    }

    /// Always exact. Zero lines on both sides is still a dirty Checkout
    /// (untracked, binary, or mode-only changes), so it also says which
    /// files changed rather than sounding clean.
    var accessibilityValue: String {
        var parts = [
            (totals.linesAreComplete ? "" : "At least ")
                + LineCounts.lines(added: totals.added, removed: totals.removed).accessibilityLabel
        ]
        if totals.added == 0, totals.removed == 0 {
            if totals.trackedFiles > 0 || totals.untrackedItems == 0 {
                parts.append((isStatusTruncated ? "more than " : "") + totals.filesSummary)
            }
            if totals.untrackedItems > 0 { parts.append(totals.untrackedSummary) }
        }
        return parts.joined(separator: ", ")
    }

    /// Exact counts are grouped as the header groups them. Compact counts
    /// from 10,000 keep at most three significant digits, rounded toward
    /// zero so they never overstate: 12.3K, 999K, 1.23M.
    static func count(_ value: Int, style: Style, locale: Locale) -> String {
        guard style == .compact, value >= 10_000,
            let unit = compactUnits.first(where: { value >= $0.scale })
        else { return value.formatted(.number.locale(locale)) }
        let whole = value / unit.scale
        // Past the largest unit; only an overflowed total gets here.
        guard whole < 1_000 else { return "999\(unit.suffix)+" }
        var digits = whole >= 100 ? 0 : whole >= 10 ? 1 : 2
        var fraction = (value % unit.scale) / (unit.scale / powerOfTen(digits))
        while digits > 0, fraction % 10 == 0 {
            fraction /= 10
            digits -= 1
        }
        guard digits > 0 else { return "\(whole)\(unit.suffix)" }
        let fractionText = String(fraction)
        let padding = String(repeating: "0", count: max(0, digits - fractionText.count))
        return "\(whole)\(locale.decimalSeparator ?? ".")\(padding)\(fractionText)\(unit.suffix)"
    }

    private static let compactUnits: [(scale: Int, suffix: String)] = [
        (1_000_000_000_000, "T"), (1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K"),
    ]

    private static func powerOfTen(_ exponent: Int) -> Int {
        (0..<exponent).reduce(1) { value, _ in value * 10 }
    }
}

/// Green additions and red removals, as a VS Code diff summary shows them,
/// by the user's choice. That departs from the rest of Changes: diff lines
/// keep their blue and mauve, independent of Agent Status (`DiffPalette`),
/// while the status chips beside the badge use green for Done and red for
/// Blocked. So these inks are not the status palette's hues, and the leading
/// + and − carry the meaning on their own; colour is never the only channel.
/// Each ink keeps at least 4.5:1 on the switcher row's
/// `secondarySystemBackground` in light, dark, and dark elevated appearances.
enum ChangesBadgePalette {
    static let addedInk = DiffPalette.adaptive(light: 0x116329, dark: 0x3FB950)
    static let removedInk = DiffPalette.adaptive(light: 0xB42318, dark: 0xFF7B72)
}
