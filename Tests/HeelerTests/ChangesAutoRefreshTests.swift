import Foundation
import Testing

@testable import Heeler

@MainActor
@Suite("Changes automatic refresh", .timeLimit(.minutes(1)))
struct ChangesAutoRefreshTests {
    @Test func leavingWorkingWaitsForTheDebounceThenReadsTheCheckout() async throws {
        let transport = ScriptedTransport()
        let old = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        let new = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(old), .success(new)])
        let clock = ChangesManualSleeper()
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        updates.yield(.init(status: .working, liveUpdatesAvailable: true))
        let store = ChangesStore(
            directory: { "/home/dev/src/app" },
            read: { try await transport.readChanges($0) },
            agentStatus: { stream }, sleep: { try await clock.sleep($0) })
        let following = Task { await store.followAgentStatus() }
        defer { following.cancel(); updates.finish() }
        await store.appear()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 1)
        updates.yield(.init(status: .done, liveUpdatesAvailable: true))
        await Self.drain()
        #expect(await clock.durations == [.milliseconds(300)])
        #expect(store.phase == .loaded(old.changes))
        await clock.fireAll()
        await Self.waitUntil { store.phase == .loaded(new.changes) }
        #expect(await transport.changesReadRequests.count == 2)
    }

    @Test(arguments: [AgentStatus.idle, .blocked, .unknown, .done])
    func everyNonNilExitFromWorkingTriggers(status: AgentStatus) async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(read), .success(read)])
        let clock = ChangesManualSleeper()
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        updates.yield(.init(status: .working, liveUpdatesAvailable: true))
        let store = ChangesStore(
            directory: { "/app" }, read: { try await transport.readChanges($0) },
            agentStatus: { stream }, sleep: { try await clock.sleep($0) })
        defer { store.cancel(); updates.finish() }
        await store.appear()
        await Self.drain()
        updates.yield(.init(status: status, liveUpdatesAvailable: true))
        await Self.drain()
        #expect(await clock.durations.count == 1)
        await clock.fireAll()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 2)
    }

    @Test func baselineDuplicatesNilAndOtherTransitionsNeverTrigger() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(read)])
        let clock = ChangesManualSleeper()
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        let store = ChangesStore(
            directory: { "/app" }, read: { try await transport.readChanges($0) },
            agentStatus: { stream }, sleep: { try await clock.sleep($0) })
        defer { store.cancel(); updates.finish() }
        await store.appear()
        let statuses: [AgentStatus?] = [.done, .idle, .blocked, .idle, .working, .working, nil, .done]
        for status in statuses {
            updates.yield(.init(status: status, liveUpdatesAvailable: true))
            await Self.drain()
        }
        #expect(await clock.durations.isEmpty)
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func repeatedEdgesRestartTheDebounceAndCoalesceOneFollowUp() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(read), .success(read)])
        let localExec = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: localExec)
        let clock = ChangesManualSleeper()
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        updates.yield(.init(status: .working, liveUpdatesAvailable: true))
        let store = ChangesStore(
            directory: { "/app" }, read: { try await transport.readChanges($0) },
            agentStatus: { stream }, sleep: { try await clock.sleep($0) })
        defer { store.cancel(); updates.finish() }
        let appearing = Task { await store.appear() }
        await localExec.waitForEntry()
        for _ in 0..<3 {
            updates.yield(.init(status: .working, liveUpdatesAvailable: true))
            updates.yield(.init(status: .done, liveUpdatesAvailable: true))
            await Self.drain()
        }
        #expect(await clock.durations == Array(repeating: .milliseconds(300), count: 3))
        await clock.fireAll()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 1)
        await localExec.open()
        await appearing.value
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 2)
        #expect(store.phase == .loaded(read.changes))
    }

    @Test func aTimeoutDropsThePendingFollowUpAndDoesNotRetry() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([.failure(TransportError.gitTimedOut)])
        let localExec = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: localExec)
        let clock = ChangesManualSleeper()
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        updates.yield(.init(status: .working, liveUpdatesAvailable: true))
        let store = ChangesStore(
            directory: { "/app" }, read: { try await transport.readChanges($0) },
            agentStatus: { stream }, sleep: { try await clock.sleep($0) })
        defer { store.cancel(); updates.finish() }
        let appearing = Task { await store.appear() }
        await localExec.waitForEntry()
        updates.yield(.init(status: .done, liveUpdatesAvailable: true))
        await Self.drain()
        await clock.fireAll()
        await Self.drain()
        await localExec.open()
        await appearing.value
        await Self.drain()
        #expect(store.phase == .timedOut)
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func leavingCancelsTheDebounceAndReappearanceUsesAFreshBaseline() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(read)])
        let clock = ChangesManualSleeper()
        let first = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        let second = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        var appearances = 0
        first.continuation.yield(.init(status: .working, liveUpdatesAvailable: true))
        second.continuation.yield(.init(status: .done, liveUpdatesAvailable: true))
        let store = ChangesStore(
            directory: { "/app" }, read: { try await transport.readChanges($0) },
            agentStatus: {
                appearances += 1
                return appearances == 1 ? first.stream : second.stream
            }, sleep: { try await clock.sleep($0) })
        let following = Task { await store.followAgentStatus() }
        await store.appear()
        await Self.drain()
        first.continuation.yield(.init(status: .done, liveUpdatesAvailable: true))
        await Self.drain()
        following.cancel()
        await following.value
        await clock.fireAll()
        let reopened = Task { await store.followAgentStatus() }
        defer { reopened.cancel(); second.continuation.finish() }
        await Self.drain()
        #expect(appearances == 2)
        #expect(await clock.durations.count == 1)
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func workingReadKeepsItsTimeAndWarningUntilANonWorkingReadSucceeds() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        await transport.scriptChangesReads([
            .success(read), .failure(TransportError.gitTimedOut), .success(read)
        ])
        let clock = ChangesManualSleeper()
        var now = Date(timeIntervalSince1970: 1_000)
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        updates.yield(.init(status: .working, liveUpdatesAvailable: true))
        let store = ChangesStore(
            directory: { "/app" }, read: { try await transport.readChanges($0) },
            agentStatus: { stream }, sleep: { try await clock.sleep($0) }, now: { now })
        defer { store.cancel(); updates.finish() }
        await store.appear()
        await Self.drain()
        #expect(store.freshness?.readAt == Date(timeIntervalSince1970: 1_000))
        updates.yield(.init(status: .done, liveUpdatesAvailable: true))
        await Self.drain()
        #expect(store.freshness != nil)
        now = Date(timeIntervalSince1970: 2_000)
        await clock.fireAll()
        await Self.waitUntil { store.timedOutKeepingContent }
        #expect(store.freshness?.readAt == Date(timeIntervalSince1970: 1_000))
        await store.refresh()
        #expect(store.readAt == Date(timeIntervalSince1970: 2_000))
        #expect(store.freshness == nil)
    }

    @Test func onlyAnAutomaticListChangeAnnouncesAndKeepsCheckoutIdentity() async throws {
        let transport = ScriptedTransport()
        let old = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        // Keep the Checkout fixed so the list's SwiftUI identity is stable.
        let clean = CheckoutChangesRead(
            changes: CheckoutChanges(
                checkout: old.changes.checkout, head: old.changes.head, files: [],
                isStatusTruncated: false, isMetadataTruncated: false),
            directoryPrefix: old.directoryPrefix)
        await transport.scriptChangesReads([
            .success(old), .success(old), .success(clean), .success(old)
        ])
        let clock = ChangesManualSleeper()
        var announcements: [String] = []
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        updates.yield(.init(status: .working, liveUpdatesAvailable: true))
        let store = ChangesStore(
            directory: { "/app" }, read: { try await transport.readChanges($0) },
            agentStatus: { stream }, sleep: { try await clock.sleep($0) },
            announce: { announcements.append($0) })
        defer { store.cancel(); updates.finish() }
        await store.appear()
        await Self.drain()
        #expect(announcements.isEmpty)
        for expectedAnnouncements in [0, 1] {
            updates.yield(.init(status: .working, liveUpdatesAvailable: true))
            updates.yield(.init(status: .done, liveUpdatesAvailable: true))
            await Self.drain()
            await clock.fireAll()
            await Self.drain()
            #expect(announcements.count == expectedAnnouncements)
        }
        #expect(announcements == ["Checkout Changes updated."])
        #expect(store.checkout == old.changes.checkout)
        await store.refresh()
        #expect(announcements.count == 1)
    }

    @Test func cancellingTheStatusTaskCancelsAnAutomaticReadAndDiscardsItsLateReply() async throws {
        let transport = ScriptedTransport()
        let old = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        let new = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(old), .success(new)])
        let clock = ChangesManualSleeper()
        var announcements: [String] = []
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        updates.yield(.init(status: .working, liveUpdatesAvailable: true))
        let store = ChangesStore(
            directory: { "/app" }, read: { try await transport.readChanges($0) },
            agentStatus: { stream }, sleep: { try await clock.sleep($0) },
            now: { Date(timeIntervalSince1970: 1_000) }, announce: { announcements.append($0) })
        let following = Task { await store.followAgentStatus() }
        await store.appear()
        await Self.drain()
        let localExec = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: localExec)
        updates.yield(.init(status: .done, liveUpdatesAvailable: true))
        await Self.drain()
        await clock.fireAll()
        await localExec.waitForEntry()
        following.cancel()
        await following.value
        #expect(!store.isRefreshing)
        await localExec.open()
        await Self.drain()
        #expect(store.phase == .loaded(old.changes))
        #expect(store.readAt == Date(timeIntervalSince1970: 1_000))
        #expect(announcements.isEmpty)
        updates.finish()
    }

    @Test func edgesDuringAnAutomaticReadProduceOneFollowUp() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        await transport.scriptChangesReads([.success(read), .success(read), .success(read)])
        let clock = ChangesManualSleeper()
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        updates.yield(.init(status: .working, liveUpdatesAvailable: true))
        let store = ChangesStore(
            directory: { "/app" }, read: { try await transport.readChanges($0) },
            agentStatus: { stream }, sleep: { try await clock.sleep($0) })
        defer { store.cancel(); updates.finish() }
        await store.appear()
        await Self.drain()
        let localExec = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: localExec)
        updates.yield(.init(status: .done, liveUpdatesAvailable: true))
        await Self.drain()
        await clock.fireAll()
        await localExec.waitForEntry()
        for _ in 0..<3 {
            updates.yield(.init(status: .working, liveUpdatesAvailable: true))
            updates.yield(.init(status: .blocked, liveUpdatesAvailable: true))
            await Self.drain()
        }
        await clock.fireAll()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 2)
        await localExec.open()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 3)
        #expect(!store.isRefreshing)
    }

    @Test func workingDuringAReadKeepsTheWarningAndUsesTheCompletionTime() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        await transport.scriptChangesReads([.success(read)])
        let localExec = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: localExec)
        let clock = ChangesManualSleeper()
        var now = Date(timeIntervalSince1970: 1_000)
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        updates.yield(.init(status: .idle, liveUpdatesAvailable: true))
        let store = ChangesStore(
            directory: { "/app" }, read: { try await transport.readChanges($0) },
            agentStatus: { stream }, sleep: { try await clock.sleep($0) }, now: { now })
        defer { store.cancel(); updates.finish() }
        let appearing = Task { await store.appear() }
        await localExec.waitForEntry()
        updates.yield(.init(status: .working, liveUpdatesAvailable: true))
        updates.yield(.init(status: .done, liveUpdatesAvailable: true))
        await Self.drain()
        now = Date(timeIntervalSince1970: 2_000)
        await localExec.open()
        await appearing.value
        #expect(store.freshness?.readAt == Date(timeIntervalSince1970: 2_000))
        #expect(!store.isRefreshing)
    }

    @Test func anAutomaticRecoveryFromAFailureAnnouncesTheNewList() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        await transport.scriptChangesReads([.failure(ChangesReadError.incomplete), .success(read)])
        let clock = ChangesManualSleeper()
        var announcements: [String] = []
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        updates.yield(.init(status: .working, liveUpdatesAvailable: true))
        let store = ChangesStore(
            directory: { "/app" }, read: { try await transport.readChanges($0) },
            agentStatus: { stream }, sleep: { try await clock.sleep($0) },
            announce: { announcements.append($0) })
        defer { store.cancel(); updates.finish() }
        await store.appear()
        await Self.drain()
        #expect(store.phase == .incomplete)
        updates.yield(.init(status: .done, liveUpdatesAvailable: true))
        await Self.drain()
        await clock.fireAll()
        await Self.waitUntil { store.phase == .loaded(read.changes) }
        #expect(announcements == ["Checkout Changes updated."])
    }

    @Test func theStatusLoopAndPendingDebounceDoNotKeepTheStoreAlive() async throws {
        let clock = ChangesManualSleeper()
        let read = try ChangesStoreTests.read(GitProbeRecordings.clean)
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        updates.yield(.init(status: .working, liveUpdatesAvailable: true))
        var store: ChangesStore? = ChangesStore(
            directory: { "/app" }, read: { _ in read },
            agentStatus: { stream }, sleep: { try await clock.sleep($0) })
        weak var weakStore = store
        await store?.appear()
        await Self.drain()
        updates.yield(.init(status: .done, liveUpdatesAvailable: true))
        await Self.drain()
        #expect(await clock.durations.count == 1)
        store = nil
        await Self.drain()
        #expect(weakStore == nil)
        await clock.fireAll()
        updates.finish()
    }

    private static func drain() async {
        for _ in 0..<100 { await Task.yield() }
    }

    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        #expect(condition())
    }
}
