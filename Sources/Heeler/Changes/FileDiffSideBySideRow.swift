import SwiftUI
import UIKit

/// One side-by-side pair. Both cells stretch to the taller side. VoiceOver
/// reads the row as one element: the removed line, then the added line.
struct FileDiffSideBySideRow: View {
    let row: SideBySideRow
    let numberDigits: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            FileDiffSideBySideCell(
                line: row.left, number: row.left?.oldNumber, numberDigits: numberDigits,
                showsContextMenu: showsCellMenu(isLeft: true))
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(width: DiffLayoutPolicy.dividerWidth)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            FileDiffSideBySideCell(
                line: row.right, number: row.right?.newNumber, numberDigits: numberDigits,
                showsContextMenu: showsCellMenu(isLeft: false))
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .top)
        // One menu for the shared context line, covering both columns.
        .modifier(SideBySideCellLineMenu(line: isContextRow ? row.left : nil))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityIdentifier("file-diff-line-\(row.id)")
        .modifier(SideBySideRowReferenceActions(row: row))
    }

    /// A context row is one line drawn twice. Its menu is installed once, on
    /// the row. Every other non-nil cell gets its own menu.
    private var isContextRow: Bool {
        guard let left = row.left, let right = row.right else { return false }
        return left.id == right.id
    }

    private func showsCellMenu(isLeft: Bool) -> Bool {
        guard !isContextRow else { return false }
        return isLeft ? row.left != nil : row.right != nil
    }
}

/// One column of a side-by-side row. `line` is nil for an unpaired side.
/// `number` is the old number on the left and the new number on the right,
/// including for a context line shown on both sides.
struct FileDiffSideBySideCell: View {
    let line: DiffLine?
    let number: Int?
    let numberDigits: Int
    var showsContextMenu: Bool
    @ScaledMetric(relativeTo: .caption) private var digitWidth: CGFloat =
        DiffLayoutPolicy.defaultDigitWidth
    @ScaledMetric(relativeTo: .callout) private var glyphWidth: CGFloat =
        DiffLayoutPolicy.defaultGlyphWidth

    var body: some View {
        Group {
            if let line {
                HStack(alignment: .firstTextBaseline, spacing: DiffLayoutPolicy.stackSpacing) {
                    Text(number.map(String.init) ?? "")
                        .frame(width: digitWidth * CGFloat(numberDigits), alignment: .trailing)
                    Text(line.glyph)
                        .font(.callout.monospaced().weight(.semibold))
                        .frame(width: glyphWidth)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.callout.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if line.missingNewline {
                            Text("No newline at end of file")
                                .font(.caption.italic())
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption.monospaced())
                .foregroundStyle(Color(uiColor: DiffPalette.ink(for: line.kind)))
                .padding(.horizontal, DiffLayoutPolicy.horizontalPadding)
                .padding(.vertical, 3)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: background))
        .modifier(SideBySideCellLineMenu(line: showsContextMenu ? line : nil))
    }

    private var background: UIColor {
        guard let line else { return DiffPalette.blankBackground }
        return DiffPalette.background(for: line.kind)
    }
}

/// Installs a line menu only for a side that owns one. The shared modifier
/// adds nothing when the diff has no reference actions, so an empty menu
/// never lands on a lazy row.
private struct SideBySideCellLineMenu: ViewModifier {
    let line: DiffLine?

    @ViewBuilder func body(content: Content) -> some View {
        if let line {
            content.diffLineContextMenu(line)
        } else {
            content
        }
    }
}

/// Qualified actions on a changed pair. Context and unpaired rows use the
/// unqualified names, and the row stays one accessibility element.
private struct SideBySideRowReferenceActions: ViewModifier {
    let row: SideBySideRow

    @ViewBuilder func body(content: Content) -> some View {
        if let left = row.left, let right = row.right, left.id != right.id {
            content
                .diffLineAccessibilityActions(left, qualifier: "Removed")
                .diffLineAccessibilityActions(right, qualifier: "Added")
        } else if let left = row.left {
            content.diffLineAccessibilityActions(left)
        } else if let right = row.right {
            content.diffLineAccessibilityActions(right)
        } else {
            content
        }
    }
}
