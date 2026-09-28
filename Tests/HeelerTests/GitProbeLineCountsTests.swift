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

    @Test func duplicateUnmergedRecordsDoNotDoubleCountOrEraseTheChange() throws {
        // Hand-built variants cover versions that emit a zero conflict record
        // beside its counts; the real against-HEAD recording has just one.
        for body in [
            "0\t0\tconflict.txt\0" + "4\t0\tconflict.txt\0",
            "4\t0\tconflict.txt\0" + "0\t0\tconflict.txt\0",
            "4\t0\tconflict.txt\0" + "4\t0\tconflict.txt\0",
        ] {
            let changes = try read(replacingNumstat(Data(body.utf8)))
            #expect(changes.files.first?.lineCounts == .lines(added: 4, removed: 0))
            #expect(changes.totals.added == 4)
        }
    }

    @Test(arguments: [Int32(0), Int32(141)])
    func aCappedNumstatDropsThePartialRenameAndMarksTotalsAsALowerBound(status: Int32) throws {
        // Hand-built overrun, cut inside the rename's destination path.
        var body = Data("2\t0\tsp ace.txt\0".utf8)
        let partialRename = Data("0\t0\t\0old/name.txt\0pkg/".utf8)
        let padding = GitProbe.Cap.numstat - body.count - partialRename.count - 5
        body.append(Data("0\t0\t".utf8))
        body.append(Data(repeating: UInt8(ascii: "x"), count: padding))
        body.append(0)
        body.append(partialRename)
        body.append(Data("renamed.txt\0".utf8))
        let changes = try read(replacingNumstat(body, status: status))
        #expect(changes.files.first { $0.displayPath == "sp ace.txt" }?.lineCounts
            == .lines(added: 2, removed: 0))
        #expect(changes.files.first { $0.displayPath == "pkg/renamed.txt" }?.lineCounts == nil)
        #expect(changes.files.first { $0.displayPath == "gone.txt" }?.lineCounts == nil)
        #expect(changes.totals.trackedFiles == 20)
        #expect(changes.totals.untrackedItems == 2)
        #expect(changes.totals.added == 2)
        #expect(!changes.totals.linesAreComplete)
        #expect(changes.totals.linesAreAvailable)
        #expect(changes.totals.linesSummary == "At least +2 −0 lines")
        #expect(changes.totals.accessibilitySummary.contains("At least 2 lines added"))
    }

    @Test func aCappedStatusMakesTheVisibleAndVoiceOverHeaderFileCountALowerBound() throws {
        let recording = GitProbeRecordings.tracking
        let frames = GitProbe.Frames(
            stdout: recording.stdout, stderr: recording.stderr, nonce: GitProbeRecordings.nonce)
        let status = try frames.requiredSection(GitProbe.SectionName.status, cap: GitProbe.Cap.status)
        // Cut the real status after app.txt and inside the next record.
        let firstFile = try #require(status.body.range(of: Data("app.txt\0".utf8)))
        let changes = try GitProbe.parseChanges(
            stdout: recording.stdout, stderr: recording.stderr,
            nonce: GitProbeRecordings.nonce, statusCap: firstFile.upperBound + 3).changes

        #expect(changes.isStatusTruncated)
        #expect(changes.files.map(\.displayPath) == ["app.txt"])
        #expect(changes.totals.trackedFiles == 1)
        #expect(changes.totals.added == 3)
        #expect(changes.totals.removed == 1)
        #expect(changes.totalsSummary == "more than 1 file changed · +3 −1 lines · 0 untracked items")
        #expect(changes.accessibilitySummary(
            relativeTo: Date(timeIntervalSince1970: 1_790_600_000), locale: Locale(identifier: "en_US"))
            .contains("more than 1 file changed. 3 lines added, 1 line removed in tracked files."))

        let complete = try read(recording)
        #expect(!complete.isStatusTruncated)
        #expect(complete.totalsSummary == "2 files changed · +3 −1 lines · 1 untracked item")
    }

    @Test func aFailedCountCommandKeepsTheFileListWithoutInventingCounts() throws {
        let changes = try read(replacingNumstat(Data("4\t0\tconflict.txt\0".utf8), status: 128))
        #expect(changes.files.count == 22)
        #expect(changes.files.allSatisfy { $0.lineCounts == nil })
        #expect(!changes.totals.linesAreComplete)
        #expect(!changes.totals.linesAreAvailable)
        #expect(changes.totals.linesSummary == "Line counts unavailable")
        #expect(!changes.totals.accessibilitySummary.contains("0 lines added"))
    }

    @Test func malformedCountsAndAnIncompleteLastRecordStayUnknown() throws {
        // Hand-built corrupt numeric fields, including signs and overflow.
        let body = Data((
            "-\t1\tbin.dat\0-1\t0\tgone.txt\0+1\t0\tadded.txt\0"
            + "999999999999999999999999\t0\t--\0"
            + "1\t0\ttab\tname.txt\0"
            + "2\t0\tsp ace.txt").utf8)
        let changes = try read(replacingNumstat(body))
        #expect(changes.files.first { $0.path == Data("tab\tname.txt".utf8) }?.lineCounts
            == .lines(added: 1, removed: 0))
        for path in ["bin.dat", "gone.txt", "added.txt", "--", "sp ace.txt"] {
            #expect(changes.files.first { $0.displayPath == path }?.lineCounts == nil)
        }
        #expect(changes.totals.added == 1)
        #expect(!changes.totals.linesAreComplete)
    }

    @Test func upstreamHeadersTolerateOrderingAndDoNotMistakeMalformedCountsForDeletion() throws {
        let recording = GitProbeRecordings.tracking
        let stdout = String(decoding: recording.stdout, as: UTF8.self)
        let headers = "# branch.upstream origin/main\0# branch.ab +2 -1\0"
        let reordered = stdout.replacingOccurrences(
            of: headers, with: "# branch.ab +2 -1\0# branch.upstream origin/main\0")
        #expect(try read((Data(reordered.utf8), recording.stderr)).head.upstream?.state
            == .tracking(ahead: 2, behind: 1))
        let invalid = stdout.replacingOccurrences(of: "+2 -1", with: "+two -1")
        let changes = try read((Data(invalid.utf8), recording.stderr))
        #expect(changes.head.upstream?.state == .unknown)
        #expect(changes.head.upstream?.summary == "Upstream origin/main, comparison unavailable")
        #expect(try read(GitProbeRecordings.hostile).head.upstream == nil)
        #expect(try read(GitProbeRecordings.clean).head.upstream == nil)
    }

    @Test func anUnbornHeadDoesNotClaimItsLiveUpstreamWasDeleted() throws {
        let recording = GitProbeRecordings.countsUnbornWithLiveUpstream
        let changes = try read(recording)
        #expect(changes.head.isUnborn)
        #expect(changes.head.upstream?.name == "origin/main")
        #expect(changes.head.upstream?.state == .unknown)
        #expect(changes.head.upstream?.summary == "Upstream origin/main, comparison unavailable")
        #expect(changes.files.first { $0.displayPath == "staged.txt" }?.lineCounts
            == .lines(added: 2, removed: 0))

        // Synthetic ordering variant of the real recording: the unborn
        // header must correct an upstream already seen by the parser.
        let stdout = String(decoding: recording.stdout, as: UTF8.self)
            .replacingOccurrences(of: "# branch.oid (initial)\0", with: "")
            .replacingOccurrences(
                of: "# branch.upstream origin/main\0",
                with: "# branch.upstream origin/main\0# branch.oid (initial)\0")
        #expect(try read((Data(stdout.utf8), recording.stderr)).head.upstream?.state == .unknown)
        #expect(try read(GitProbeRecordings.upstreamGone).head.upstream?.state == .deleted)
    }

    /// Replaces only the numeric section in a real read; altered bytes are
    /// synthetic parser edge cases, not further live-git recordings.
    private func replacingNumstat(
        _ body: Data, status: Int32 = 0
    ) -> (stdout: Data, stderr: Data) {
        let recording = GitProbeRecordings.hostile
        let begin = Data("\n__HEELER_GIT_F00D__ numstat begin\n".utf8)
        let end = Data("\n__HEELER_GIT_F00D__ numstat rc=0\n".utf8)
        let start = recording.stdout.range(of: begin)!.upperBound
        let finish = recording.stdout.range(of: end)!
        var stdout = recording.stdout
        stdout.replaceSubrange(start..<finish.upperBound,
            with: body + Data("\n__HEELER_GIT_F00D__ numstat rc=\(status)\n".utf8))
        return (stdout, recording.stderr)
    }

    private func read(_ recording: (stdout: Data, stderr: Data)) throws -> CheckoutChanges {
        try GitProbe.parseChanges(
            stdout: recording.stdout, stderr: recording.stderr,
            nonce: GitProbeRecordings.nonce).changes
    }
}
