import Foundation
import Testing

@testable import Heeler

@Suite("Changes transport seam")
struct ChangesTransportSeamTests {
    /// Transports that cannot run git on a Host compile without a Changes
    /// implementation and say so, rather than inventing an empty Checkout.
    @Test func aTransportWithoutGitReportsChangesUnavailable() async {
        let transport = FakeTransport(
            pingResult: .success(ServerInfo(version: "0.9.0", protocolVersion: 22)))
        await #expect(throws: ChangesReadError.unavailable) {
            _ = try await transport.readChanges(ChangesReadRequest(directory: "/home/dev"))
        }
    }
}

/// The Changes store over the scripted Transport. Replies are parsed from
/// the recorded GitProbe output, so the documents are what a real Host sends.
@MainActor
@Suite("Changes store")
struct ChangesStoreTests {
    static func read(_ recording: (stdout: Data, stderr: Data)) throws -> CheckoutChangesRead {
        try GitProbe.parseChanges(
            stdout: recording.stdout, stderr: recording.stderr,
            nonce: GitProbeRecordings.nonce)
    }

    private static func store(
        transport: ScriptedTransport,
        directory: @escaping @MainActor () -> String? = { "/home/dev/src/app" }
    ) -> ChangesStore {
        ChangesStore(directory: directory) { request in
            try await transport.readChanges(request)
        }
    }

    @Test func theFirstReadGoesFromLoadingToLoaded() async throws {
        let transport = ScriptedTransport()
        let hostile = try Self.read(GitProbeRecordings.hostile)
        await transport.scriptChangesReads([.success(hostile)])
        let gate = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: gate)
        let store = Self.store(transport: transport)
        #expect(store.phase == .loading)

        let appearing = Task { await store.appear() }
        await gate.waitForEntry()
        #expect(store.phase == .loading)
        #expect(!store.isRefreshing)

        await gate.open()
        await appearing.value
        #expect(store.phase == .loaded(hostile.changes))
        #expect(!store.isRefreshing)
        #expect(
            await transport.changesReadRequests
                == [ChangesReadRequest(directory: "/home/dev/src/app")])

        // Appearing again (returning from elsewhere in the view) reads nothing.
        await store.appear()
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func aCleanCheckoutLoadsAsClean() async throws {
        let transport = ScriptedTransport()
        let clean = try Self.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(clean)])
        let store = Self.store(transport: transport)

        await store.appear()

        guard case .loaded(let changes) = store.phase else {
            Issue.record("expected a loaded document, got \(store.phase)")
            return
        }
        #expect(changes.isClean)
        #expect(ChangesStore.cleanMessage == "No uncommitted changes")
    }

    @Test func aDirectoryOutsideAnyWorkingTreeShowsItsOwnState() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([.failure(ChangesReadError.notAGitWorkingTree)])
        let store = Self.store(transport: transport, directory: { "/home/dev/plain" })

        await store.appear()

        #expect(store.phase == .notAGitWorkingTree)
        #expect(store.checkout == nil)
    }

    @Test func aRefreshKeepsTheContentAndItsIdentityWhileItRuns() async throws {
        let transport = ScriptedTransport()
        let first = try Self.read(GitProbeRecordings.hostile)
        let second = try Self.read(GitProbeRecordings.subdir)
        let cleaned = CheckoutChanges(
            checkout: second.changes.checkout, head: second.changes.head,
            files: Array(second.changes.files.dropFirst()))
        await transport.scriptChangesReads([
            .success(first), .success(CheckoutChangesRead(changes: cleaned, directoryPrefix: Data())),
        ])
        let store = Self.store(transport: transport)
        await store.appear()
        let identity = try #require(store.checkout)

        let gate = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: gate)
        let refreshing = Task { await store.refresh() }
        await gate.waitForEntry()
        #expect(store.phase == .loaded(first.changes))
        #expect(store.isRefreshing)

        await gate.open()
        await refreshing.value
        #expect(store.phase == .loaded(cleaned))
        #expect(!store.isRefreshing)
        #expect(store.checkout == identity)
    }

    /// The Agent moved into another Checkout between reads: the next read
    /// uses its current directory and the whole document is replaced.
    @Test func aReadResolvingAnotherCheckoutReplacesTheDocument() async throws {
        let transport = ScriptedTransport()
        let main = try Self.read(GitProbeRecordings.hostile)
        let worktree = try Self.read(GitProbeRecordings.worktree)
        await transport.scriptChangesReads([.success(main), .success(worktree)])
        let directory = DirectoryBox("/home/dev/src/app")
        let store = Self.store(transport: transport, directory: { directory.value })
        await store.appear()
        let before = try #require(store.checkout)

        directory.value = "/home/dev/src/app-wt/src"
        await store.refresh()

        #expect(store.phase == .loaded(worktree.changes))
        let after = try #require(store.checkout)
        #expect(after != before)
        #expect(after.isLinkedWorktree)
        #expect(
            await transport.changesReadRequests.map(\.directory)
                == ["/home/dev/src/app", "/home/dev/src/app-wt/src"])
    }

    @Test func aReadFindingNoCheckoutReplacesTheDocument() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([
            .success(try Self.read(GitProbeRecordings.hostile)),
            .failure(ChangesReadError.notAGitWorkingTree),
        ])
        let store = Self.store(transport: transport)
        await store.appear()
        await store.refresh()
        #expect(store.phase == .notAGitWorkingTree)
        #expect(store.checkout == nil)
    }

    @Test func aGitFailureShowsGitsOwnFirstLine() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([
            .failure(ChangesReadError.gitFailed("fatal: bad config line 3 in file .git/config"))
        ])
        let store = Self.store(transport: transport)
        await store.appear()
        #expect(store.phase == .failed("fatal: bad config line 3 in file .git/config"))
    }

    /// Leaving mid-read cancels it; nothing is shown from it, and the next
    /// appearance reads again rather than trusting a read that never landed.
    @Test func aCancelledFirstReadIsReadAgainOnTheNextAppearance() async throws {
        let transport = ScriptedTransport()
        let clean = try Self.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([
            .failure(TransportError.cancelled), .success(clean),
        ])
        let store = Self.store(transport: transport)
        await store.appear()
        #expect(store.phase == .loading)
        await store.appear()
        #expect(store.phase == .loaded(clean.changes))
    }

    @Test func aPullDuringARunningReadStartsNoSecondRead() async throws {
        let transport = ScriptedTransport()
        let clean = try Self.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(clean), .success(clean)])
        let gate = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: gate)
        let store = Self.store(transport: transport)
        let appearing = Task { await store.appear() }
        await gate.waitForEntry()

        await store.refresh()
        #expect(await transport.changesReadRequests.count == 1)

        await gate.open()
        await appearing.value
        #expect(store.phase == .loaded(clean.changes))
    }

    /// Two Agents in one Checkout, one in a subdirectory: both show the
    /// Checkout's Changes, and nothing in the header names an Agent.
    @Test func twoAgentsInOneCheckoutShowIdenticalChanges() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([
            .success(try Self.read(GitProbeRecordings.hostile)),
            .success(try Self.read(GitProbeRecordings.subdir)),
        ])
        let atTop = Self.store(transport: transport, directory: { "/home/dev/src/app" })
        let inPackage = Self.store(transport: transport, directory: { "/home/dev/src/app/pkg" })
        await atTop.appear()
        await inPackage.appear()

        guard case .loaded(let top) = atTop.phase, case .loaded(let package) = inPackage.phase
        else {
            Issue.record("both stores should load")
            return
        }
        #expect(top == package)
        let now = Date(timeIntervalSince1970: 1_790_600_000)
        let summary = top.accessibilitySummary(relativeTo: now, locale: Locale(identifier: "en_US"))
        #expect(summary == package.accessibilitySummary(relativeTo: now, locale: Locale(identifier: "en_US")))
        #expect(!summary.localizedCaseInsensitiveContains("agent"))
        #expect(!summary.localizedCaseInsensitiveContains("claude"))
    }

    /// VoiceOver reads the header as one summary: the Checkout, whether it
    /// is a linked Worktree, the branch or detached commit, and the latest
    /// commit with its age.
    @Test func theHeaderReadsAsOneSummary() throws {
        let now = Date(timeIntervalSince1970: 1_790_600_000)
        let locale = Locale(identifier: "en_US")
        let main = try Self.read(GitProbeRecordings.hostile).changes
        #expect(
            main.accessibilitySummary(relativeTo: now, locale: locale)
                == #"Checkout ~/src/app. Branch main. Latest commit: Main edit to "conflict.txt", 3 hours ago."#)
        let worktree = try Self.read(GitProbeRecordings.worktree).changes
        #expect(
            worktree.accessibilitySummary(relativeTo: now, locale: locale)
                == "Checkout ~/src/app-wt, linked Worktree. Detached at 4f87954. Latest commit: Seed the fixture repository, 1 day ago.")
        let unborn = try Self.read(GitProbeRecordings.unborn).changes
        #expect(
            unborn.accessibilitySummary(relativeTo: now, locale: locale)
                == "Checkout ~/src/fresh. Branch main.")
    }
}

@MainActor
private final class DirectoryBox {
    var value: String
    init(_ value: String) { self.value = value }
}
