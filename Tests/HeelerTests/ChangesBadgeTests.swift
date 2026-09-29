import Foundation
import Testing
import UIKit

@testable import Heeler

/// The Agent switcher's Changes badge: the line totals the Changes header
/// shows for the same read, and nothing when that read cannot vouch for them.
@MainActor
@Suite("Changes badge")
struct ChangesBadgeTests {
    private static let english = Locale(identifier: "en_US")

    /// The tracking recording with `app.txt` counted as `added`/`removed`;
    /// its binary file and untracked note stay as recorded.
    static func read(added: Int, removed: Int) throws -> CheckoutChangesRead {
        let stdout = Data(
            String(decoding: GitProbeRecordings.tracking.stdout, as: UTF8.self)
                .replacingOccurrences(of: "3\t1\tapp.txt", with: "\(added)\t\(removed)\tapp.txt")
                .utf8)
        return try ChangesStoreTests.read((stdout, GitProbeRecordings.tracking.stderr))
    }

    private static func badge(_ changes: CheckoutChanges) -> ChangesBadge? {
        ChangesBadge(phase: .loaded(changes), timedOutKeepingContent: false)
    }

    @Test func showsTheHeadersLineTotalsForALoadedDirtyCheckout() throws {
        let changes = try Self.read(added: 12, removed: 7).changes
        let badge = try #require(Self.badge(changes))
        #expect(badge.addedText(locale: Self.english) == "+12")
        #expect(badge.removedText(locale: Self.english) == "\u{2212}7")
        #expect(changes.totalsSummary.contains("\(badge.addedText()) \(badge.removedText()) lines"))
        #expect(badge.accessibilityValue == "12 lines added, 7 lines removed")
    }

    @Test func hidesWhenNothingIsReadCleanOrFailed() throws {
        let clean = try ChangesStoreTests.read(GitProbeRecordings.clean).changes
        #expect(clean.isClean)
        let phases: [ChangesStore.Phase] = [
            .loading, .loaded(clean), .notAGitWorkingTree, .failed("fatal: broken"), .gitMissing,
            .gitTooOld("2.10.0"), .notOwnedByAccount, .directoryMissing, .incomplete, .timedOut,
        ]
        for phase in phases {
            #expect(
                ChangesBadge(phase: phase, timedOutKeepingContent: false) == nil,
                "a badge for \(phase)")
        }
    }

    @Test func hidesWhenARefreshTimedOutKeepingTheOldDocument() throws {
        let changes = try Self.read(added: 12, removed: 7).changes
        #expect(ChangesBadge(phase: .loaded(changes), timedOutKeepingContent: true) == nil)
    }

    @Test func hidesWhenLineCountsAreUnavailable() throws {
        var changes = try Self.read(added: 12, removed: 7).changes
        changes.totals.linesAreAvailable = false
        #expect(Self.badge(changes) == nil)
    }

    /// Untracked, binary, and mode-only changes have no line delta, yet the
    /// Checkout is not clean: the badge says +0 −0 as the header does, and
    /// VoiceOver hears what did change.
    @Test func showsZeroesWhenFilesChangedWithoutALineDelta() throws {
        var changes = try Self.read(added: 12, removed: 7).changes
        changes.totals.added = 0
        changes.totals.removed = 0
        let badge = try #require(Self.badge(changes))
        #expect(badge.addedText(locale: Self.english) == "+0")
        #expect(badge.removedText(locale: Self.english) == "\u{2212}0")
        #expect(changes.totalsSummary.contains("\(badge.addedText()) \(badge.removedText()) lines"))
        #expect(
            badge.accessibilityValue
                == "0 lines added, 0 lines removed, 2 files changed, 1 untracked item")

        changes.totals.trackedFiles = 0
        let untrackedOnly = try #require(Self.badge(changes))
        #expect(
            untrackedOnly.accessibilityValue == "0 lines added, 0 lines removed, 1 untracked item")
    }

    @Test func aTruncatedCountReadsAsALowerBound() throws {
        var changes = try Self.read(added: 12, removed: 7).changes
        changes.totals.linesAreComplete = false
        let badge = try #require(Self.badge(changes))
        #expect(badge.addedText(locale: Self.english) == "+12")
        #expect(badge.removedText(locale: Self.english) == "\u{2212}7")
        #expect(badge.accessibilityValue == "At least 12 lines added, 7 lines removed")
    }

    @Test(arguments: [
        (0, "0"), (9_999, "9,999"), (10_000, "10K"), (12_345, "12.3K"), (99_999, "99.9K"),
        (123_456, "123K"), (999_999, "999K"), (1_000_000, "1M"), (1_050_000, "1.05M"),
        (1_234_567, "1.23M"), (999_999_999, "999M"), (Int.max, "999T+"),
    ])
    func compactCountsShortenFromTenThousandWithoutOverstating(value: Int, expected: String) {
        #expect(ChangesBadge.count(value, style: .compact, locale: Self.english) == expected)
        #expect(
            ChangesBadge.count(value, style: .exact, locale: Self.english)
                == value.formatted(.number.locale(Self.english)))
    }

    @Test func compactCountsUseTheLocalesDecimalSeparator() {
        let german = Locale(identifier: "de_DE")
        #expect(ChangesBadge.count(12_345, style: .compact, locale: german) == "12,3K")
        #expect(ChangesBadge.count(9_999, style: .compact, locale: german) == "9.999")
    }

    /// The badge prefers the header's exact numbers; the short form is only
    /// for a row without room, and VoiceOver always hears them exactly.
    @Test func largeTotalsStayExactUntilTheRowAsksForTheShortForm() throws {
        let changes = try Self.read(added: 12_345, removed: 7).changes
        let badge = try #require(Self.badge(changes))
        #expect(badge.addedText(locale: Self.english) == "+12,345")
        #expect(badge.addedText(.compact, locale: Self.english) == "+12.3K")
        #expect(badge.removedText(.compact, locale: Self.english) == "\u{2212}7")
        #expect(badge.accessibilityValue.hasPrefix("\(12_345.formatted()) lines added"))
    }

    @Test func inksMeetTextContrastOnTheRowInEveryAppearance() {
        let appearances: [(String, UITraitCollection)] = [
            ("light", UITraitCollection(userInterfaceStyle: .light)),
            ("dark", UITraitCollection(userInterfaceStyle: .dark)),
            (
                "dark elevated",
                UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: .dark),
                    UITraitCollection(userInterfaceLevel: .elevated),
                ])
            ),
        ]
        for (name, traits) in appearances {
            let ground = Self.rgb(.secondarySystemBackground, traits)
            for (role, ink) in [
                ("added", ChangesBadgePalette.addedInk), ("removed", ChangesBadgePalette.removedInk),
            ] {
                let ratio = Self.contrastRatio(Self.rgb(ink, traits), ground)
                #expect(ratio >= 4.5, "\(role) ink on the \(name) row: \(ratio)")
            }
        }
    }

    private static func rgb(_ color: UIColor, _ traits: UITraitCollection) -> [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue]
    }

    /// WCAG 2 contrast ratio from sRGB components.
    private static func contrastRatio(_ a: [CGFloat], _ b: [CGFloat]) -> CGFloat {
        let (lighter, darker) = luminance(a) > luminance(b)
            ? (luminance(a), luminance(b)) : (luminance(b), luminance(a))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ components: [CGFloat]) -> CGFloat {
        let linear = components.map { channel in
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}
