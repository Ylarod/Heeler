import SwiftUI
import Testing

@testable import Heeler

@Suite("Console sheet presentation")
struct ConsoleSheetPresentationTests {
    @Test func regularWidthUsesFormSizing() {
        #expect(ConsoleSheetPresentation(horizontalSizeClass: .regular) == .form)
    }

    @Test func compactWidthPreservesDestinationSizing() {
        #expect(ConsoleSheetPresentation(horizontalSizeClass: .compact) == .inheritedSheet)
    }

    @Test func unknownSizeClassPreservesDestinationSizing() {
        #expect(ConsoleSheetPresentation(horizontalSizeClass: nil) == .inheritedSheet)
    }

    @MainActor @Test func fittedFormSeedsFromAnUnplacedPageOnlyUntilOneIsPlaced() {
        let fit = ConsoleSheetFit()
        #expect(fit.height == nil)
        fit.report(0, isPlaced: false)
        #expect(fit.height == nil)
        // Laid out against the window, before the sheet placed it.
        fit.report(304.25, isPlaced: false)
        #expect(fit.height == 305)
        fit.report(278.25, isPlaced: false)
        #expect(fit.height == 279)

        fit.report(285.5, isPlaced: true)
        #expect(fit.height == 286)
        // The window's taller insets never outgrow a placed page again.
        fit.report(304.25, isPlaced: false)
        #expect(fit.height == 286)
    }

    @MainActor @Test func fittedFormProposesLessByTheMarginTheSheetAdds() {
        let fit = ConsoleSheetFit()
        fit.report(278.25, isPlaced: false)
        #expect(fit.height == 279)
        // The sheet lays its content out 20 points taller than proposed.
        fit.contentLaidOut(299)
        #expect(fit.height == 279)
        fit.report(285.5, isPlaced: true)
        #expect(fit.height == 266)
        fit.contentLaidOut(286)
        #expect(fit.height == 266)
    }

    @MainActor @Test func fittedFormKeepsTheTallestPage() {
        let fit = ConsoleSheetFit()
        fit.report(300, isPlaced: false)
        fit.contentLaidOut(320)
        fit.report(311.5, isPlaced: true)
        #expect(fit.height == 292)

        // A shorter page pushed on, or content leaving, keeps the height.
        fit.report(283.5, isPlaced: true)
        #expect(fit.height == 292)
        // A taller one grows it, less the same margin.
        fit.report(400, isPlaced: true)
        #expect(fit.height == 380)
    }

    @MainActor @Test func fittedFormIgnoresASheetShorterThanProposed() {
        let fit = ConsoleSheetFit()
        fit.report(300, isPlaced: false)
        fit.report(300, isPlaced: true)
        // Capped by the form's own height: no negative margin.
        fit.contentLaidOut(250)
        #expect(fit.height == 300)
    }

    @MainActor @Test func sheetPageLeavesTheKeyboardOutOfItsHeight() {
        let measure = ConsoleSheetPageMeasure()
        // Unplaced, the window's insets pass through as they are.
        #expect(measure.height(content: 300, bottomInset: 90, isPlaced: false) == 390)
        // Placed: a pinned Retry Now counts.
        #expect(measure.height(content: 300, bottomInset: 76, isPlaced: true) == 376)
        // A keyboard overlapping the sheet does not, while up or after.
        #expect(measure.height(content: 300, bottomInset: 76 + 212, isPlaced: true) == 376)
        #expect(measure.height(content: 300, bottomInset: 76, isPlaced: true) == 376)
        // The page's content still grows it under the keyboard.
        #expect(measure.height(content: 340, bottomInset: 76 + 212, isPlaced: true) == 416)
    }

    @MainActor @Test func sheetPageCountsAPinnedControlThatJoinsAfterAFirstPass() {
        let measure = ConsoleSheetPageMeasure()
        // Opening a Host's own connection sheet, as logged on iPad: a first
        // placed pass before Retry Now joins the inset, then the page is
        // laid out again unplaced with it.
        #expect(measure.height(content: 129, bottomInset: 0, isPlaced: true) == 129)
        #expect(measure.height(content: 181, bottomInset: 90.5, isPlaced: false) == 271.5)
        // Placed again, Retry Now counts rather than covering the page.
        #expect(measure.height(content: 181, bottomInset: 90.5, isPlaced: true) == 271.5)
        // And a keyboard over it still does not.
        #expect(measure.height(content: 181, bottomInset: 90.5 + 212, isPlaced: true) == 271.5)
    }

    @MainActor @Test func fittedFormDoesNotGrowByAKeyboardOverItsPage() {
        let fit = ConsoleSheetFit()
        let measure = ConsoleSheetPageMeasure()
        fit.report(measure.height(content: 407, bottomInset: 20, isPlaced: false), isPlaced: false)
        fit.contentLaidOut(447)
        fit.report(measure.height(content: 407, bottomInset: 20, isPlaced: true), isPlaced: true)
        let resting = fit.height
        #expect(resting == 407)

        for overlap in stride(from: 20, through: 240, by: 20) {
            let page = measure.height(
                content: 407, bottomInset: 20 + CGFloat(overlap), isPlaced: true)
            fit.report(page, isPlaced: true)
            #expect(fit.height == resting)
        }
        fit.report(measure.height(content: 407, bottomInset: 20, isPlaced: true), isPlaced: true)
        #expect(fit.height == resting)
    }

    @Test func attachLinksPopoverPresentsOnlyFromTheControlThatOpenedIt() {
        let chip = AttachLinksOrigin.composerChip
        let floating = AttachLinksOrigin.floatingButton
        #expect(!chip.presents(nil))
        #expect(chip.presents(.composerChip))
        #expect(!floating.presents(.composerChip))
        #expect(floating.presents(.floatingButton))
        #expect(!chip.presents(.floatingButton))

        // A control that is not presenting cannot dismiss the other's popover.
        #expect(floating.dismissing(.composerChip) == .composerChip)
        #expect(chip.dismissing(.composerChip) == nil)
        #expect(chip.dismissing(nil) == nil)
    }
}
