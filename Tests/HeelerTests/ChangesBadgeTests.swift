import Foundation
import Testing
import UIKit

@testable import Heeler

/// The Agent switcher's Changes badge: the line totals the Changes header
/// shows for the same read, and nothing when that read cannot vouch for them.
@MainActor
@Suite("Changes badge")
struct ChangesBadgeTests {
    private static let english = Locale(identifier: "en_US")

    /// The tracking recording with `app.txt` counted as `added`/`removed`;
    /// its binary file and untracked note stay as recorded.
    static func read(added: Int, removed: Int) throws -> CheckoutChangesRead {
        let stdout = Data(
            String(decoding: GitProbeRecordings.tracking.stdout, as: UTF8.self)
                .replacingOccurrences(of: "3\t1\tapp.txt", with: "\(added)\t\(removed)\tapp.txt")
                .utf8)
        return try ChangesStoreTests.read((stdout, GitProbeRecordings.tracking.stderr))
    }

    private static func badge(_ changes: CheckoutChanges) -> ChangesBadge? {
        ChangesBadge(phase: .loaded(changes), timedOutKeepingContent: false)
    }

    @Test func showsTheHeadersLineTotalsForALoadedDirtyCheckout() throws {
        let changes = try Self.read(added: 12, removed: 7).changes
        let badge = try #require(Self.badge(changes))
        #expect(badge.addedText(locale: Self.english) == "+12")
        #expect(badge.removedText(locale: Self.english) == "\u{2212}7")
        #expect(changes.totalsSummary.contains("\(badge.addedText()) \(badge.removedText()) lines"))
        #expect(badge.accessibilityValue == "12 lines added, 7 lines removed")
    }

    @Test func hidesWhenNothingIsReadCleanOrFailed() throws {
        let clean = try ChangesStoreTests.read(GitProbeRecordings.clean).changes
        #expect(clean.isClean)
        let phases: [ChangesStore.Phase] = [
            .loading, .loaded(clean), .notAGitWorkingTree, .failed("fatal: broken"), .gitMissing,
            .gitTooOld("2.10.0"), .notOwnedByAccount, .directoryMissing, .incomplete, .timedOut,
        ]
        for phase in phases {
            #expect(
                ChangesBadge(phase: phase, timedOutKeepingContent: false) == nil,
                "a badge for \(phase)")
        }
    }

    @Test func hidesWhenARefreshTimedOutKeepingTheOldDocument() throws {
        let changes = try Self.read(added: 12, removed: 7).changes
        #expect(ChangesBadge(phase: .loaded(changes), timedOutKeepingContent: true) == nil)
    }

    @Test func hidesWhenLineCountsAreUnavailable() throws {
        var changes = try Self.read(added: 12, removed: 7).changes
        changes.totals.linesAreAvailable = false
        #expect(Self.badge(changes) == nil)
    }

    /// Untracked, binary, and mode-only changes have no line delta, yet the
    /// Checkout is not clean: the badge says +0 −0 as the header does, and
    /// VoiceOver hears what did change.
    @Test func showsZeroesWhenFilesChangedWithoutALineDelta() throws {
        var changes = try Self.read(added: 12, removed: 7).changes
        changes.totals.added = 0
        changes.totals.removed = 0
        let badge = try #require(Self.badge(changes))
        #expect(badge.addedText(locale: Self.english) == "+0")
        #expect(badge.removedText(locale: Self.english) == "\u{2212}0")
        #expect(changes.totalsSummary.contains("\(badge.addedText()) \(badge.removedText()) lines"))
        #expect(
            badge.accessibilityValue
                == "0 lines added, 0 lines removed, 2 files changed, 1 untracked item")

        changes.totals.trackedFiles = 0
        let untrackedOnly = try #require(Self.badge(changes))
        #expect(
            untrackedOnly.accessibilityValue == "0 lines added, 0 lines removed, 1 untracked item")
    }

    @Test func aTruncatedCountReadsAsALowerBound() throws {
        var changes = try Self.read(added: 12, removed: 7).changes
        changes.totals.linesAreComplete = false
        let badge = try #require(Self.badge(changes))
        #expect(badge.addedText(locale: Self.english) == "+12")
        #expect(badge.removedText(locale: Self.english) == "\u{2212}7")
        #expect(badge.accessibilityValue == "At least 12 lines added, 7 lines removed")
    }

    @Test(arguments: [
        (0, "0"), (9_999, "9,999"), (10_000, "10K"), (12_345, "12.3K"), (99_999, "99.9K"),
        (123_456, "123K"), (999_999, "999K"), (1_000_000, "1M"), (1_050_000, "1.05M"),
        (1_234_567, "1.23M"), (999_999_999, "999M"), (Int.max, "999T+"),
    ])
    func compactCountsShortenFromTenThousandWithoutOverstating(value: Int, expected: String) {
        #expect(ChangesBadge.count(value, style: .compact, locale: Self.english) == expected)
        #expect(
            ChangesBadge.count(value, style: .exact, locale: Self.english)
                == value.formatted(.number.locale(Self.english)))
    }

    @Test func compactCountsUseTheLocalesDecimalSeparator() {
        let german = Locale(identifier: "de_DE")
        #expect(ChangesBadge.count(12_345, style: .compact, locale: german) == "12,3K")
        #expect(ChangesBadge.count(9_999, style: .compact, locale: german) == "9.999")
    }

    /// The badge prefers the header's exact numbers; the short form is only
    /// for a row without room, and VoiceOver always hears them exactly.
    @Test func largeTotalsStayExactUntilTheRowAsksForTheShortForm() throws {
        let changes = try Self.read(added: 12_345, removed: 7).changes
        let badge = try #require(Self.badge(changes))
        #expect(badge.addedText(locale: Self.english) == "+12,345")
        #expect(badge.addedText(.compact, locale: Self.english) == "+12.3K")
        #expect(badge.removedText(.compact, locale: Self.english) == "\u{2212}7")
        #expect(badge.accessibilityValue.hasPrefix("\(12_345.formatted()) lines added"))
    }

    @Test func inksMeetTextContrastOnTheRowInEveryAppearance() {
        let appearances: [(String, UITraitCollection)] = [
            ("light", UITraitCollection(userInterfaceStyle: .light)),
            ("dark", UITraitCollection(userInterfaceStyle: .dark)),
            (
                "dark elevated",
                UITraitCollection { traits in
                    traits.userInterfaceStyle = .dark
                    traits.userInterfaceLevel = .elevated
                }
            ),
        ]
        for (name, traits) in appearances {
            let ground = Self.rgb(.secondarySystemBackground, traits)
            for (role, ink) in [
                ("added", ChangesBadgePalette.addedInk), ("removed", ChangesBadgePalette.removedInk),
            ] {
                let ratio = Self.contrastRatio(Self.rgb(ink, traits), ground)
                #expect(ratio >= 4.5, "\(role) ink on the \(name) row: \(ratio)")
            }
        }
    }

    private static func rgb(_ color: UIColor, _ traits: UITraitCollection) -> [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue]
    }

    /// WCAG 2 contrast ratio from sRGB components.
    private static func contrastRatio(_ a: [CGFloat], _ b: [CGFloat]) -> CGFloat {
        let (lighter, darker) = luminance(a) > luminance(b)
            ? (luminance(a), luminance(b)) : (luminance(b), luminance(a))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ components: [CGFloat]) -> CGFloat {
        let linear = components.map { channel in
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}

/// Agent detail's own Changes store: one for the life of the detail, read
/// once the page settles, when the Agent leaves Working, and by Changes
/// itself, every read through the Host's git exec gate.
@MainActor
@Suite("Agent Changes following", .timeLimit(.minutes(1)))
struct AgentChangesFollowTests {
    /// An Agent's status stream per store, as the Console hands them out: a
    /// fresh stream whose first value is the current status.
    @MainActor
    final class StatusFeed {
        private var current: AgentStatus?
        private var continuations: [AsyncStream<ConsoleStore.AgentStatusUpdate>.Continuation] = []

        init(_ status: AgentStatus?) { current = status }

        func stream() -> AsyncStream<ConsoleStore.AgentStatusUpdate> {
            let (stream, continuation) = AsyncStream.makeStream(
                of: ConsoleStore.AgentStatusUpdate.self)
            continuation.yield(.init(status: current, liveUpdatesAvailable: true))
            continuations.append(continuation)
            return stream
        }

        func send(_ status: AgentStatus?) {
            current = status
            for continuation in continuations {
                continuation.yield(.init(status: status, liveUpdatesAvailable: true))
            }
        }

        func finish() {
            for continuation in continuations { continuation.finish() }
        }
    }

    static func presentation(
        transport: ScriptedTransport,
        gate: GitExecGate = GitExecGate(),
        clock: ChangesManualSleeper,
        feed: StatusFeed,
        now: @escaping @MainActor () -> Date = { Date(timeIntervalSince1970: 1_000) },
        announce: @escaping @MainActor (String) -> Void = { _ in }
    ) -> AgentChangesPresentation {
        AgentChangesPresentation(makeStoreIn: { fixed in
            ChangesStore(
                directory: { fixed ?? "/home/dev/src/tracking" },
                read: { try await transport.readChanges($0) },
                readPatch: { try await transport.readFilePatch($0) },
                gate: gate,
                agentStatus: { feed.stream() },
                sleep: { try await clock.sleep($0) },
                now: now,
                announce: announce)
        })
    }

    private static func badge(_ store: ChangesStore?) -> ChangesBadge? {
        store.flatMap {
            ChangesBadge(phase: $0.phase, timedOutKeepingContent: $0.timedOutKeepingContent)
        }
    }

    private static func texts(_ store: ChangesStore?) -> String? {
        badge(store).map { "\($0.addedText()) \($0.removedText())" }
    }

    @Test func followingReadsOnceAfterTheAppearanceSettles() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesBadgeTests.read(added: 12, removed: 7)
        await transport.scriptChangesReads([.success(read)])
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.idle)
        defer { feed.finish() }
        let changes = Self.presentation(transport: transport, clock: clock, feed: feed)
        changes.startFollowingAgent()
        defer { changes.stopFollowingAgent() }
        await Self.drain()
        #expect(await clock.durations == [.milliseconds(300)])
        #expect(await transport.changesReadRequests.isEmpty)
        #expect(changes.isFollowingAgent)
        let store = try #require(changes.agentStore)
        #expect(Self.badge(store) == nil)

        await clock.fireAll()
        await Self.waitUntilSettled(store, .loaded(read.changes))
        #expect(await transport.changesReadRequests.count == 1)
        #expect(Self.texts(store) == "+12 \u{2212}7")
        #expect(changes.store == nil)
    }

    @Test func leavingBeforeTheSettleNeverReads() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([.success(try ChangesBadgeTests.read(added: 12, removed: 7))])
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.idle)
        defer { feed.finish() }
        let changes = Self.presentation(transport: transport, clock: clock, feed: feed)
        changes.startFollowingAgent()
        await Self.drain()
        changes.stopFollowingAgent()
        #expect(!changes.isFollowingAgent)
        await clock.fireAll()
        await Self.drain()
        #expect(await transport.changesReadRequests.isEmpty)
        #expect(changes.agentStore?.phase == .loading)
    }

    /// Opening Changes reads once more, as it always has, keeping the
    /// badge's document on screen while it does.
    @Test func openingChangesAfterTheBadgesReadShowsItAndReadsAgain() async throws {
        let transport = ScriptedTransport()
        let first = try ChangesBadgeTests.read(added: 12, removed: 7)
        let second = try ChangesBadgeTests.read(added: 1, removed: 1)
        await transport.scriptChangesReads([.success(first), .success(second)])
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.idle)
        defer { feed.finish() }
        let changes = Self.presentation(transport: transport, clock: clock, feed: feed)
        changes.startFollowingAgent()
        defer { changes.stopFollowingAgent() }
        await Self.drain()
        await clock.fireAll()
        let agentStore = try #require(changes.agentStore)
        await Self.waitUntilSettled(agentStore, .loaded(first.changes))

        let hold = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: hold)
        changes.open()
        let shown = try #require(changes.store)
        #expect(shown === agentStore)
        shown.startRefresh()
        await hold.waitForEntry()
        #expect(shown.phase == .loaded(first.changes))
        #expect(shown.isRefreshing)
        await hold.open()
        await Self.waitUntilSettled(shown, .loaded(second.changes))
        #expect(await transport.changesReadRequests.count == 2)
    }

    @Test func openingChangesDuringTheBadgesReadWaitsForThatRead() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesBadgeTests.read(added: 12, removed: 7)
        await transport.scriptChangesReads([.success(read)])
        let hold = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: hold)
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.idle)
        defer { feed.finish() }
        let changes = Self.presentation(transport: transport, clock: clock, feed: feed)
        changes.startFollowingAgent()
        defer { changes.stopFollowingAgent() }
        await Self.drain()
        await clock.fireAll()
        await hold.waitForEntry()

        changes.open()
        let shown = try #require(changes.store)
        shown.startRefresh()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 1)
        #expect(shown.phase == .loading)
        await hold.open()
        await Self.waitUntilSettled(shown, .loaded(read.changes))
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func backFromChangesKeepsItsFresherReadForTheBadge() async throws {
        let transport = ScriptedTransport()
        let first = try ChangesBadgeTests.read(added: 12, removed: 7)
        let second = try ChangesBadgeTests.read(added: 1, removed: 1)
        await transport.scriptChangesReads([.success(first), .success(second)])
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.idle)
        defer { feed.finish() }
        let changes = Self.presentation(transport: transport, clock: clock, feed: feed)
        changes.startFollowingAgent()
        defer { changes.stopFollowingAgent() }
        await Self.drain()
        await clock.fireAll()
        let store = try #require(changes.agentStore)
        await Self.waitUntilSettled(store, .loaded(first.changes))

        changes.open()
        store.startRefresh()
        await Self.waitUntilSettled(store, .loaded(second.changes))
        let file = try #require(second.changes.files.first { $0.displayPath == "app.txt" })
        store.openDiff(file)
        #expect(store.fileDiff.current != nil)
        changes.close()
        #expect(changes.store == nil)
        #expect(changes.agentStore === store)
        #expect(store.fileDiff.current == nil)
        #expect(Self.texts(store) == "+1 \u{2212}1")
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 2)
    }

    @Test func aReadStartedByChangesOutlivesBack() async throws {
        let transport = ScriptedTransport()
        let first = try ChangesBadgeTests.read(added: 12, removed: 7)
        let second = try ChangesBadgeTests.read(added: 1, removed: 1)
        await transport.scriptChangesReads([.success(first), .success(second)])
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.idle)
        defer { feed.finish() }
        let changes = Self.presentation(transport: transport, clock: clock, feed: feed)
        changes.startFollowingAgent()
        defer { changes.stopFollowingAgent() }
        await Self.drain()
        await clock.fireAll()
        let store = try #require(changes.agentStore)
        await Self.waitUntilSettled(store, .loaded(first.changes))

        let hold = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: hold)
        changes.open()
        store.startRefresh()
        await hold.waitForEntry()
        changes.close()
        await hold.open()
        await Self.waitUntilSettled(store, .loaded(second.changes))
        #expect(Self.texts(store) == "+1 \u{2212}1")
    }

    @Test func leavingWorkingRefreshesTheBadgeThroughTheHostGate() async throws {
        let transport = ScriptedTransport()
        let first = try ChangesBadgeTests.read(added: 12, removed: 7)
        let second = try ChangesBadgeTests.read(added: 1, removed: 1)
        let third = try ChangesBadgeTests.read(added: 2, removed: 0)
        await transport.scriptChangesReads([.success(first), .success(second), .success(third)])
        let gate = GitExecGate()
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.working)
        defer { feed.finish() }
        let changes = Self.presentation(transport: transport, gate: gate, clock: clock, feed: feed)
        changes.startFollowingAgent()
        defer { changes.stopFollowingAgent() }
        await Self.drain()
        await clock.fireAll()
        let store = try #require(changes.agentStore)
        await Self.waitUntilSettled(store, .loaded(first.changes))

        // Another git exec on this Host, such as Worktree Changes, holds the gate.
        let other = ScriptedTransportCallGate()
        let holder = Task { try await gate.run { await other.waitUntilOpen() } }
        await other.waitForEntry()
        feed.send(.done)
        await Self.drain()
        await clock.fireAll()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 1)
        // A second exit while that read waits merges into one follow-up.
        feed.send(.working)
        feed.send(.done)
        await Self.drain()
        await clock.fireAll()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 1)
        #expect(Self.texts(store) == "+12 \u{2212}7")

        await other.open()
        try await holder.value
        await Self.eventually { await transport.changesReadRequests.count == 3 }
        await Self.waitUntilSettled(store, .loaded(third.changes))
        await Self.drain()
        await clock.fireAll()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 3)
        #expect(Self.texts(store) == "+2 \u{2212}0")
    }

    @Test func aTimedOutRefreshHidesTheBadgeAndTheNextSuccessRestoresIt() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesBadgeTests.read(added: 12, removed: 7)
        await transport.scriptChangesReads([
            .success(read), .failure(TransportError.gitTimedOut), .success(read),
        ])
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.idle)
        defer { feed.finish() }
        let changes = Self.presentation(transport: transport, clock: clock, feed: feed)
        changes.startFollowingAgent()
        defer { changes.stopFollowingAgent() }
        await Self.drain()
        await clock.fireAll()
        let store = try #require(changes.agentStore)
        await Self.waitUntilSettled(store, .loaded(read.changes))
        #expect(Self.badge(store) != nil)

        await store.refresh()
        #expect(store.timedOutKeepingContent)
        #expect(Self.badge(store) == nil)
        await store.refresh()
        #expect(Self.texts(store) == "+12 \u{2212}7")
    }

    @Test func followingNeverReadsWithoutATrigger() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesBadgeTests.read(added: 12, removed: 7)
        await transport.scriptChangesReads([.success(read), .success(read)])
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.idle)
        defer { feed.finish() }
        let changes = Self.presentation(transport: transport, clock: clock, feed: feed)
        changes.startFollowingAgent()
        defer { changes.stopFollowingAgent() }
        await Self.drain()
        await clock.fireAll()
        let store = try #require(changes.agentStore)
        await Self.waitUntilSettled(store, .loaded(read.changes))
        for _ in 0..<5 {
            await Self.drain()
            await clock.fireAll()
        }
        #expect(await transport.changesReadRequests.count == 1)
        #expect(await clock.durations == [.milliseconds(300)])
    }

    /// Leaving drops a read still queued at the Host gate, but a read git is
    /// already running keeps the gate until it answers, so quickly passing
    /// through Agents never stacks git processes on one Host.
    @Test func leavingKeepsARunningReadAndDropsAQueuedOne() async throws {
        let transport = ScriptedTransport()
        let first = try ChangesBadgeTests.read(added: 12, removed: 7)
        let second = try ChangesBadgeTests.read(added: 1, removed: 1)
        await transport.scriptChangesReads([.success(first), .success(second)])
        let hold = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: hold)
        let gate = GitExecGate()
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.idle)
        defer { feed.finish() }
        let a = Self.presentation(transport: transport, gate: gate, clock: clock, feed: feed)
        let b = Self.presentation(transport: transport, gate: gate, clock: clock, feed: feed)
        defer {
            a.stopFollowingAgent()
            b.stopFollowingAgent()
        }
        a.startFollowingAgent()
        await Self.drain()
        await clock.fireAll()
        await hold.waitForEntry()
        a.stopFollowingAgent()

        b.startFollowingAgent()
        await Self.drain()
        await clock.fireAll()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 1)
        b.stopFollowingAgent()
        await Self.drain()

        await hold.open()
        let aStore = try #require(a.agentStore)
        await Self.waitUntilSettled(aStore, .loaded(first.changes))
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 1)
        let bStore = try #require(b.agentStore)
        #expect(bStore.phase == .loading)

        b.startFollowingAgent()
        await Self.drain()
        await clock.fireAll()
        await Self.waitUntilSettled(bStore, .loaded(second.changes))
        #expect(await transport.changesReadRequests.count == 2)
    }

    @Test func automaticUpdatesAnnounceOnlyWhileChangesIsShown() async throws {
        let transport = ScriptedTransport()
        let dirty = try ChangesBadgeTests.read(added: 12, removed: 7)
        let clean = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(dirty), .success(clean), .success(dirty)])
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.working)
        defer { feed.finish() }
        var announcements: [String] = []
        let changes = Self.presentation(
            transport: transport, clock: clock, feed: feed,
            announce: { announcements.append($0) })
        changes.startFollowingAgent()
        defer { changes.stopFollowingAgent() }
        await Self.drain()
        await clock.fireAll()
        let store = try #require(changes.agentStore)
        await Self.waitUntilSettled(store, .loaded(dirty.changes))

        feed.send(.done)
        await Self.drain()
        await clock.fireAll()
        await Self.waitUntilSettled(store, .loaded(clean.changes))
        #expect(announcements.isEmpty)

        changes.open()
        feed.send(.working)
        feed.send(.done)
        await Self.drain()
        await clock.fireAll()
        await Self.waitUntilSettled(store, .loaded(dirty.changes))
        #expect(announcements == ["Checkout Changes updated."])
        changes.close()
    }

    /// Worktree Details offers Changes for the Agent's own linked Worktree.
    /// Back hands that newer read to the badge; another Checkout's does not.
    @Test func worktreeChangesOfTheAgentsCheckoutUpdateTheBadgeOnBack() async throws {
        let transport = ScriptedTransport()
        let agentRead = try ChangesBadgeTests.read(added: 12, removed: 7)
        let worktreeRead = try ChangesBadgeTests.read(added: 15, removed: 9)
        let elsewhere = try ChangesStoreTests.read(GitProbeRecordings.worktree)
        await transport.scriptChangesReads([
            .success(agentRead), .success(worktreeRead), .success(elsewhere),
        ])
        #expect(elsewhere.changes.checkout.topLevel != agentRead.changes.checkout.topLevel)
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.idle)
        defer { feed.finish() }
        var now = Date(timeIntervalSince1970: 1_000)
        let changes = Self.presentation(
            transport: transport, clock: clock, feed: feed, now: { now })
        changes.startFollowingAgent()
        defer { changes.stopFollowingAgent() }
        await Self.drain()
        await clock.fireAll()
        let store = try #require(changes.agentStore)
        await Self.waitUntilSettled(store, .loaded(agentRead.changes))

        now = Date(timeIntervalSince1970: 2_000)
        changes.open(directory: "/home/dev/src/tracking")
        let worktree = try #require(changes.store)
        #expect(worktree !== store)
        await worktree.appear()
        #expect(worktree.phase == .loaded(worktreeRead.changes))
        changes.close()
        #expect(Self.texts(store) == "+15 \u{2212}9")
        #expect(store.readAt == Date(timeIntervalSince1970: 2_000))

        now = Date(timeIntervalSince1970: 3_000)
        changes.open(directory: "/home/dev/src/wt")
        let other = try #require(changes.store)
        await other.appear()
        #expect(other.phase == .loaded(elsewhere.changes))
        changes.close()
        #expect(Self.texts(store) == "+15 \u{2212}9")
        #expect(store.readAt == Date(timeIntervalSince1970: 2_000))
        #expect(await transport.changesReadRequests.count == 3)
    }

    /// Worktree Changes of the Agent's own Checkout follow the same Agent, so
    /// an exit from Working reads that Checkout once, in the shown store, and
    /// Back hands that read to the badge without reading again.
    @Test func worktreeChangesOfTheAgentsCheckoutReadOncePerWorkingExit() async throws {
        let transport = ScriptedTransport()
        let agentRead = try ChangesBadgeTests.read(added: 12, removed: 7)
        let opened = try ChangesBadgeTests.read(added: 15, removed: 9)
        let exited = try ChangesBadgeTests.read(added: 2, removed: 0)
        let spare = try ChangesBadgeTests.read(added: 3, removed: 3)
        await transport.scriptChangesReads([
            .success(agentRead), .success(opened), .success(exited), .success(spare),
        ])
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.working)
        defer { feed.finish() }
        var now = Date(timeIntervalSince1970: 1_000)
        let changes = Self.presentation(
            transport: transport, clock: clock, feed: feed, now: { now })
        changes.startFollowingAgent()
        defer { changes.stopFollowingAgent() }
        await Self.drain()
        await clock.fireAll()
        let store = try #require(changes.agentStore)
        await Self.waitUntilSettled(store, .loaded(agentRead.changes))

        now = Date(timeIntervalSince1970: 2_000)
        changes.open(directory: "/home/dev/src/tracking")
        let worktree = try #require(changes.store)
        await worktree.appear()
        #expect(worktree.phase == .loaded(opened.changes))
        await Self.drain()

        now = Date(timeIntervalSince1970: 3_000)
        feed.send(.done)
        await Self.drain()
        await clock.fireAll()
        await Self.waitUntilSettled(worktree, .loaded(exited.changes))
        await Self.drain()
        await clock.fireAll()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 3)
        #expect(Self.texts(store) == "+12 \u{2212}7")

        changes.close()
        worktree.cancel()
        #expect(Self.texts(store) == "+2 \u{2212}0")
        await Self.drain()
        await clock.fireAll()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 3)
        #expect(store.activeRead == nil)
    }

    /// Back before Worktree Changes answered an exit from Working leaves the
    /// badge's Checkout unread since that exit, so its own refresh runs.
    @Test func backBeforeWorktreeChangesAnswerAnExitRefreshesTheBadge() async throws {
        let transport = ScriptedTransport()
        let agentRead = try ChangesBadgeTests.read(added: 12, removed: 7)
        let opened = try ChangesBadgeTests.read(added: 15, removed: 9)
        let unanswered = try ChangesBadgeTests.read(added: 1, removed: 1)
        let refreshed = try ChangesBadgeTests.read(added: 2, removed: 0)
        await transport.scriptChangesReads([
            .success(agentRead), .success(opened), .success(unanswered), .success(refreshed),
        ])
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.working)
        defer { feed.finish() }
        let changes = Self.presentation(transport: transport, clock: clock, feed: feed)
        changes.startFollowingAgent()
        defer { changes.stopFollowingAgent() }
        await Self.drain()
        await clock.fireAll()
        let store = try #require(changes.agentStore)
        await Self.waitUntilSettled(store, .loaded(agentRead.changes))

        changes.open(directory: "/home/dev/src/tracking")
        let worktree = try #require(changes.store)
        await worktree.appear()
        await Self.drain()

        let hold = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: hold)
        feed.send(.done)
        await Self.drain()
        await clock.fireAll()
        await hold.waitForEntry()
        await Self.drain()
        #expect(await transport.changesReadRequests.count == 3)

        // Back, and the view's teardown cancels the Worktree's read.
        changes.close()
        worktree.cancel()
        await hold.open()
        await Self.waitUntilSettled(store, .loaded(refreshed.changes))
        #expect(await transport.changesReadRequests.count == 4)
        #expect(Self.texts(store) == "+2 \u{2212}0")
    }

    @Test func thePresentationStopsFollowingWhenItGoesAway() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([.success(try ChangesBadgeTests.read(added: 12, removed: 7))])
        let clock = ChangesManualSleeper()
        let feed = StatusFeed(.idle)
        defer { feed.finish() }
        var changes: AgentChangesPresentation? = Self.presentation(
            transport: transport, clock: clock, feed: feed)
        changes?.startFollowingAgent()
        weak let weakStore = changes?.agentStore
        await Self.drain()
        #expect(weakStore != nil)
        changes = nil
        await Self.drain()
        await clock.fireAll()
        await Self.drain()
        #expect(weakStore == nil)
        #expect(await transport.changesReadRequests.isEmpty)
    }

    static func drain() async {
        for _ in 0..<100 { await Task.yield() }
    }

    /// The document is published inside the Host gate, a hop before the
    /// read ends; the next read can start only once it has.
    static func waitUntilSettled(_ store: ChangesStore, _ phase: ChangesStore.Phase) async {
        await waitUntil { store.phase == phase && store.activeRead == nil }
    }

    static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        #expect(condition())
    }

    static func eventually(_ condition: () async -> Bool) async {
        for _ in 0..<2_000 {
            if await condition() { return }
            await Task.yield()
        }
        #expect(await condition())
    }
}

/// Hosted accessibility lookups for the badge's row and detail tests: every
/// visible element with a label, and where it sits.
@MainActor
enum AccessibilityProbe {
    static func elements(labeled label: String, in root: UIView) -> [NSObject] {
        root.layoutIfNeeded()
        var visited = Set<ObjectIdentifier>()
        var found: [NSObject] = []
        func visit(_ node: NSObject) {
            guard visited.insert(ObjectIdentifier(node)).inserted,
                !node.accessibilityElementsHidden
            else { return }
            if node.accessibilityLabel == label, frame(of: node, in: root).width > 0 {
                found.append(node)
            }
            for object in node.accessibilityElements ?? [] {
                if let object = object as? NSObject { visit(object) }
            }
            let count = node.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<count {
                    if let object = node.accessibilityElement(at: index) as? NSObject {
                        visit(object)
                    }
                }
            }
            if let view = node as? UIView { view.subviews.forEach(visit) }
        }
        visit(root)
        return found
    }

    static func frame(of node: NSObject, in root: UIView) -> CGRect {
        if let view = node as? UIView {
            return view.convert(view.bounds, to: root)
        }
        return root.convert(node.accessibilityFrame, from: nil)
    }

    static func frame(labeled label: String, in root: UIView) -> CGRect? {
        elements(labeled: label, in: root).first.map { frame(of: $0, in: root) }
    }
}
