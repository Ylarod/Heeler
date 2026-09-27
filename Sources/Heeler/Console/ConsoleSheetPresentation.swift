import SwiftUI

/// Resolve against the presenting view, since a form may itself be compact.
enum ConsoleSheetPresentation: Equatable {
    case form
    case inheritedSheet

    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        self = horizontalSizeClass == .regular ? .form : .inheritedSheet
    }
}

/// A sheet's content under the presentation resolved when it opened. The
/// presenting view's size class can change under an open sheet (a Max
/// iPhone rotating, an iPad window resized); following it would move the
/// sheet's modifiers to their other branch and rebuild its content, losing
/// a pushed page, an open Edit form, and what was typed there. The next
/// sheet opens under the new size class.
struct ConsoleSheetContent<Content: View>: View {
    @State private var presentation: ConsoleSheetPresentation
    private let content: (ConsoleSheetPresentation) -> Content

    init(
        _ presentation: ConsoleSheetPresentation,
        @ViewBuilder content: @escaping (ConsoleSheetPresentation) -> Content
    ) {
        _presentation = State(initialValue: presentation)
        self.content = content
    }

    var body: some View {
        content(presentation)
    }
}

struct ConsoleSheetPresentationModifier: ViewModifier {
    let presentation: ConsoleSheetPresentation
    /// A short destination's form shrinks to its content, which reports its
    /// height with `consoleSheetPage()`.
    var fitsContent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
        case .form:
            if fitsContent {
                content.modifier(ConsoleFittedFormModifier(presentation: presentation))
            } else {
                content.presentationSizing(.form)
            }
        case .inheritedSheet:
            // Keep each destination's existing detents (including Rename's medium sheet).
            content
        }
    }
}

/// A regular-width form sheet no taller than its content, for a short
/// sheet that would otherwise leave most of a form empty; compact width
/// keeps the destination's own sizing. Its pages report their height with
/// `consoleSheetPage()`.
struct ConsoleFittedFormModifier: ViewModifier {
    let presentation: ConsoleSheetPresentation

    @State private var fit = ConsoleSheetFit()

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
        case .form:
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    fit.contentLaidOut($0)
                }
                .frame(idealHeight: fit.height)
                .environment(fit)
                .presentationSizing(ContentFittedFormSizing())
        case .inheritedSheet:
            content
        }
    }
}

/// The sheets a Host's condition opens: one failing Host's connection, and
/// the flat lists' summary of several. On iPhone a bottom sheet that opens
/// partway. In regular width a centered form like the Console's other
/// sheets, opaque so the split view never shows through, and no taller than
/// what it says, so Retry Now sits under the failure rather than a screen
/// away. There it cannot be resized, so it shows no grabber.
struct ConsoleStatusSheetPresentationModifier: ViewModifier {
    let presentation: ConsoleSheetPresentation

    /// Every page of the form, the list and any Host pushed from it, on the
    /// ground the list's rows sit on, so a push never changes the material.
    static let formBackground = Color(uiColor: .systemGroupedBackground)

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
        case .form:
            content
                .modifier(ConsoleFittedFormModifier(presentation: presentation))
                .presentationBackground(Self.formBackground)
        case .inheritedSheet:
            content
                .presentationDetents([.fraction(0.6), .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// How tall a fitted form's pages are unscrolled. A list or scroll view
/// offers the sheet's sizing no height of its own, and a navigation stack
/// sizes to its root whatever is pushed, so each page reports here. The
/// sheet keeps the tallest it has shown: a longer page grows it, and going
/// back or content leaving never shrinks it under the pointer.
@MainActor
@Observable
final class ConsoleSheetFit {
    /// The height the form proposes; nil until a page has reported.
    private(set) var height: CGFloat?
    /// The tallest any page has needed since the sheet placed it.
    @ObservationIgnored private var tallestPage: CGFloat = 0
    /// How much taller than proposed the sheet lays its content out.
    @ObservationIgnored private var margin: CGFloat = 0

    /// A page needs `height`. Until the sheet places a page under a
    /// proposal, reports only seed one: before that a page's insets are the
    /// window's, taller than any the sheet gives it.
    func report(_ height: CGFloat, isPlaced: Bool) {
        guard isPlaced, self.height != nil else {
            if tallestPage == 0, height > 0 { self.height = height.rounded(.up) }
            return
        }
        tallestPage = max(tallestPage, height)
        propose()
    }

    /// The sheet laid its content out `height` tall for the current
    /// proposal. Only a change is reported, so a sheet that stops following
    /// a lower proposal never walks it further down.
    func contentLaidOut(_ height: CGFloat) {
        guard let proposed = self.height else { return }
        margin = max(height - proposed, 0)
        propose()
    }

    private func propose() {
        guard tallestPage > 0 else { return }
        let target = (tallestPage - margin).rounded(.up)
        if abs(target - (height ?? 0)) >= 1 { height = target }
    }
}

extension View {
    /// Reports this scrolling page's unscrolled height, bars and pinned
    /// insets included, to the fitted form around it, if any.
    func consoleSheetPage() -> some View {
        modifier(ConsoleSheetPage())
    }
}

private struct ConsoleSheetPage: ViewModifier {
    private struct Geometry: Equatable {
        let content: CGFloat
        let bottomInset: CGFloat
        let isPlaced: Bool
    }

    @Environment(ConsoleSheetFit.self) private var fit: ConsoleSheetFit?
    @State private var measure = ConsoleSheetPageMeasure()

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Geometry.self) { geometry in
            Geometry(
                content: geometry.contentSize.height + geometry.contentInsets.top,
                bottomInset: geometry.contentInsets.bottom,
                isPlaced: geometry.containerSize.height > 0)
        } action: { _, page in
            let height = measure.height(
                content: page.content, bottomInset: page.bottomInset, isPlaced: page.isPlaced)
            fit?.report(height, isPlaced: page.isPlaced)
        }
    }
}

/// A page's height as its fitted form counts it. A software keyboard over
/// the sheet adds its overlap to the page's bottom inset; counted, it would
/// grow the sheet by the keyboard for good, and feed the keyboard's own
/// layout of the sheet back into its size. So once the sheet places the
/// page, only the least bottom inset it has had counts: its own bars and
/// pinned controls, not the keyboard. A page laid out unplaced again starts
/// over: as a sheet opens, a first placed pass can come before a pinned
/// control joins the inset, and holding to it would leave the control
/// covering the page.
@MainActor
final class ConsoleSheetPageMeasure {
    private var restingBottomInset: CGFloat?

    func height(content: CGFloat, bottomInset: CGFloat, isPlaced: Bool) -> CGFloat {
        guard isPlaced else {
            restingBottomInset = nil
            return content + bottomInset
        }
        let resting = min(restingBottomInset ?? bottomInset, bottomInset)
        restingBottomInset = resting
        return content + resting
    }
}

/// A form sheet's width, and its height unless the content needs less.
struct ContentFittedFormSizing: PresentationSizing {
    func proposedSize(
        for root: PresentationSizingRoot, context: PresentationSizingContext
    ) -> ProposedViewSize {
        let form = FormPresentationSizing.form.proposedSize(for: root, context: context)
        guard let height = form.height else { return form }
        let fitted = root.sizeThatFits(ProposedViewSize(width: form.width, height: nil))
        return ProposedViewSize(width: form.width, height: min(height, fitted.height))
    }
}

