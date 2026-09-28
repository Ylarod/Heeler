import Foundation
import Testing

@testable import Heeler

@MainActor
@Suite("Changes store failure states")
struct ChangesStoreFailureStateTests {
    private static func store(_ transport: ScriptedTransport) -> ChangesStore {
        ChangesStore(directory: { "/home/dev/src/app/pkg" }) { request in
            try await transport.readChanges(request)
        }
    }

    @Test func failuresHaveDistinctStatesAndAPullTriesAgain() async throws {
        let cases: [(ChangesReadError, ChangesStore.Phase)] = [
            (.gitMissing, .gitMissing),
            (.gitTooOld("2.16.6"), .gitTooOld("2.16.6")),
            (.notOwnedByAccount, .notOwnedByAccount),
            (.directoryMissing, .directoryMissing),
            (.incomplete, .incomplete),
            (.notAGitWorkingTree, .notAGitWorkingTree),
            (.gitFailed("fatal: unable to read tree object"), .failed("fatal: unable to read tree object")),
            (.unavailable, .failed(ChangesReadError.unavailable.message)),
        ]
        let clean = try ChangesStoreTests.read(GitProbeRecordings.clean)
        for (error, expected) in cases {
            let transport = ScriptedTransport()
            await transport.scriptChangesReads([.success(clean), .failure(error), .success(clean)])
            let store = Self.store(transport)
            await store.appear()
            await store.refresh()
            #expect(store.phase == expected)
            #expect(store.checkout == nil)
            #expect(!store.timedOutKeepingContent)
            #expect(!store.isRefreshing)
            await store.appear()
            #expect(await transport.changesReadRequests.count == 2)
            await store.refresh()
            #expect(store.phase == .loaded(clean.changes))
            #expect(await transport.changesReadRequests.count == 3)
        }
    }

    @Test func aTimedOutFirstReadWaitsForAPullRatherThanRetryingOnAppear() async throws {
        let transport = ScriptedTransport()
        let clean = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.failure(TransportError.gitTimedOut), .success(clean)])
        let store = Self.store(transport)
        await store.appear()
        #expect(store.phase == .timedOut)
        #expect(!store.timedOutKeepingContent)
        await store.appear()
        #expect(store.phase == .timedOut)
        #expect(await transport.changesReadRequests.count == 1)
        await store.refresh()
        #expect(store.phase == .loaded(clean.changes))
        #expect(await transport.changesReadRequests.count == 2)
    }

    @Test func aTimedOutRefreshKeepsTheReadUntilASuccessfulPull() async throws {
        let transport = ScriptedTransport()
        let first = try ChangesStoreTests.read(GitProbeRecordings.subdir)
        let next = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([
            .success(first), .failure(TransportError.gitTimedOut), .success(next),
        ])
        let store = Self.store(transport)
        await store.appear()
        await store.refresh()
        #expect(store.phase == .loaded(first.changes))
        #expect(store.checkout == first.changes.checkout)
        #expect(store.directoryPrefix == first.directoryPrefix)
        #expect(store.timedOutKeepingContent)
        #expect(!store.isRefreshing)
        await store.appear()
        #expect(await transport.changesReadRequests.count == 2)

        let gate = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: gate)
        let pull = Task { await store.refresh() }
        await gate.waitForEntry()
        #expect(store.phase == .loaded(first.changes))
        #expect(store.timedOutKeepingContent)
        #expect(store.isRefreshing)
        await gate.open()
        await pull.value
        #expect(store.phase == .loaded(next.changes))
        #expect(!store.timedOutKeepingContent)
        #expect(!store.isRefreshing)
    }

    @Test func aDifferentFailureReplacesTheKeptReadAndTimeoutNotice() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([
            .success(try ChangesStoreTests.read(GitProbeRecordings.clean)),
            .failure(TransportError.gitTimedOut), .failure(ChangesReadError.directoryMissing),
        ])
        let store = Self.store(transport)
        await store.appear()
        await store.refresh()
        #expect(store.timedOutKeepingContent)
        await store.refresh()
        #expect(store.phase == .directoryMissing)
        #expect(!store.timedOutKeepingContent)
        #expect(store.directoryPrefix.isEmpty)
    }

    @Test func aTruncatedReadKeepsItsPartialStateInTheStore() async throws {
        let transport = ScriptedTransport()
        let partial = try ChangesStoreTests.read(
            GitProbeRecordings.failureStatusWithFiles(2_345, truncated: true))
        await transport.scriptChangesReads([.success(partial)])
        let store = Self.store(transport)
        await store.appear()
        guard case .loaded(let changes) = store.phase else {
            Issue.record("Expected a loaded partial read, got \(store.phase)")
            return
        }
        #expect(changes.isStatusTruncated)
        #expect(changes.files.count == 2_345)
        #expect(changes.listedFiles.count == 2_000)
        #expect(changes.listLimitNotice
            == "Showing \(2_000.formatted()) of more than \(2_345.formatted()) changed files.")
    }
}
