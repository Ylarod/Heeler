import Testing
import UIKit

@testable import Heeler

@MainActor
@Suite("Diff layout policy")
struct DiffLayoutPolicyTests {
    private let column = DiffLayoutPolicy.defaultColumnWidth

    @Test func defaultTextSizeFitsACollapsedThirteenInchButNotBesideItsSidebar() {
        let required = DiffLayoutPolicy.requiredWidth(columnWidth: column)
        #expect(required > 1056)
        #expect(required < 1376)
        #expect(resolve(1376) == DiffLayoutDecision(layout: .sideBySide, toggle: .enabled))
        #expect(resolve(1056) == DiffLayoutDecision(layout: .unified, toggle: .disabled))
        #expect(resolve(996) == DiffLayoutDecision(layout: .unified, toggle: .disabled))
        #expect(resolve(required) == DiffLayoutDecision(layout: .sideBySide, toggle: .enabled))
        #expect(resolve(required - 0.5) == DiffLayoutDecision(layout: .unified, toggle: .disabled))
    }

    @Test func thePortraitThirteenInchStaysUnified() {
        #expect(resolve(1032) == DiffLayoutDecision(layout: .unified, toggle: .disabled))
    }

    @Test func anElevenInchLandscapeWithTheSidebarHiddenFits() {
        #expect(resolve(1210) == DiffLayoutDecision(layout: .sideBySide, toggle: .enabled))
    }

    @Test func columnCountsPinTheThreshold() {
        #expect(DiffLayoutPolicy.minimumColumnsPerSide == 50)
        #expect(DiffLayoutPolicy.gutterColumnsPerSide == 7)
        #expect(DiffLayoutPolicy.defaultColumnWidth == 9.89)
        #expect(DiffLayoutPolicy.requiredWidth(columnWidth: 10) == 1_140)
    }

    @Test func largerTextFallsBackToUnifiedAtTheColumnThreshold() {
        let metrics = UIFontMetrics(forTextStyle: .callout)
        let xxxLarge = metrics.scaledValue(
            for: column,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge))
        let accessibility = metrics.scaledValue(
            for: column,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityLarge))
        #expect(xxxLarge > column)
        #expect(accessibility > xxxLarge)
        #expect(DiffLayoutPolicy.requiredWidth(columnWidth: xxxLarge) > 1376)
        #expect(DiffLayoutPolicy.requiredWidth(columnWidth: accessibility) > 1376)
        for scaled in [xxxLarge, accessibility] {
            #expect(
                resolve(1376, columnWidth: scaled)
                    == DiffLayoutDecision(layout: .unified, toggle: .disabled))
        }

        let samples: [CGFloat] = [8, column, xxxLarge, accessibility, 40]
        let required = samples.map { DiffLayoutPolicy.requiredWidth(columnWidth: $0) }
        for pair in zip(required, required.dropFirst()) {
            #expect(pair.0 < pair.1)
        }
    }

    @Test func unifiedPreferenceWinsWhereSideBySideWouldFit() {
        #expect(
            resolve(1376, preference: .unified)
                == DiffLayoutDecision(layout: .unified, toggle: .enabled))
    }

    @Test func aPhoneNeverOffersTheToggle() {
        for width: CGFloat in [1376, 402] {
            for preference in DiffLayout.allCases {
                #expect(
                    resolve(width, preference: preference, offersSideBySide: false)
                        == DiffLayoutDecision(layout: .unified, toggle: .hidden))
            }
        }
    }

    @Test func usableWidthExcludesSafeAreaInsets() {
        #expect(DiffLayoutPolicy.usableWidth(width: 1376, leadingInset: 380, trailingInset: 0) == 996)
        #expect(DiffLayoutPolicy.usableWidth(width: 1376, leadingInset: 320, trailingInset: 0) == 1056)
    }

    private func resolve(
        _ usableWidth: CGFloat,
        preference: DiffLayout = .sideBySide,
        offersSideBySide: Bool = true,
        columnWidth: CGFloat? = nil
    ) -> DiffLayoutDecision {
        DiffLayoutPolicy.resolve(
            preference: preference,
            offersSideBySide: offersSideBySide,
            usableWidth: usableWidth,
            columnWidth: columnWidth ?? column)
    }
}
