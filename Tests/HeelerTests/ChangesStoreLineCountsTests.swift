import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Heeler

@MainActor
@Suite("Changes store line counts and header")
struct ChangesStoreLineCountsTests {
    @Test func loadedFilesAndHeaderKeepTrackedCountsSeparateFromUntrackedItems() async throws {
        let changes = try await load(GitProbeRecordings.tracking)
        #expect(changes.files.first { $0.displayPath == "app.txt" }?.lineCounts
            == .lines(added: 3, removed: 1))
        let binary = try #require(changes.files.first { $0.displayPath == "logo.bin" })
        #expect(binary.lineCounts == .binary)
        #expect(binary.countsSummary == "Binary")
        #expect(binary.rowAccessibilityLabel == "logo.bin, modified, staged, binary")
        let new = try #require(changes.files.first { $0.displayPath == "notes.txt" })
        #expect(new.lineCounts == nil)
        #expect(new.countsSummary == "New")
        #expect(new.rowAccessibilityLabel == "notes.txt, untracked")
        #expect(changes.totals.trackedFiles == 2)
        #expect(changes.totals.untrackedItems == 1)
        #expect(changes.totals.summary == "2 files changed · +3 −1 lines · 1 untracked item")
        #expect(changes.totals.accessibilitySummary
            == "2 files changed. 3 lines added, 1 line removed in tracked files. 1 untracked item")
    }

    @Test func theHeaderShowsCommitsAheadAndBehindItsUpstream() async throws {
        let changes = try await load(GitProbeRecordings.tracking)
        #expect(changes.head.upstream?.state == .tracking(ahead: 2, behind: 1))
        #expect(changes.head.upstream?.summary == "origin/main: 2 ahead, 1 behind")
        #expect(summary(changes).contains("2 commits ahead and 1 commit behind origin/main."))
    }

    @Test func aDeletedFilesCountLabelDoesNotDependOnItsRowBeingVisible() async throws {
        let changes = try await load(GitProbeRecordings.hostile)
        let deleted = try #require(changes.files.first { $0.displayPath == "gone.txt" })
        #expect(deleted.rowAccessibilityLabel
            == "gone.txt, deleted, unstaged, 0 lines added, 1 line removed")
    }

    @Test func theHeaderStatesWhenTheUpstreamWasDeleted() async throws {
        let changes = try await load(GitProbeRecordings.upstreamGone)
        #expect(changes.head.upstream?.state == .deleted)
        #expect(changes.head.upstream?.summary == "Upstream origin/feature was deleted")
        #expect(summary(changes).contains("Upstream origin/feature was deleted."))
    }

    @Test func aDetachedHeadKeepsItsCommitAndHasNoUpstream() async throws {
        let changes = try await load(GitProbeRecordings.worktree)
        #expect(changes.head.branch == .detached)
        #expect(changes.head.upstream == nil)
        #expect(!changes.head.isUnborn)
        #expect(summary(changes).contains("Detached at 4f87954."))
        #expect(!summary(changes).contains("No commits yet"))
        #expect(changes.totals.summary == "1 file changed · +1 −0 lines · 0 untracked items")
    }

    @Test func anUnbornCheckoutSaysNoCommitsYetOnBothObjectFormats() async throws {
        for recording in [GitProbeRecordings.unborn, GitProbeRecordings.unbornSHA256] {
            let changes = try await load(recording)
            #expect(changes.head.isUnborn)
            #expect(changes.head.commit == nil)
            #expect(changes.head.latestCommit == nil)
            #expect(summary(changes).contains("Branch main. No commits yet."))
            #expect(changes.files.first { $0.displayPath == "staged.txt" }?.kind == .added)
            #expect(changes.files.first { $0.displayPath == "loose.txt" }?.kind == .untracked)
        }
    }

    @Test func anUnbornCheckoutKeepsItsLiveUpstreamWithoutClaimingDeletion() async throws {
        let changes = try await load(GitProbeRecordings.countsUnbornWithLiveUpstream)
        #expect(changes.head.isUnborn)
        #expect(changes.head.upstream?.state == .unknown)
        #expect(summary(changes).contains("Branch main. No commits yet."))
        #expect(summary(changes).contains("Upstream origin/main, comparison unavailable."))
        #expect(!summary(changes).contains("was deleted"))
        #expect(changes.totals.trackedFiles == 1)
        #expect(changes.totals.untrackedItems == 1)
    }

    @Test func aRefreshReplacesCountsWithoutChangingRowIdentity() async throws {
        let transport = ScriptedTransport()
        let first = try ChangesStoreTests.read(GitProbeRecordings.tracking)
        // Script a subsequent read of the same paths with different counts.
        let updated = Data(String(decoding: GitProbeRecordings.tracking.stdout, as: UTF8.self)
            .replacingOccurrences(of: "3\t1\tapp.txt", with: "5\t2\tapp.txt").utf8)
        let second = try ChangesStoreTests.read((updated, GitProbeRecordings.tracking.stderr))
        await transport.scriptChangesReads([.success(first), .success(second)])
        let store = Self.store(transport)
        await store.appear()
        #expect(store.phase == .loaded(first.changes))
        await store.refresh()
        guard case .loaded(let changes) = store.phase else {
            Issue.record("expected loaded Changes after refresh")
            return
        }
        #expect(changes.files.map(\.id) == first.changes.files.map(\.id))
        #expect(changes.files.first { $0.displayPath == "app.txt" }?.lineCounts
            == .lines(added: 5, removed: 2))
        #expect(changes.totals.added == 5)
        #expect(changes.totals.removed == 2)
        #expect(await transport.changesReadRequests.count == 2)
    }

    @Test func countsProvideDisplayAndVoiceOverTextForTheTooLargeDiffSeam() throws {
        let changes = try ChangesStoreTests.read(GitProbeRecordings.rewrittenRename).changes
        let file = try #require(changes.files.first)
        #expect(file.lineCounts?.summary == "+41 −20 lines")
        #expect(file.lineCounts?.accessibilityLabel == "41 lines added, 20 lines removed")
        #expect(file.rowAccessibilityLabel
            == "new.txt, renamed from old.txt, staged and unstaged, 41 lines added, 20 lines removed")
        #expect(LineCounts.binary.summary == "Binary")
        #expect(LineCounts.binary.accessibilityLabel == "binary")
    }

    @Test(arguments: ["new.txt", "logo.bin"])
    func aTooLargeDiffKeepsItsRecordedCountsInTheVisibleAndVoiceOverFooter(path: String) async throws {
        let recording = path == "new.txt"
            ? GitProbeRecordings.rewrittenRename : GitProbeRecordings.tracking
        let read = try ChangesStoreTests.read(recording)
        let file = try #require(read.changes.files.first { $0.displayPath == path })
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([.success(read)])
        let cut = FilePatch(files: [], isTruncated: true)
        await transport.scriptFilePatchReads([.success(cut), .success(cut)])
        let store = ChangesStore(
            directory: { "/home/dev/src/app" },
            read: { try await transport.readChanges($0) },
            readPatch: { try await transport.readFilePatch($0) })
        await store.appear()
        store.openDiff(file)
        let diff = try #require(store.fileDiff.current)
        await diff.appear()
        #expect(diff.truncation == .canLoadMore)
        await diff.loadMore()
        #expect(diff.truncation == .tooLarge)
        let expected = "This file is too large to display in full. "
            + (path == "new.txt" ? "+41 −20 lines" : "Binary")
        #expect(diff.tooLargeMessage == expected)
        #expect(await transport.filePatchRequests.map(\.limit) == [.initial, .extended])
        #expect(await transport.changesReadRequests.count == 1)

        let controller = UIHostingController(rootView: FileDiffView(store: diff))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874),
            rootViewController: controller)
        defer { window.isHidden = true }
        try #expect(await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains(expected)
        })
    }

    private func load(_ recording: (stdout: Data, stderr: Data)) async throws -> CheckoutChanges {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([.success(try ChangesStoreTests.read(recording))])
        let store = Self.store(transport)
        await store.appear()
        guard case .loaded(let changes) = store.phase else {
            Issue.record("expected loaded Changes, got \(store.phase)")
            throw ChangesReadError.incomplete
        }
        return changes
    }

    private static func store(_ transport: ScriptedTransport) -> ChangesStore {
        ChangesStore(directory: { "/home/dev/src/app" }, read: { request in
            try await transport.readChanges(request)
        })
    }

    private func summary(_ changes: CheckoutChanges) -> String {
        changes.accessibilitySummary(
            relativeTo: Date(timeIntervalSince1970: 1_790_600_000),
            locale: Locale(identifier: "en_US"))
    }
}
