import SwiftUI

/// "+4 −8" in the diff's inks, or "Binary". A side with no lines is left
/// out, and a change without line changes shows nothing, unless
/// `showsZeroes` writes them as the Agents list's badge does.
struct ChangesLineCounts: View {
    let counts: LineCounts
    var font: Font = .footnote.weight(.semibold)
    var showsZeroes = false
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    /// The visible text of each side, nil for a side left out. The minus
    /// sign is U+2212.
    static func texts(added: Int, removed: Int, showsZeroes: Bool)
        -> (added: String?, removed: String?)
    {
        (
            added > 0 || showsZeroes ? "+\(added.formatted())" : nil,
            removed > 0 || showsZeroes ? "\u{2212}\(removed.formatted())" : nil
        )
    }

    var body: some View {
        let palette = DiffPalette.current(differentiatingWithoutColor: differentiateWithoutColor)
        Group {
            switch counts {
            case .lines(let added, let removed) where showsZeroes || added > 0 || removed > 0:
                let texts = Self.texts(added: added, removed: removed, showsZeroes: showsZeroes)
                HStack(spacing: 4) {
                    if let added = texts.added {
                        Text(verbatim: added)
                            .foregroundStyle(Color(uiColor: palette.added.ink))
                    }
                    if let removed = texts.removed {
                        Text(verbatim: removed)
                            .foregroundStyle(Color(uiColor: palette.removed.ink))
                    }
                }
            case .lines:
                EmptyView()
            case .binary:
                Text("Binary")
                    .foregroundStyle(.secondary)
            }
        }
        .font(font)
        .monospacedDigit()
        .fixedSize()
    }
}

/// The branch or detached commit, with its upstream and how far the two
/// have moved apart. The upstream moves under the branch when the row is
/// short of room.
struct ChangesBranchRow: View {
    let head: CheckoutHead

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                branch
                Spacer(minLength: 8)
                upstream
            }
            VStack(alignment: .leading, spacing: 4) {
                branch
                upstream
            }
        }
    }

    private var branch: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ChangesHeaderIcon(
                systemName: head.branch == .detached
                    ? "smallcircle.filled.circle" : "arrow.triangle.branch")
            Text(head.branchTitle)
                .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var upstream: some View {
        if let upstream = head.upstream {
            switch upstream.state {
            case .tracking(let ahead, let behind):
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(upstream.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "↑\(ahead.formatted()) ↓\(behind.formatted())")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary))
                }
            case .deleted, .unknown:
                Text(upstream.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The Checkout's line totals, large, beside its file counts.
struct ChangesTotalsRow: View {
    let changes: CheckoutChanges

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                lines
                Spacer(minLength: 8)
                files
            }
            VStack(alignment: .leading, spacing: 4) {
                lines
                files
            }
        }
    }

    /// Zeroes show too: a Checkout with only untracked, binary, or
    /// mode-only changes reads +0 −0 here; its Agents list row counts files.
    @ViewBuilder
    private var lines: some View {
        let totals = changes.totals
        if !totals.linesAreAvailable {
            Text("Line counts unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if !totals.linesAreComplete {
                    Text("At least")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ChangesLineCounts(
                    counts: .lines(added: totals.added, removed: totals.removed),
                    font: .title3.weight(.semibold), showsZeroes: true)
            }
        }
    }

    private var files: some View {
        Text(changes.filesSummary)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A header row's leading symbol, one width for every row so their text
/// lines up.
struct ChangesHeaderIcon: View {
    let systemName: String
    @ScaledMetric(relativeTo: .subheadline) private var width: CGFloat = 18

    var body: some View {
        Image(systemName: systemName)
            .imageScale(.small)
            .foregroundStyle(.secondary)
            .frame(width: width)
            .accessibilityHidden(true)
    }
}
