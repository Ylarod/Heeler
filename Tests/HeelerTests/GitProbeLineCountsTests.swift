import Foundation
import Testing

@testable import Heeler

@Suite("GitProbe line counts")
struct GitProbeLineCountsTests {
    @Test func trackedCountsUseRawPathsAndKeepUntrackedItemsSeparate() throws {
        let changes = try read(GitProbeRecordings.hostile)
        let files = Dictionary(uniqueKeysWithValues: changes.files.map { ($0.path, $0) })
        #expect(files[Data("sp ace.txt".utf8)]?.lineCounts == .lines(added: 2, removed: 0))
        #expect(files[Data("gone.txt".utf8)]?.lineCounts == .lines(added: 0, removed: 1))
        #expect(files[Data("conflict.txt".utf8)]?.lineCounts == .lines(added: 4, removed: 0))
        #expect(files[Data("bin.dat".utf8)]?.lineCounts == .binary)
        #expect(files[Data("pkg/renamed.txt".utf8)]?.lineCounts == .lines(added: 0, removed: 0))
        for path in ["tab\tname.txt", "line\nbreak.txt", "中文.txt", "--"] {
            #expect(files[Data(path.utf8)]?.lineCounts == .lines(added: 1, removed: 0))
        }
        #expect(files[Data("newdir/".utf8)]?.lineCounts == nil)
        #expect(files[Data("untracked.txt".utf8)]?.lineCounts == nil)
        #expect(changes.totals.trackedFiles == 20)
        #expect(changes.totals.untrackedItems == 2)
        #expect(changes.totals.added == 21)
        #expect(changes.totals.removed == 1)
        #expect(changes.totals.linesAreComplete)
    }

    @Test func aRewrittenStagedRenameCombinesItsAdditionAndDeletion() throws {
        let changes = try read(GitProbeRecordings.rewrittenRename)
        let file = try #require(changes.files.first)
        #expect(changes.files.count == 1)
        #expect(file.kind == .renamed)
        #expect(file.originalPath == Data("old.txt".utf8))
        #expect(file.lineCounts == .lines(added: 41, removed: 20))
        #expect(changes.totals.trackedFiles == 1)
        #expect(changes.totals.added == 41)
        #expect(changes.totals.removed == 20)
    }

    @Test func anIntentToAddMoveNeverInventsZeroCountsForItsSeparateRows() throws {
        for recording in [
            GitProbeRecordings.intentToAddMove,
            GitProbeRecordings.intentToAddMoveAfterStagedRename,
        ] {
            let changes = try read(recording)
            #expect(changes.files.count == 2)
            #expect(changes.files.allSatisfy { $0.lineCounts == nil })
            // The net difference against HEAD is still an unchanged move.
            #expect(changes.totals.added == 0)
            #expect(changes.totals.removed == 0)
            #expect(changes.totals.linesAreComplete)
        }
    }

    @Test func anUnbornCheckoutCountsAgainstItsOwnEmptyTree() throws {
        let sha1 = try read(GitProbeRecordings.unborn)
        let sha256 = try read(GitProbeRecordings.unbornSHA256)
        #expect(sha1.files.first { $0.displayPath == "staged.txt" }?.lineCounts
            == .lines(added: 1, removed: 0))
        #expect(sha256.files.first { $0.displayPath == "staged.txt" }?.lineCounts
            == .lines(added: 3, removed: 0))
        #expect(sha256.files.first { $0.displayPath == "blob.bin" }?.lineCounts == .binary)
        for changes in [sha1, sha256] {
            #expect(changes.files.first { $0.displayPath == "staged.txt" }?.kind == .added)
            #expect(changes.files.first { $0.displayPath == "loose.txt" }?.lineCounts == nil)
            #expect(changes.totals.untrackedItems == 1)
            #expect(changes.totals.linesAreComplete)
        }
    }

    private func read(_ recording: (stdout: Data, stderr: Data)) throws -> CheckoutChanges {
        try GitProbe.parseChanges(
            stdout: recording.stdout, stderr: recording.stderr,
            nonce: GitProbeRecordings.nonce).changes
    }
}
