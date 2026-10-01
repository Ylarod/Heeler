import Foundation
import Testing

@testable import Heeler

@MainActor
@Suite("File diff store", .timeLimit(.minutes(1)))
struct FileDiffStoreTests {
    private static func store(transport: ScriptedTransport) -> ChangesStore {
        ChangesStore(
            directory: { "/home/dev/src/app" },
            read: { try await transport.readChanges($0) },
            readPatch: { try await transport.readFilePatch($0) })
    }

    private static func loadList(transport: ScriptedTransport) async throws -> ChangesStore {
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        await transport.scriptChangesReads([.success(read)])
        let store = Self.store(transport: transport)
        await store.appear()
        return store
    }

    private static let file = ChangedFile(
        path: Data("source.swift".utf8), originalPath: nil,
        kind: .modified, staging: .unstaged)
    private static let patch = FilePatch(files: [], isTruncated: false)

    @Test func openingAFileReadsOnlyItsPatchAndLoadsOnce() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadList(transport: transport)
        let checkout = try #require(store.checkout)
        await transport.scriptFilePatchReads([.success(Self.patch)])
        let gate = ScriptedTransportCallGate()
        defer { Task { await gate.open() } }
        await transport.gateNextFilePatchRead(using: gate)
        store.openDiff(Self.file)
        let diff = try #require(store.fileDiff.current)
        #expect(diff.file.id == Self.file.id)
        #expect(diff.phase == .loading)

        let appearing = Task { await diff.appear() }
        await gate.waitForEntry()
        #expect(diff.phase == .loading)
        #expect(!diff.isRefreshing)
        let requests = await transport.filePatchRequests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.topLevel == checkout.topLevel)
        #expect(request.path == Data("source.swift".utf8))
        #expect(request.originalPath == nil)
        #expect(!request.isUntracked)
        #expect(request.limit.byteCount == 262_144)

        await gate.open()
        await appearing.value
        #expect(diff.phase == .loaded(Self.patch))
        #expect(diff.readAt != nil)
        #expect(!diff.isRefreshing)
        await diff.appear()
        #expect(await transport.filePatchRequests.count == 1)
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func aTruncatedFirstReadCanLoadMoreUpToTheExtendedLimit() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadList(transport: transport)
        let cut = FilePatch(files: [], isTruncated: true)
        await transport.scriptFilePatchReads([.success(cut), .success(cut)])
        store.openDiff(Self.file)
        let diff = try #require(store.fileDiff.current)

        await diff.appear()
        #expect(diff.phase == .loaded(cut))
        #expect(diff.truncation == .canLoadMore)
        await diff.loadMore()
        #expect(diff.phase == .loaded(cut))
        #expect(diff.truncation == .tooLarge)
        #expect(diff.tooLargeMessage == "This file is too large to display in full.")
        #expect(await transport.filePatchRequests.map(\.limit.byteCount) == [262_144, 1_048_576])

        await diff.loadMore()
        #expect(await transport.filePatchRequests.count == 2)
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func loadMoreCanFinishThePatchAndPullResetsItsLimit() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadList(transport: transport)
        let cut = FilePatch(files: [], isTruncated: true)
        await transport.scriptFilePatchReads([
            .success(cut), .success(Self.patch), .success(cut),
        ])
        store.openDiff(Self.file)
        let diff = try #require(store.fileDiff.current)
        await diff.appear()
        await diff.loadMore()
        #expect(diff.truncation == .none)

        let gate = ScriptedTransportCallGate()
        defer { Task { await gate.open() } }
        await transport.gateNextFilePatchRead(using: gate)
        let refreshing = Task { await diff.refresh() }
        await gate.waitForEntry()
        #expect(diff.phase == .loaded(Self.patch))
        #expect(diff.isRefreshing)
        await diff.refresh()
        #expect(await transport.filePatchRequests.count == 3)
        #expect(await transport.changesReadRequests.count == 1)

        await gate.open()
        await refreshing.value
        #expect(diff.phase == .loaded(cut))
        #expect(!diff.isRefreshing)
        #expect(diff.truncation == .canLoadMore)
        #expect(await transport.filePatchRequests.map(\.limit.byteCount) == [262_144, 1_048_576, 262_144])
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func closingDiscardsALateReplyAndReopeningDoesNotWaitForIt() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadList(transport: transport)
        let latePatch = FilePatch(files: [], isTruncated: true)
        await transport.scriptFilePatchReads([.success(latePatch), .success(Self.patch)])
        let gate = ScriptedTransportCallGate()
        defer { Task { await gate.open() } }
        await transport.gateNextFilePatchRead(using: gate)
        store.openDiff(Self.file)
        let oldDiff = try #require(store.fileDiff.current)
        let oldRead = Task { await oldDiff.appear() }
        await gate.waitForEntry()

        store.closeDiff()
        #expect(store.fileDiff.current == nil)
        store.openDiff(Self.file)
        let reopened = try #require(store.fileDiff.current)
        #expect(reopened !== oldDiff)
        await reopened.appear()
        #expect(reopened.phase == .loaded(Self.patch))

        await gate.open()
        await oldRead.value
        #expect(store.fileDiff.current === reopened)
        #expect(reopened.phase == .loaded(Self.patch))
        #expect(oldDiff.phase == .loading)
        #expect(await transport.filePatchRequests.count == 2)
    }

    @Test(arguments: [false, true])
    func cancellingTheCallerOrStoreCancelsItsTransportRead(fromStore: Bool) async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadList(transport: transport)
        let checkout = try #require(store.checkout)
        let readGate = ScriptedTransportCallGate()
        defer { Task { await readGate.open() } }
        let cancellation = ScriptedTransportCallGate()
        let patch = Self.patch
        let diff = FileDiffStore(file: Self.file, checkout: checkout) { _ in
            await withTaskCancellationHandler {
                await readGate.waitUntilOpen()
                return patch
            } onCancel: {
                Task { await cancellation.open() }
            }
        }
        let appearing = Task { await diff.appear() }
        await readGate.waitForEntry()
        if fromStore { diff.cancel() } else { appearing.cancel() }
        await cancellation.waitUntilOpen()
        await readGate.open()
        await appearing.value
        #expect(diff.phase == .loading)
        #expect(diff.readAt == nil)

        await diff.appear()
        #expect(diff.phase == .loaded(patch))
    }

    @Test func cancellingARefreshKeepsTheEarlierPatchAndRejectsItsLateReply() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadList(transport: transport)
        let latePatch = FilePatch(files: [], isTruncated: true)
        await transport.scriptFilePatchReads([
            .success(Self.patch), .success(latePatch), .success(Self.patch),
        ])
        store.openDiff(Self.file)
        let diff = try #require(store.fileDiff.current)
        await diff.appear()
        let firstReadAt = diff.readAt
        let gate = ScriptedTransportCallGate()
        defer { Task { await gate.open() } }
        await transport.gateNextFilePatchRead(using: gate)
        let refreshing = Task { await diff.refresh() }
        await gate.waitForEntry()
        #expect(diff.isRefreshing)

        diff.cancel()
        #expect(!diff.isRefreshing)
        #expect(diff.phase == .loaded(Self.patch))
        #expect(diff.readAt == firstReadAt)
        await diff.refresh()
        await gate.open()
        await refreshing.value
        #expect(diff.phase == .loaded(Self.patch))
        #expect(diff.truncation == .none)
        #expect(await transport.filePatchRequests.count == 3)
    }

    @Test func aFailedRefreshKeepsItsPatchAndReadTimeUntilATryAgainSucceeds() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadList(transport: transport)
        let cut = FilePatch(files: [], isTruncated: true)
        await transport.scriptFilePatchReads([
            .success(cut), .failure(TransportError.gitTimedOut), .success(Self.patch),
        ])
        store.openDiff(Self.file)
        let diff = try #require(store.fileDiff.current)
        await diff.appear()
        let readAt = diff.readAt

        await diff.loadMore()
        #expect(diff.phase == .loaded(cut))
        #expect(diff.readAt == readAt)
        #expect(diff.truncation == .canLoadMore)
        #expect(diff.refreshError == TransportError.gitTimedOut.presentation.explanation)
        #expect(!diff.isRefreshing)
        await diff.appear()
        #expect(await transport.filePatchRequests.count == 2)

        await diff.refresh()
        #expect(diff.phase == .loaded(Self.patch))
        #expect(diff.refreshError == nil)
        #expect(diff.truncation == .none)
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func aFirstReadFailureShowsItsMessageWithoutAnAutomaticRetry() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadList(transport: transport)
        await transport.scriptFilePatchReads([
            .failure(ChangesReadError.gitFailed("fatal: could not read source.swift")),
        ])
        store.openDiff(Self.file)
        let diff = try #require(store.fileDiff.current)
        await diff.appear()
        #expect(diff.phase == .failed("fatal: could not read source.swift"))
        #expect(diff.readAt == nil)
        #expect(diff.refreshError == nil)
        #expect(diff.truncation == .none)
        await diff.appear()
        #expect(await transport.filePatchRequests.count == 1)
    }

    @Test func renamesPassBothRawPathsAndExpandedUntrackedFilesCanOpen() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadList(transport: transport)
        await transport.scriptFilePatchReads([.success(Self.patch), .success(Self.patch)])
        let oldPath = Data([0x6F, 0x6C, 0x64, 0xFF])
        let rename = ChangedFile(
            path: Data("new name.swift".utf8), originalPath: oldPath,
            kind: .renamed, staging: .staged)
        store.openDiff(rename)
        let renamed = try #require(store.fileDiff.current)
        await renamed.appear()
        let renameRequests = await transport.filePatchRequests
        let first = try #require(renameRequests.first)
        #expect(first.path == Data("new name.swift".utf8))
        #expect(first.originalPath == oldPath)
        #expect(!first.isUntracked)

        let child = ChangedFile(
            path: Data("newdir/child.txt".utf8), originalPath: nil,
            kind: .untracked, staging: nil)
        store.openDiff(child)
        let untracked = try #require(store.fileDiff.current)
        await untracked.appear()
        let childRequests = await transport.filePatchRequests
        let second = try #require(childRequests.last)
        #expect(second.path == Data("newdir/child.txt".utf8))
        #expect(second.originalPath == nil)
        #expect(second.isUntracked)
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func anUntrackedDirectoryDoesNotOpenAFilePatch() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadList(transport: transport)
        let directory = ChangedFile(
            path: Data("newdir/".utf8), originalPath: nil,
            kind: .untracked, staging: nil)
        store.openDiff(directory)
        #expect(store.fileDiff.current == nil)
        #expect(await transport.filePatchRequests.isEmpty)
    }

    @Test func aListRefreshKeepsTheOpenFileAndDoesNotReadItAgain() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadList(transport: transport)
        let first = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        let clean = CheckoutChangesRead(
            changes: CheckoutChanges(
                checkout: first.changes.checkout, head: first.changes.head, files: []),
            directoryPrefix: first.directoryPrefix)
        await transport.scriptChangesReads([.success(clean)])
        await transport.scriptFilePatchReads([.success(Self.patch)])
        store.openDiff(Self.file)
        let diff = try #require(store.fileDiff.current)
        await diff.appear()
        let readAt = diff.readAt

        await store.refresh()
        #expect(store.fileDiff.current === diff)
        #expect(diff.phase == .loaded(Self.patch))
        #expect(diff.readAt == readAt)
        #expect(await transport.changesReadRequests.count == 2)
        #expect(await transport.filePatchRequests.count == 1)
    }

    @Test func aDifferentCheckoutClosesTheOpenFileAndDiscardsItsLateReply() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadList(transport: transport)
        let worktree = try ChangesStoreTests.read(GitProbeRecordings.worktree)
        await transport.scriptChangesReads([.success(worktree)])
        await transport.scriptFilePatchReads([.success(Self.patch)])
        let gate = ScriptedTransportCallGate()
        defer { Task { await gate.open() } }
        await transport.gateNextFilePatchRead(using: gate)
        store.openDiff(Self.file)
        let diff = try #require(store.fileDiff.current)
        let appearing = Task { await diff.appear() }
        await gate.waitForEntry()

        await store.refresh()
        #expect(store.checkout?.topLevel == worktree.changes.checkout.topLevel)
        #expect(store.fileDiff.current == nil)
        await gate.open()
        await appearing.value
        #expect(diff.phase == .loading)
    }
}
