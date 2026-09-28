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

    private func read(_ recording: (stdout: Data, stderr: Data)) throws -> CheckoutChanges {
        try GitProbe.parseChanges(
            stdout: recording.stdout, stderr: recording.stderr,
            nonce: GitProbeRecordings.nonce).changes
    }
}
