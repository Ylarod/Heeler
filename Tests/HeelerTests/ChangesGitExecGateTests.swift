import Foundation
import Testing

@testable import Heeler

@MainActor
@Suite("Changes git exec gate", .timeLimit(.minutes(1)))
struct ChangesGitExecGateTests {
    private static func store(_ transport: ScriptedTransport, gate: GitExecGate?) -> ChangesStore {
        ChangesStore(
            directory: { "/home/dev/src/app" },
            read: { try await transport.readChanges($0) },
            readPatch: { try await transport.readFilePatch($0) },
            listUntrackedDirectory: { try await transport.listUntrackedDirectory($0) },
            gate: gate)
    }

    @Test func twoStoresOnOneHostShareOneExecAndTheWaiterShowsLoading() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        await transport.scriptChangesReads([.success(read), .success(read)])
        let localExec = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: localExec)
        let gate = GitExecGate()
        let first = Self.store(transport, gate: gate)
        let second = Self.store(transport, gate: gate)
        let a = Task { await first.appear() }
        await localExec.waitForEntry()
        let b = Task { await second.appear() }
        await Self.drain()
        #expect(second.phase == .loading)
        #expect(await transport.changesReadRequests.count == 1)
        await localExec.open()
        await a.value
        await b.value
        #expect(first.phase == .loaded(read.changes))
        #expect(second.phase == .loaded(read.changes))
        #expect(await transport.changesReadRequests.count == 2)
    }

    @Test func cancellationDiscardsLateResultsButHoldsTheGateUntilLocalCompletion() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        await transport.scriptChangesReads([.success(read), .success(read)])
        let localExec = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: localExec)
        let gate = GitExecGate()
        let first = Self.store(transport, gate: gate)
        let second = Self.store(transport, gate: gate)
        let a = Task { await first.appear() }
        await localExec.waitForEntry()
        first.cancel()
        let b = Task { await second.appear() }
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 1)
        #expect(first.phase == .loading)
        #expect(second.phase == .loading)
        await localExec.open()
        await a.value
        await b.value
        #expect(first.phase == .loading)
        #expect(first.readAt == nil)
        #expect(second.phase == .loaded(read.changes))
    }

    @Test func cancellingAWaitingStoreNeverEntersTheTransport() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(read)])
        let localExec = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: localExec)
        let gate = GitExecGate()
        let first = Self.store(transport, gate: gate)
        let second = Self.store(transport, gate: gate)
        let a = Task { await first.appear() }
        await localExec.waitForEntry()
        let b = Task { await second.appear() }
        await Self.drain()
        second.cancel()
        await b.value
        await localExec.open()
        await a.value
        #expect(second.phase == .loading)
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func aCancellationAwareLocalExecReleasesTheGateImmediately() async throws {
        let clock = ChangesManualSleeper()
        let gate = GitExecGate()
        let first = ChangesStore(
            directory: { "/app" }, read: { _ in
                try await clock.sleep(.seconds(10))
                throw TransportError.gitTimedOut
            }, gate: gate)
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(read)])
        let second = Self.store(transport, gate: gate)
        let a = Task { await first.appear() }
        for _ in 0..<2_000 {
            if await clock.durations.count == 1 { break }
            await Task.yield()
        }
        #expect(await clock.durations.count == 1)
        let b = Task { await second.appear() }
        first.cancel()
        await a.value
        await b.value
        #expect(first.phase == .loading)
        #expect(second.phase == .loaded(read.changes))
    }

    @Test(arguments: [false, true])
    func aTappedFileWaitsForRefreshAndIsCancelledIfTheCheckoutMoves(moves: Bool) async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        let next = try ChangesStoreTests.read(moves ? GitProbeRecordings.worktree : GitProbeRecordings.hostile)
        await transport.scriptChangesReads([.success(read), .success(next)])
        let patch = FilePatch(files: [], isTruncated: false)
        await transport.scriptFilePatchReads([.success(patch)])
        let store = Self.store(transport, gate: GitExecGate())
        await store.appear()
        let localExec = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: localExec)
        let refreshing = Task { await store.refresh() }
        await localExec.waitForEntry()
        let file = try #require(read.changes.files.first { !$0.isUntrackedDirectory })
        store.openDiff(file)
        let diff = try #require(store.fileDiff.current)
        let opening = Task { await diff.appear() }
        await Self.drain()
        #expect(diff.phase == .loading)
        #expect(await transport.filePatchRequests.isEmpty)
        await localExec.open()
        await refreshing.value
        await opening.value
        if moves {
            #expect(store.fileDiff.current == nil)
            #expect(await transport.filePatchRequests.isEmpty)
        } else {
            #expect(diff.phase == .loaded(patch))
            #expect(await transport.filePatchRequests.count == 1)
        }
    }

    @Test func closingADiffCancelsItsQueuedPatch() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        await transport.scriptChangesReads([.success(read), .success(read)])
        let store = Self.store(transport, gate: GitExecGate())
        await store.appear()
        let localExec = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: localExec)
        let refreshing = Task { await store.refresh() }
        await localExec.waitForEntry()
        store.openDiff(try #require(read.changes.files.first { !$0.isUntrackedDirectory }))
        let diff = try #require(store.fileDiff.current)
        let opening = Task { await diff.appear() }
        await Self.drain()
        store.closeDiff()
        await opening.value
        await localExec.open()
        await refreshing.value
        #expect(diff.phase == .loading)
        #expect(await transport.filePatchRequests.isEmpty)
    }

    private static func drain() async {
        for _ in 0..<100 { await Task.yield() }
    }
}
