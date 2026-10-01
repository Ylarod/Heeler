import Foundation
import Testing

@testable import Heeler

@Suite("Side-by-side diff rows")
struct SideBySideDiffTests {
    @Test func equalRunsPairIndexWise() {
        let rows = SideBySideDiff.rows(for: hunk([
            line(0, .removed, old: 8, new: nil, "a"),
            line(1, .removed, old: 9, new: nil, "b"),
            line(2, .added, old: nil, new: 8, "c"),
            line(3, .added, old: nil, new: 9, "d"),
        ]))

        #expect(rows.map(\.id) == [0, 1])
        #expect(rows.map(\.left?.text) == ["a", "b"])
        #expect(rows.map(\.right?.text) == ["c", "d"])
    }

    @Test func surplusRemovedLeavesTheAddedSideBlank() {
        let rows = SideBySideDiff.rows(for: hunk([
            line(0, .removed, old: 1, new: nil, "a"),
            line(1, .removed, old: 2, new: nil, "b"),
            line(2, .removed, old: 3, new: nil, "c"),
            line(3, .added, old: nil, new: 1, "d"),
        ]))

        #expect(rows.map(\.id) == [0, 1, 2])
        #expect(rows.map { $0.left?.text } == ["a", "b", "c"])
        #expect(rows.map { $0.right?.text } == ["d", nil, nil])
    }

    @Test func surplusAddedLeavesTheRemovedSideBlank() {
        let rows = SideBySideDiff.rows(for: hunk([
            line(0, .removed, old: 4, new: nil, "a"),
            line(1, .added, old: nil, new: 4, "b"),
            line(2, .added, old: nil, new: 5, "c"),
        ]))

        #expect(rows.map(\.id) == [0, 2])
        #expect(rows.map { $0.left?.text } == ["a", nil])
        #expect(rows.map { $0.right?.text } == ["b", "c"])
    }

    @Test func contextIsOneRowOnBothSidesAndBreaksChangeBlocks() {
        let rows = SideBySideDiff.rows(for: hunk([
            line(0, .removed, old: 1, new: nil, "a"),
            line(1, .context, old: 2, new: 2, "ctx"),
            line(2, .added, old: nil, new: 3, "b"),
        ]))

        #expect(rows.count == 3)
        #expect(rows[0].left?.text == "a")
        #expect(rows[0].right == nil)
        #expect(rows[1].id == 1)
        #expect(rows[1].left?.id == 1)
        #expect(rows[1].right?.id == 1)
        #expect(rows[2].left == nil)
        #expect(rows[2].right?.text == "b")
    }

    @Test func addedThenRemovedStartsANewBlock() {
        let rows = SideBySideDiff.rows(for: hunk([
            line(0, .added, old: nil, new: 1, "b"),
            line(1, .removed, old: 1, new: nil, "a"),
        ]))

        #expect(rows.map { $0.left?.text } == [nil, "a"])
        #expect(rows.map { $0.right?.text } == ["b", nil])
    }

    @Test func newAndDeletedFilesAreOneSided() {
        let added = SideBySideDiff.rows(for: hunk([
            line(0, .added, old: nil, new: 1, "first"),
            line(1, .added, old: nil, new: 2, "second"),
        ]))
        #expect(added.allSatisfy { $0.left == nil && $0.right != nil })

        let removed = SideBySideDiff.rows(for: hunk([
            line(0, .removed, old: 1, new: nil, "first"),
            line(1, .removed, old: 2, new: nil, "second"),
        ]))
        #expect(removed.allSatisfy { $0.left != nil && $0.right == nil })
    }

    @Test func everyUnifiedLineMapsToTheRowThatShowsIt() throws {
        for recording in [GitProbeRecordings.patchSection, GitProbeRecordings.patchMultipleHunks] {
            let patch = try GitProbePatchParsingTests.parse(recording)
            for hunk in patch.files.flatMap(\.hunks) {
                let rows = SideBySideDiff.rows(for: hunk)
                let lineIDs = Set(hunk.lines.map(\.id))
                #expect(Set(rows.map(\.id)).count == rows.count)
                for row in rows {
                    #expect(lineIDs.contains(row.id))
                }
                for line in hunk.lines {
                    #expect(rows.contains { $0.left?.id == line.id || $0.right?.id == line.id })
                }
            }
        }
    }

    @Test func wrappingKeepsEachSidesFullText() {
        let long = String(repeating: "m", count: 300)
        let rows = SideBySideDiff.rows(for: hunk([
            line(0, .removed, old: 4, new: nil, long, missingNewline: true),
            line(1, .added, old: nil, new: 4, "short"),
        ]))

        #expect(rows.count == 1)
        #expect(rows[0].left?.text.count == 300)
        #expect(rows[0].left?.text == long)
        #expect(rows[0].left?.missingNewline == true)
        #expect(rows[0].right?.text == "short")
    }

    @Test func accessibilityReadsRemovedThenAdded() {
        let removed = line(0, .removed, old: 8, new: nil, "old value")
        let added = line(1, .added, old: nil, new: 8, "new value")
        let paired = SideBySideDiff.rows(for: hunk([removed, added]))
        #expect(paired[0].accessibilityLabel == "Removed, line 8: old value. Added, line 8: new value")

        let context = line(2, .context, old: 6, new: 6, "same")
        let contextRow = SideBySideDiff.rows(for: hunk([context]))
        #expect(contextRow[0].accessibilityLabel == "Unchanged, line 6: same")

        let unpaired = SideBySideDiff.rows(for: hunk([removed]))
        #expect(unpaired[0].accessibilityLabel == "Removed, line 8: old value")

        let missing = line(0, .removed, old: 8, new: nil, "old value", missingNewline: true)
        let joined = SideBySideDiff.rows(for: hunk([missing, added]))
        #expect(
            joined[0].accessibilityLabel
                == "Removed, line 8: old value. No newline at end of file. Added, line 8: new value")
        #expect(!joined[0].accessibilityLabel.contains(".."))
    }

    @Test func demoPatchPairsWithBlankCells() throws {
        #if DEBUG && targetEnvironment(simulator)
        let request = FilePatchRequest(
            topLevel: Data("/workspace/storefront".utf8),
            path: Data("Sources/Checkout/PaymentCoordinator.swift".utf8),
            isUntracked: false)
        let patch = try DemoChangesSample.patch(request)
        var sawBlankSide = false
        var sawLongSide = false
        for file in patch.files {
            for hunk in file.hunks {
                for row in SideBySideDiff.rows(for: hunk) {
                    if row.left == nil || row.right == nil { sawBlankSide = true }
                    if (row.left?.text.count ?? 0) > 120 || (row.right?.text.count ?? 0) > 120 {
                        sawLongSide = true
                    }
                }
            }
        }
        #expect(sawBlankSide)
        #expect(sawLongSide)
        #endif
    }

    private func line(
        _ id: Int, _ kind: DiffLine.Kind, old: Int?, new: Int?, _ text: String,
        missingNewline: Bool = false
    ) -> DiffLine {
        DiffLine(
            id: id, kind: kind, oldNumber: old, newNumber: new, text: text,
            missingNewline: missingNewline)
    }

    private func hunk(_ lines: [DiffLine]) -> DiffHunk {
        DiffHunk(
            id: 0, oldStart: 1, oldCount: lines.count, newStart: 1, newCount: lines.count,
            section: "", lines: lines)
    }
}
