import Testing
import UIKit

@testable import Heeler

@MainActor
@Suite("Diff layout policy")
struct DiffLayoutPolicyTests {
    private let column = DiffLayoutPolicy.defaultColumnWidth

    @Test func defaultTextSizeFitsACollapsedThirteenInchButNotBesideItsSidebar() {
        for digits in 1...4 {
            let required = DiffLayoutPolicy.requiredWidth(columnWidth: column, numberDigits: digits)
            #expect(required > 1056)
            #expect(required < 1376)
            #expect(resolve(1376, numberDigits: digits) == DiffLayoutDecision(layout: .sideBySide, toggle: .enabled))
            #expect(resolve(1056, numberDigits: digits) == DiffLayoutDecision(layout: .unified, toggle: .disabled))
            #expect(resolve(996, numberDigits: digits) == DiffLayoutDecision(layout: .unified, toggle: .disabled))
            #expect(resolve(required, numberDigits: digits) == DiffLayoutDecision(layout: .sideBySide, toggle: .enabled))
            #expect(resolve(required - 0.5, numberDigits: digits) == DiffLayoutDecision(layout: .unified, toggle: .disabled))
        }
    }

    @Test func thePortraitThirteenInchStaysUnified() {
        #expect(resolve(1032) == DiffLayoutDecision(layout: .unified, toggle: .disabled))
    }

    @Test func anElevenInchLandscapeWithTheSidebarHiddenFits() {
        #expect(resolve(1210) == DiffLayoutDecision(layout: .sideBySide, toggle: .enabled))
    }

    @Test func theRowGutterPinsTheThreshold() {
        #expect(DiffLayoutPolicy.minimumColumnsPerSide == 50)
        #expect(DiffLayoutPolicy.defaultColumnWidth == 9.89)
        #expect(DiffLayoutPolicy.horizontalPadding == 12)
        #expect(DiffLayoutPolicy.stackSpacing == 8)
        #expect(DiffLayoutPolicy.defaultDigitWidth == 8)
        #expect(DiffLayoutPolicy.defaultGlyphWidth == 12)
        #expect(DiffLayoutPolicy.dividerWidth == 1)
        // 32 pt number + 12 pt glyph + two 8 pt gaps + two 12 pt paddings.
        #expect(DiffLayoutPolicy.sideChrome(digitWidth: 8, glyphWidth: 12, numberDigits: 4) == 84)
        // 2 × (chrome + 50 columns) + the 1 pt divider. 100 × 9.89 is 989.
        #expect(DiffLayoutPolicy.requiredWidth(columnWidth: column, numberDigits: 1) == 1_110)
        #expect(DiffLayoutPolicy.requiredWidth(columnWidth: column, numberDigits: 2) == 1_126)
        #expect(DiffLayoutPolicy.requiredWidth(columnWidth: column, numberDigits: 3) == 1_142)
        #expect(DiffLayoutPolicy.requiredWidth(columnWidth: column, numberDigits: 4) == 1_158)
        let eightDigits = DiffLayoutPolicy.requiredWidth(columnWidth: column, numberDigits: 8)
        #expect(eightDigits > 1_158)
        #expect(eightDigits > 1056)
        #expect(eightDigits < 1376)
    }

    @Test func largerTextFallsBackToUnifiedAtTheColumnThreshold() {
        let callout = UIFontMetrics(forTextStyle: .callout)
        let caption = UIFontMetrics(forTextStyle: .caption1)
        let xxxTraits = UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge)
        let accessibilityTraits = UITraitCollection(preferredContentSizeCategory: .accessibilityLarge)
        let xxxLarge = callout.scaledValue(for: column, compatibleWith: xxxTraits)
        let accessibility = callout.scaledValue(for: column, compatibleWith: accessibilityTraits)
        #expect(xxxLarge > column)
        #expect(accessibility > xxxLarge)
        for traits in [xxxTraits, accessibilityTraits] {
            let scaledColumn = callout.scaledValue(for: column, compatibleWith: traits)
            let scaledGlyph = callout.scaledValue(
                for: DiffLayoutPolicy.defaultGlyphWidth, compatibleWith: traits)
            let scaledDigit = caption.scaledValue(
                for: DiffLayoutPolicy.defaultDigitWidth, compatibleWith: traits)
            for digits in [1, 4] {
                let required = DiffLayoutPolicy.requiredWidth(
                    columnWidth: scaledColumn, digitWidth: scaledDigit, glyphWidth: scaledGlyph,
                    numberDigits: digits)
                #expect(required > 1376)
                #expect(
                    resolve(
                        1376, columnWidth: scaledColumn, digitWidth: scaledDigit,
                        glyphWidth: scaledGlyph, numberDigits: digits)
                        == DiffLayoutDecision(layout: .unified, toggle: .disabled))
            }
        }

        let samples: [CGFloat] = [8, column, xxxLarge, accessibility, 40]
        let required = samples.map { DiffLayoutPolicy.requiredWidth(columnWidth: $0, numberDigits: 4) }
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
        columnWidth: CGFloat? = nil,
        digitWidth: CGFloat = DiffLayoutPolicy.defaultDigitWidth,
        glyphWidth: CGFloat = DiffLayoutPolicy.defaultGlyphWidth,
        numberDigits: Int = 4
    ) -> DiffLayoutDecision {
        DiffLayoutPolicy.resolve(
            preference: preference,
            offersSideBySide: offersSideBySide,
            usableWidth: usableWidth,
            columnWidth: columnWidth ?? column,
            digitWidth: digitWidth,
            glyphWidth: glyphWidth,
            numberDigits: numberDigits)
    }
}
