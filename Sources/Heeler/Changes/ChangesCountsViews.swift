import SwiftUI

/// Extra branch context from the display model, independent of a diff view.
struct ChangesHeadDetails: View {
    let head: CheckoutHead

    var body: some View {
        Group {
            if head.isUnborn { Text("No commits yet") }
            if let upstream = head.upstream { Text(upstream.summary) }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ChangesTotalsLine: View {
    let totals: ChangesTotals

    var body: some View {
        Text(totals.summary)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One wrapping detail line keeps counts beside the kind and staging at
/// ordinary sizes, and below them when Dynamic Type needs the width.
struct ChangedFileDetails: View {
    let file: ChangedFile

    var body: some View {
        Text(file.detail + (file.countsSummary.map { " · " + $0 } ?? ""))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }
}
