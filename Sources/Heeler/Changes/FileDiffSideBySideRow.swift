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
                line: row.left, number: row.left?.oldNumber, numberDigits: numberDigits)
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(width: DiffLayoutPolicy.dividerWidth)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            FileDiffSideBySideCell(
                line: row.right, number: row.right?.newNumber, numberDigits: numberDigits)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityIdentifier("file-diff-line-\(row.id)")
    }
}

/// One column of a side-by-side row. `line` is nil for an unpaired side.
/// `number` is the old number on the left and the new number on the right,
/// including for a context line shown on both sides.
struct FileDiffSideBySideCell: View {
    let line: DiffLine?
    let number: Int?
    let numberDigits: Int
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
    }

    private var background: UIColor {
        guard let line else { return DiffPalette.blankBackground }
        return DiffPalette.background(for: line.kind)
    }
}
