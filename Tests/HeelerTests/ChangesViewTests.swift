import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Heeler

/// Changes opened in place of Agent detail. The Agent's own Changes keep one
/// store for the life of Agent detail, which its switcher badge reads too;
/// Worktree Changes get a store of their own that closing discards.
@MainActor
@Suite("Changes presentation")
struct AgentChangesPresentationTests {
    @Test func theAgentsChangesAreOneStoreForTheLifeOfAgentDetail() async throws {
        var made = 0
        let presentation = AgentChangesPresentation {
            made += 1
            return ChangesStore(directory: { "/home/dev/src/app" }) { _ in
                throw ChangesReadError.unavailable
            }
        }
        #expect(presentation.store == nil)
        #expect(presentation.agentStore == nil)

        presentation.open()
        let first = try #require(presentation.store)
        presentation.open()
        #expect(presentation.store === first)
        #expect(presentation.agentStore === first)
        #expect(made == 1)
        await first.refresh()
        #expect(first.phase == .failed(ChangesReadError.unavailable.message))

        presentation.close()
        #expect(presentation.store == nil)
        #expect(presentation.agentStore === first)

        presentation.open()
        #expect(presentation.store === first)
        #expect(first.phase == .failed(ChangesReadError.unavailable.message))
        #expect(made == 1)
    }

    /// Worktree Details and the dirty-removal refusal hand that Worktree's
    /// directory. The Agent menu hands nil, so the next open follows the Agent
    /// again instead of keeping the Worktree path.
    @Test func openingForAWorktreeReadsThatDirectory() async throws {
        let transport = ScriptedTransport()
        var handed: [String?] = []
        let presentation = AgentChangesPresentation(makeStoreIn: { fixed in
            handed.append(fixed)
            return ChangesStore(directory: { fixed ?? "/home/dev/src/app/pkg" }) { request in
                try await transport.readChanges(request)
            }
        })

        presentation.open(directory: "/work/Heeler-wt")
        let store = try #require(presentation.store)
        await store.appear()
        #expect(handed == ["/work/Heeler-wt"])
        #expect(
            await transport.changesReadRequests
                == [ChangesReadRequest(directory: "/work/Heeler-wt")])

        let shown = presentation.store
        presentation.open(directory: "/other")
        #expect(presentation.store === shown)
        #expect(handed == ["/work/Heeler-wt"])

        await store.refresh()
        #expect(
            await transport.changesReadRequests.map(\.directory)
                == ["/work/Heeler-wt", "/work/Heeler-wt"])

        presentation.close()
        #expect(presentation.store == nil)

        presentation.open()
        let followed = try #require(presentation.store)
        await followed.appear()
        #expect(handed == ["/work/Heeler-wt", nil])
        #expect(
            await transport.changesReadRequests.map(\.directory)
                == [
                    "/work/Heeler-wt", "/work/Heeler-wt",
                    "/home/dev/src/app/pkg",
                ])
    }
    @Test func insertingClosesChangesAndHandsTheReferenceBackExactlyOnce() async throws {
        let read = try ChangesStoreTests.read(GitProbeRecordings.subdir)
        let presentation = AgentChangesPresentation {
            ChangesStore(directory: { "/home/dev/src/app/pkg" }) { _ in read }
        }
        presentation.open()
        let store = try #require(presentation.store)
        await store.appear()
        let file = ChangedFile(
            path: Data("pkg/renamed.txt".utf8), originalPath: nil,
            kind: .modified, staging: .unstaged)
        store.insert(file: file)
        #expect(presentation.store == nil)
        #expect(presentation.takePendingInsertion() == "renamed.txt ")
        #expect(presentation.takePendingInsertion() == nil)

        // A departing menu cannot hand another reference to the next view.
        store.insert(file: file)
        #expect(presentation.takePendingInsertion() == nil)
    }

    @Test func worktreeInsertionsStayAbsoluteAndAnOrdinaryBackInsertsNothing() async throws {
        let read = try ChangesStoreTests.read(GitProbeRecordings.subdir)
        let presentation = AgentChangesPresentation(makeStoreIn: { directory in
            ChangesStore(directory: { directory }) { _ in read }
        })
        presentation.open(directory: "/work/other/pkg")
        let store = try #require(presentation.store)
        await store.appear()
        let file = ChangedFile(
            path: Data("pkg/renamed.txt".utf8), originalPath: nil,
            kind: .modified, staging: .unstaged)
        store.insert(file: file)
        #expect(presentation.takePendingInsertion() == "/home/dev/src/app/pkg/renamed.txt ")

        presentation.open()
        presentation.close()
        #expect(presentation.takePendingInsertion() == nil)
    }
}

/// The Changes view hosted in a window, read the way VoiceOver reads it.
@MainActor
@Suite("Changes view", .timeLimit(.minutes(1)))
struct ChangesViewTests {
    @Test func theHeaderIsOneSummaryAndEachRowReadsItsPathAndKind() async throws {
        let (controller, window, _) = try await Self.host(GitProbeRecordings.hostile)
        defer { window.isHidden = true }

        var labels = Set<String>()
        let loaded = try await Self.eventually {
            labels = Self.labels(in: controller)
            return labels.contains("conflict.txt, conflicted, 4 lines added, 0 lines removed")
        }
        try #require(loaded, "rows never appeared: \(labels.sorted())")

        let header = labels.filter {
            $0.hasPrefix(
                #"Checkout ~/src/app. Branch main. Latest commit: Main edit to "conflict.txt", "#)
        }
        #expect(header.count == 1, "header summary missing: \(labels.sorted())")
        // The summary replaces its fragments rather than repeating them.
        #expect(!labels.contains("~/src/app"))
        #expect(!labels.contains("main"))
        // Rows are lazy, so only the first screenful exists: conflicts
        // first, then by path.
        #expect(labels.contains("conflict.txt, conflicted, 4 lines added, 0 lines removed"))
        #expect(labels.contains("--, modified, unstaged, 1 line added, 0 lines removed"))
        #expect(labels.contains("[ab].txt, modified, unstaged, 1 line added, 0 lines removed"))
        #expect(labels.contains("added.txt, added, staged, 1 line added, 0 lines removed"))
    }

    @Test func aCleanCheckoutSaysSoUnderItsHeader() async throws {
        let (controller, window, _) = try await Self.host(GitProbeRecordings.clean)
        defer { window.isHidden = true }

        var labels = Set<String>()
        let clean = try await Self.eventually {
            labels = Self.labels(in: controller)
            return labels.contains(ChangesStore.cleanMessage)
        }
        #expect(clean, "clean state missing: \(labels.sorted())")
        #expect(
            labels.contains {
                $0.hasPrefix("Checkout ~/src/clean. Branch main. Latest commit: Clean tree, ")
            })
    }

    /// A staged rename moved on with `git add -N` lists each path once:
    /// the rename, now also deleted from the working tree, and the addition.
    @Test func aMovedStagedRenameShowsItsRenameAndItsAddition() async throws {
        let (controller, window, _) = try await Self.host(
            GitProbeRecordings.intentToAddMoveAfterStagedRename)
        defer { window.isHidden = true }

        var labels = Set<String>()
        let shown = try await Self.eventually {
            labels = Self.labels(in: controller)
            return labels.contains("b.txt, renamed from a.txt, staged and unstaged")
                && labels.contains("c.txt, added, unstaged")
        }
        #expect(shown, "rows missing: \(labels.sorted())")
    }

    @Test func aDirectoryOutsideAWorkingTreeSaysSo() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([.failure(ChangesReadError.notAGitWorkingTree)])
        let (controller, window, _) = try await Self.host(transport: transport)
        defer { window.isHidden = true }

        var labels = Set<String>()
        let shown = try await Self.eventually {
            labels = Self.labels(in: controller)
            return labels.contains("Not a Git Working Tree")
        }
        #expect(shown, "state missing: \(labels.sorted())")
    }

    /// Try Again's read belongs to the view, as the first read does: leaving
    /// Changes cancels it instead of letting it run on for a store nobody
    /// shows.
    @Test func leavingChangesCancelsATryAgainRead() async throws {
        let reads = ReadRecorder()
        let store = ChangesStore(directory: { "/home/dev/src/app" }) { _ in
            if await reads.begin() == 1 { throw ChangesReadError.notAGitWorkingTree }
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                await reads.markCancelled()
                throw error
            }
            throw ChangesReadError.unavailable
        }
        let controller = UIHostingController(
            rootView: AnyView(NavigationStack { ChangesView(store: store) {} }))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874),
            rootViewController: controller)
        defer { window.isHidden = true }
        try #require(
            await Self.eventually {
                Self.labels(in: controller).contains("Not a Git Working Tree")
            })

        try #require(await Self.eventually { Self.activate("Try Again", in: controller.view) })
        try #require(await Self.eventually { await reads.count == 2 })
        controller.rootView = AnyView(Text("Agent detail"))

        let cancelled = try await Self.eventually {
            controller.view.layoutIfNeeded()
            return await reads.wasCancelled
        }
        #expect(cancelled, "the Try Again read outlived Changes")
    }

    private actor ReadRecorder {
        private(set) var count = 0
        private(set) var wasCancelled = false

        func begin() -> Int {
            count += 1
            return count
        }

        func markCancelled() { wasCancelled = true }
    }

    /// Agent detail's store outlives Changes, so Try Again's read there is
    /// the store's: Back neither cancels it nor loses the refresh an exit
    /// from Working queued behind it, which the switcher badge needs.
    @Test func backKeepsATryAgainReadOnAgentDetailsStoreAndTheRefreshBehindIt() async throws {
        let transport = ScriptedTransport()
        let updated = try ChangesBadgeTests.read(added: 1, removed: 1)
        let latest = try ChangesBadgeTests.read(added: 2, removed: 0)
        await transport.scriptChangesReads([
            .failure(ChangesReadError.notAGitWorkingTree), .success(updated), .success(latest),
        ])
        let clock = ChangesManualSleeper()
        let feed = AgentChangesFollowTests.StatusFeed(.working)
        defer { feed.finish() }
        let shown = try await Self.hostAgentDetailsChanges(
            transport: transport, clock: clock, feed: feed)
        defer {
            shown.window.isHidden = true
            shown.changes.stopFollowingAgent()
        }
        try #require(
            await Self.eventually {
                Self.labels(in: shown.controller).contains("Not a Git Working Tree")
            })

        let hold = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: hold)
        try #require(
            await Self.eventually { Self.activate("Try Again", in: shown.controller.view) })
        try #require(await Self.eventually { await transport.changesReadRequests.count == 2 })
        try await Self.leaveWorkingThenGoBack(shown, transport: transport, clock: clock, feed: feed)

        await hold.open()
        let refreshed = try await Self.eventually {
            shown.store.phase == .loaded(latest.changes) && shown.store.activeRead == nil
        }
        #expect(refreshed, "Back lost the refresh queued behind Try Again: \(shown.store.phase)")
        #expect(await transport.changesReadRequests.count == 3)
    }

    /// A pull on Agent detail's store is kept past Back in the same way.
    @Test func backKeepsAPulledReadOnAgentDetailsStoreAndTheRefreshBehindIt() async throws {
        let transport = ScriptedTransport()
        let first = try ChangesBadgeTests.read(added: 12, removed: 7)
        let updated = try ChangesBadgeTests.read(added: 1, removed: 1)
        let latest = try ChangesBadgeTests.read(added: 2, removed: 0)
        await transport.scriptChangesReads([.success(first), .success(updated), .success(latest)])
        let clock = ChangesManualSleeper()
        let feed = AgentChangesFollowTests.StatusFeed(.working)
        defer { feed.finish() }
        let shown = try await Self.hostAgentDetailsChanges(
            transport: transport, clock: clock, feed: feed)
        defer {
            shown.window.isHidden = true
            shown.changes.stopFollowingAgent()
        }
        try #require(
            await Self.eventually {
                Self.labels(in: shown.controller).contains { $0.hasPrefix("Checkout ~/src/tracking") }
            })

        let hold = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: hold)
        try #require(Self.pull(in: shown.controller.view), "Changes has no refresh control")
        let pulled = try await Self.eventually { await transport.changesReadRequests.count == 2 }
        try #require(pulled, "the pull never read")
        try await Self.leaveWorkingThenGoBack(shown, transport: transport, clock: clock, feed: feed)

        await hold.open()
        let refreshed = try await Self.eventually {
            shown.store.phase == .loaded(latest.changes) && shown.store.activeRead == nil
        }
        #expect(refreshed, "Back lost the refresh queued behind the pull: \(shown.store.phase)")
        #expect(await transport.changesReadRequests.count == 3)
    }

    private struct ShownAgentChanges {
        let changes: AgentChangesPresentation
        let store: ChangesStore
        let controller: UIHostingController<AnyView>
        let window: UIWindow
    }

    /// Agent detail's own Changes as the Agent menu shows them: its store,
    /// already following the Agent's status, opened after that following
    /// began. Back closes them, and the test then takes them off screen.
    private static func hostAgentDetailsChanges(
        transport: ScriptedTransport,
        clock: ChangesManualSleeper,
        feed: AgentChangesFollowTests.StatusFeed
    ) async throws -> ShownAgentChanges {
        let changes = AgentChangesFollowTests.presentation(
            transport: transport, clock: clock, feed: feed)
        changes.startFollowingAgent()
        await AgentChangesFollowTests.drain()
        changes.open()
        let store = try #require(changes.store)
        #expect(store === changes.agentStore)
        let controller = UIHostingController(
            rootView: AnyView(
                NavigationStack {
                    ChangesView(store: store, sharesAgentDetailStore: true) { changes.close() }
                }))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874),
            rootViewController: controller)
        return ShownAgentChanges(
            changes: changes, store: store, controller: controller, window: window)
    }

    /// The Agent leaves Working while the requested read runs, so its
    /// refresh waits; then Back, and Changes leave the screen.
    private static func leaveWorkingThenGoBack(
        _ shown: ShownAgentChanges,
        transport: ScriptedTransport,
        clock: ChangesManualSleeper,
        feed: AgentChangesFollowTests.StatusFeed
    ) async throws {
        feed.send(.done)
        await AgentChangesFollowTests.drain()
        await clock.fireAll()
        await AgentChangesFollowTests.drain()
        #expect(await transport.changesReadRequests.count == 2)
        #expect(shown.store.activeRead != nil)

        try #require(await Self.eventually { Self.activate("Back", in: shown.controller.view) })
        #expect(shown.changes.store == nil)
        shown.controller.rootView = AnyView(Text("Agent detail"))
        let left = try await Self.eventually {
            Self.labels(in: shown.controller).contains("Agent detail")
        }
        try #require(left, "Changes never left the screen")
        await AgentChangesFollowTests.drain()
    }

    /// Pulls the list down as a finger does: SwiftUI's refresh control runs
    /// the view's refresh action when its value changes.
    static func pull(in root: UIView) -> Bool {
        root.layoutIfNeeded()
        func control(in view: UIView) -> UIRefreshControl? {
            if let control = view as? UIRefreshControl { return control }
            for subview in view.subviews {
                if let control = control(in: subview) { return control }
            }
            return nil
        }
        guard let refresh = control(in: root) else { return false }
        refresh.beginRefreshing()
        refresh.sendActions(for: .valueChanged)
        return true
    }

    @Test func backReturnsThroughTheBarButton() async throws {
        let (controller, window, backs) = try await Self.host(GitProbeRecordings.clean)
        defer { window.isHidden = true }

        let activated = try await Self.eventually {
            Self.activate("Back", in: controller.view)
        }
        #expect(activated)
        #expect(backs.count == 1)
    }

    // MARK: Hosting

    final class Counter {
        var count = 0
    }

    static func host(
        _ recording: (stdout: Data, stderr: Data)
    ) async throws -> (UIHostingController<AnyView>, UIWindow, Counter) {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([.success(try ChangesStoreTests.read(recording))])
        return try await host(transport: transport)
    }

    static func host(
        transport: ScriptedTransport
    ) async throws -> (UIHostingController<AnyView>, UIWindow, Counter) {
        let store = ChangesStore(directory: { "/home/dev/src/app" }) { request in
            try await transport.readChanges(request)
        }
        let backs = Counter()
        let controller = UIHostingController(
            rootView: AnyView(
                NavigationStack {
                    ChangesView(store: store) { backs.count += 1 }
                }))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874),
            rootViewController: controller)
        return (controller, window, backs)
    }

    static func labels(in controller: UIViewController) -> Set<String> {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return AgentSurfaceReplacementTests.accessibilityLabels(in: controller.view)
    }

    /// Activates the first accessibility element labelled `label`, as
    /// VoiceOver's double tap does; a bar button is a control that takes
    /// the tap itself.
    static func activate(_ label: String, in root: UIView) -> Bool {
        var visited = Set<ObjectIdentifier>()
        func visit(_ node: NSObject) -> Bool {
            guard visited.insert(ObjectIdentifier(node)).inserted,
                !node.accessibilityElementsHidden
            else { return false }
            if node.accessibilityLabel == label {
                if let control = node as? UIControl {
                    control.sendActions(for: .touchUpInside)
                    return true
                }
                if node.accessibilityActivate() { return true }
            }
            for object in node.accessibilityElements ?? [] {
                if let object = object as? NSObject, visit(object) { return true }
            }
            let count = node.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<count {
                    if let object = node.accessibilityElement(at: index) as? NSObject,
                        visit(object)
                    {
                        return true
                    }
                }
            }
            if let view = node as? UIView {
                for subview in view.subviews where visit(subview) { return true }
            }
            return false
        }
        root.layoutIfNeeded()
        return visit(root.window ?? root)
    }

    static func eventually(
        timeout: Duration = .seconds(5),
        _ condition: @escaping () async -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

/// Changes inside a hosted Agent detail: it replaces the terminal in place,
/// and Back brings the same Agent detail back with its draft and input mode.
@MainActor
@Suite("Agent detail Changes", .timeLimit(.minutes(1)))
struct AgentDetailChangesTests {
    @Test(arguments: [AgentInputMode.composer, .direct])
    func backRestoresAgentDetailWithTheDraftAndInputModeUntouched(
        mode: AgentInputMode
    ) async throws {
        let transport = ScriptedTransport()
        // Agent detail's badge reads once it settles; opening Changes reads again.
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        await transport.scriptChangesReads([.success(read), .success(read)])
        let composer = AgentComposerStore(target: "w1:p1") { _ in
            Agent(.fixture(paneID: "w1:p1"))
        }
        composer.replaceDraft(with: "keep this draft")
        let attach = try await Self.makeLiveAttach(transport: transport, composer: composer)
        let suiteName = "changes-detail-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let inputMode = AgentInputModeSettings(defaults: defaults)
        inputMode.select(mode)
        let changes = AgentChangesPresentation {
            ChangesStore(directory: { "/home/dev/src/app" }) { request in
                try await transport.readChanges(request)
            }
        }
        var shownChanges: [Bool] = []
        let detail = Self.makeDetail(
            attach: attach, composer: composer, inputMode: inputMode, defaults: defaults,
            changes: changes, onShowsChanges: { shownChanges.append($0) })
        let controller = UIHostingController(rootView: NavigationStack { detail })
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874),
            rootViewController: controller)
        defer { window.isHidden = true }
        try #require(
            await ChangesViewTests.eventually {
                controller.view.layoutIfNeeded()
                return !AgentSurfaceReplacementTests.terminals(in: controller.view).isEmpty
            })

        changes.open()
        var labels = Set<String>()
        let opened = try await ChangesViewTests.eventually {
            labels = ChangesViewTests.labels(in: controller)
            return labels.contains("conflict.txt, conflicted, 4 lines added, 0 lines removed")
                && AgentSurfaceReplacementTests.terminals(in: controller.view).isEmpty
        }
        try #require(opened, "Changes never replaced the terminal: \(labels.sorted())")
        #expect(shownChanges.last == true)

        let wentBack = try await ChangesViewTests.eventually {
            ChangesViewTests.activate("Back", in: controller.view)
        }
        try #require(wentBack)
        let returned = try await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            return !AgentSurfaceReplacementTests.terminals(in: controller.view).isEmpty
        }
        #expect(returned)
        #expect(changes.store == nil)
        #expect(shownChanges.last == false)
        #expect(composer.draft == "keep this draft")
        #expect(inputMode.mode == mode)
        #expect(!ChangesViewTests.labels(in: controller).contains("conflict.txt, conflicted, 4 lines added, 0 lines removed"))

        await attach.leave().value
    }

    /// Agent detail leaving the screen while Changes stays open (another
    /// tab, or a view pushed over it) hands the chrome back to the terminal
    /// theme's owner, and coming back claims it for Changes again.
    @Test func changesClaimTheChromeAgainWhenAgentDetailComesBack() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(read), .success(read)])
        let composer = AgentComposerStore(target: "w1:p1") { _ in
            Agent(.fixture(paneID: "w1:p1"))
        }
        let attach = try await Self.makeLiveAttach(transport: transport, composer: composer)
        let suiteName = "changes-chrome-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let changes = AgentChangesPresentation {
            ChangesStore(directory: { "/home/dev/src/clean" }) { request in
                try await transport.readChanges(request)
            }
        }
        var shownChanges: [Bool] = []
        let detail = Self.makeDetail(
            attach: attach, composer: composer,
            inputMode: AgentInputModeSettings(defaults: defaults), defaults: defaults,
            changes: changes, onShowsChanges: { shownChanges.append($0) })
        let cover = CoveringPath()
        let controller = UIHostingController(
            rootView: CoverableStack(cover: cover, detail: detail))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874),
            rootViewController: controller)
        defer { window.isHidden = true }
        try #require(
            await ChangesViewTests.eventually {
                controller.view.layoutIfNeeded()
                return !AgentSurfaceReplacementTests.terminals(in: controller.view).isEmpty
            })

        changes.open()
        try #require(
            await ChangesViewTests.eventually {
                ChangesViewTests.labels(in: controller).contains(ChangesStore.cleanMessage)
            })
        #expect(shownChanges.last == true)

        cover.path = [1]
        let covered = try await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            return shownChanges.last == false
        }
        try #require(covered, "covering never released the chrome: \(shownChanges)")

        cover.path = []
        let reclaimed = try await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            return shownChanges.last == true
        }
        #expect(reclaimed, "Changes never reclaimed the chrome: \(shownChanges)")
        #expect(changes.store != nil)

        await attach.leave().value
    }

    private static func makeDetail(
        attach: AgentAttachStore,
        composer: AgentComposerStore,
        inputMode: AgentInputModeSettings,
        defaults: UserDefaults,
        changes: AgentChangesPresentation,
        agent: ConsoleAgent = AgentSurfaceReplacementTests.makeAgent(pane: "w1:p1"),
        isVisible: @escaping () -> Bool = { true },
        onShowsChanges: @escaping (Bool) -> Void
    ) -> AgentDetailView {
        detailBuilder(
            attach: attach, composer: composer, inputMode: inputMode, defaults: defaults,
            changes: changes, isVisible: isVisible, onShowsChanges: onShowsChanges)(agent)
    }

    /// Builds Agent detail for whichever value of its Agent the host hands
    /// it, over one Console and one set of settings, as the Console rebuilds
    /// its detail column when that Agent's state changes.
    private static func detailBuilder(
        attach: AgentAttachStore,
        composer: AgentComposerStore,
        inputMode: AgentInputModeSettings,
        defaults: UserDefaults,
        changes: AgentChangesPresentation,
        isVisible: @escaping () -> Bool = { true },
        onShowsChanges: @escaping (Bool) -> Void
    ) -> @MainActor (ConsoleAgent) -> AgentDetailView {
        let console = ConsoleStore(snapshotRetryDelay: .seconds(30)) { _, subscriptions in
            EventsSession(
                subscriptions: subscriptions,
                connect: { throw TransportError.sshUnreachable(detail: "fixture") },
                reconnectPolicy: .default,
                keepalive: .default)
        }
        let terminal = TerminalSettings(
            themes: TerminalThemeSettings(defaults: defaults),
            zoom: TerminalZoomSettings(defaults: defaults),
            fonts: TerminalFontSettings(defaults: defaults),
            snippets: SnippetStore(defaults: defaults))
        let activity = AppActivityCoordinator()
        let keyboardHandoff = TerminalKeyboardHandoff()
        let keyboardInset = TerminalKeyboardInset()
        return { agent in
            AgentDetailView(
                agent: agent,
                console: console,
                terminal: terminal,
                inputMode: inputMode,
                hosts: [],
                activity: activity,
                keyboardHandoff: keyboardHandoff,
                keyboardInset: keyboardInset,
                stage: AgentDetailStage(isVisible: isVisible, terminalAccess: { .holds }),
                onSwitch: { _ in },
                onClosed: {},
                onShowsChanges: onShowsChanges,
                composerStore: composer,
                attachStore: attach,
                changesPresentation: changes)
        }
    }

    private static func makeLiveAttach(
        transport: ScriptedTransport,
        composer: AgentComposerStore
    ) async throws -> AgentAttachStore {
        let attach = AgentAttachStore(
            target: "w1:p1",
            paneTitle: "Claude",
            transportGeneration: 1,
            isOnStage: { true },
            runTerminal: { request, handler in
                let session = try await transport.attachTerminal(request)
                try await handler.runEndingSession(session)
            },
            stageImage: { _, _ in throw TransportError.cancelled },
            stageFile: { _, _ in throw TransportError.cancelled },
            composer: composer,
            closePane: {})
        attach.viewDidResize(cols: 80, rows: 24)
        try #require(
            await ChangesViewTests.eventually { await transport.attachRequests.count == 1 })
        #expect(await transport.emitAttachOutput(Data("live".utf8)))
        try #require(
            await ChangesViewTests.eventually {
                attach.terminalStatus == AttachTerminalStore.Status.live
            })
        return attach
    }
    @Test(arguments: [AgentInputMode.composer, .direct])
    func insertingARemovedLineReturnsWithoutSendingAndWaitsForAttach(mode: AgentInputMode) async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.subdir)
        await transport.scriptChangesReads([.success(read), .success(read)])
        let patch = FilePatch(
            files: GitProbe.parsePatchFiles(Data("""
                diff --git a/pkg/modified.txt b/pkg/modified.txt
                @@ -1,3 +1,3 @@
                 first
                -old
                +new
                 last

                """.utf8), isTruncated: false), isTruncated: false)
        await transport.scriptFilePatchReads([.success(patch)])
        let composer = AgentComposerStore(target: "w1:p1") { params in
            try await transport.promptAgent(params)
        }
        composer.replaceDraft(with: "keep this draft")
        let attach = try await Self.makeLiveAttach(transport: transport, composer: composer)
        let suiteName = "changes-reference-detail-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let inputMode = AgentInputModeSettings(defaults: defaults)
        inputMode.select(mode)
        let changes = AgentChangesPresentation {
            ChangesStore(
                directory: { "/home/dev/src/app/pkg" },
                read: { try await transport.readChanges($0) },
                readPatch: { try await transport.readFilePatch($0) })
        }
        let detail = Self.makeDetail(
            attach: attach, composer: composer, inputMode: inputMode, defaults: defaults,
            changes: changes, onShowsChanges: { _ in })
        let controller = UIHostingController(rootView: NavigationStack { detail })
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874), rootViewController: controller)
        defer { window.isHidden = true }
        try #require(await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            return !AgentSurfaceReplacementTests.terminals(in: controller.view).isEmpty
        })

        changes.open()
        let store = try #require(changes.store)
        try #require(await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            return store.checkout != nil && attach.terminalStatus == .stopped
        })
        let file = ChangedFile(
            path: Data("pkg/modified.txt".utf8), originalPath: nil,
            kind: .modified, staging: .unstaged)
        store.openDiff(file)
        let diff = try #require(store.fileDiff.current)
        await diff.appear()
        try #require(await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains("Removed, line 2: old")
        })
        composer.setDraftSelection(NSRange(location: 5, length: 0))
        let gate = ScriptedTransportCallGate()
        defer { Task { await gate.open() } }
        if mode == .direct { await transport.gateNextAttach(using: gate) }

        store.insert(line: 1)
        try #require(await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            return changes.store == nil && !AgentSurfaceReplacementTests.terminals(in: controller.view).isEmpty
        })
        if mode == .direct {
            await gate.waitForEntry()
            #expect(await transport.attachInputs.compactMap(Self.keystrokes).isEmpty)
            await gate.open()
            try #require(await ChangesViewTests.eventually { attach.input.liveGeneration != nil })
            #expect(attach.terminalStatus == .connecting)
            #expect(await transport.attachInputs.compactMap(Self.keystrokes).isEmpty)
            #expect(await transport.emitAttachOutput(Data("rebuilt".utf8)))
            try #require(await ChangesViewTests.eventually {
                await transport.attachInputs.compactMap(Self.keystrokes) == [Data("modified.txt:2 ".utf8)]
            })
            #expect(composer.draft == "keep this draft")
        } else {
            try #require(await ChangesViewTests.eventually {
                composer.draft == "keep modified.txt:2 this draft"
            })
            #expect(await transport.attachInputs.compactMap(Self.keystrokes).isEmpty)
        }
        #expect(inputMode.mode == mode)
        #expect(composer.messages.isEmpty)
        #expect(await transport.agentPromptParams.isEmpty)
        await attach.leave().value
        let writes = await transport.attachInputs.compactMap(Self.keystrokes)
        #expect(writes == (mode == .direct ? [Data("modified.txt:2 ".utf8)] : []))
        #expect(!writes.contains { $0.contains(0x0D) || $0.contains(0x0A) })
    }

    nonisolated private static func keystrokes(_ input: TerminalAttachInput) -> Data? {
        if case .keystrokes(let data) = input { data } else { nil }
    }

    nonisolated private static func isResize(_ input: TerminalAttachInput) -> Bool {
        if case .resize = input { true } else { false }
    }

    private static func badgeValue(in controller: UIViewController) -> String? {
        AccessibilityProbe.elements(labeled: "Changes", in: controller.view).first?
            .accessibilityValue
    }

    /// The badge shows the Checkout's line totals beside the Composer
    /// control without resizing the terminal, opens Changes, and after Back
    /// still follows the Agent: its next Working exit updates the badge.
    @Test(arguments: [AgentInputMode.composer, .direct])
    func theBadgeShowsTheReadInTheSwitcherAndOpensChanges(mode: AgentInputMode) async throws {
        let transport = ScriptedTransport()
        let dirty = try ChangesBadgeTests.read(added: 12, removed: 7)
        let updated = try ChangesBadgeTests.read(added: 1, removed: 1)
        await transport.scriptChangesReads([.success(dirty), .success(dirty), .success(updated)])
        let hold = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: hold)
        let composer = AgentComposerStore(target: "w1:p1") { _ in
            Agent(.fixture(paneID: "w1:p1"))
        }
        let attach = try await Self.makeLiveAttach(transport: transport, composer: composer)
        let suiteName = "changes-badge-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let inputMode = AgentInputModeSettings(defaults: defaults)
        inputMode.select(mode)
        let feed = AgentChangesFollowTests.StatusFeed(.working)
        defer { feed.finish() }
        let changes = AgentChangesPresentation {
            ChangesStore(
                directory: { "/home/dev/src/tracking" },
                read: { try await transport.readChanges($0) },
                agentStatus: { feed.stream() })
        }
        let detail = Self.makeDetail(
            attach: attach, composer: composer, inputMode: inputMode, defaults: defaults,
            changes: changes, onShowsChanges: { _ in })
        let controller = UIHostingController(rootView: NavigationStack { detail })
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874), rootViewController: controller)
        defer { window.isHidden = true }
        try #require(
            await ChangesViewTests.eventually {
                controller.view.layoutIfNeeded()
                return !AgentSurfaceReplacementTests.terminals(in: controller.view).isEmpty
            })

        await hold.waitForEntry()
        controller.view.layoutIfNeeded()
        let terminal = try #require(AgentSurfaceReplacementTests.terminals(in: controller.view).first)
        let height = terminal.bounds.height
        let resizes = await transport.attachInputs.filter(Self.isResize).count
        #expect(Self.badgeValue(in: controller) == nil)
        await hold.open()
        let shown = try await ChangesViewTests.eventually {
            Self.badgeValue(in: controller) == "12 lines added, 7 lines removed"
        }
        try #require(shown, "the badge never showed the read")
        let root: UIView = controller.view
        #expect(AccessibilityProbe.elements(labeled: "Changes", in: root).count == 1)
        let modeLabel = mode == .composer
            ? AgentDirectInputPresentation.hideComposerAccessibilityLabel
            : AgentDirectInputPresentation.showComposerAccessibilityLabel
        let badgeFrame = try #require(AccessibilityProbe.frame(labeled: "Changes", in: root))
        let modeFrame = try #require(AccessibilityProbe.frame(labeled: modeLabel, in: root))
        #expect(badgeFrame.maxX <= modeFrame.minX + 0.5, "\(badgeFrame) overlaps \(modeFrame)")
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(30))
            controller.view.layoutIfNeeded()
            #expect(terminal.bounds.height == height)
        }
        #expect(await transport.attachInputs.filter(Self.isResize).count == resizes)

        try #require(await ChangesViewTests.eventually { ChangesViewTests.activate("Changes", in: root) })
        let opened = try await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains { $0.hasPrefix("Checkout ~/src/tracking") }
                && AgentSurfaceReplacementTests.terminals(in: controller.view).isEmpty
        }
        try #require(opened, "the badge never opened Changes")
        #expect(changes.store === changes.agentStore)
        try #require(await ChangesViewTests.eventually { await transport.changesReadRequests.count == 2 })

        try #require(await ChangesViewTests.eventually { ChangesViewTests.activate("Back", in: root) })
        try #require(
            await ChangesViewTests.eventually {
                controller.view.layoutIfNeeded()
                return changes.store == nil
                    && !AgentSurfaceReplacementTests.terminals(in: controller.view).isEmpty
            })
        #expect(changes.isFollowingAgent)
        feed.send(.done)
        let refreshed = try await ChangesViewTests.eventually {
            Self.badgeValue(in: controller) == "1 line added, 1 line removed"
        }
        #expect(refreshed, "leaving Working after Back never refreshed the badge")
        #expect(await transport.changesReadRequests.count == 3)
        await attach.leave().value
    }

    /// Switching Agents builds a new detail and store: the badge stays
    /// hidden until the new Agent's own read lands.
    @Test func switchingAgentsNeverShowsThePreviousAgentsNumbers() async throws {
        let first = ScriptedTransport()
        let second = ScriptedTransport()
        await first.scriptChangesReads([.success(try ChangesBadgeTests.read(added: 12, removed: 7))])
        await second.scriptChangesReads([.success(try ChangesBadgeTests.read(added: 1, removed: 1))])
        let hold = ScriptedTransportCallGate()
        await second.gateNextChangesRead(using: hold)
        let suiteName = "changes-badge-switch-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let inputMode = AgentInputModeSettings(defaults: defaults)
        let selection = DetailSelection()
        var details: [AgentDetailView] = []
        var presentations: [AgentChangesPresentation] = []
        var attaches: [AgentAttachStore] = []
        for (index, transport) in [first, second].enumerated() {
            let pane = "w1:p\(index + 1)"
            let composer = AgentComposerStore(target: pane) { _ in Agent(.fixture(paneID: pane)) }
            let attach = try await Self.makeLiveAttach(transport: transport, composer: composer)
            let changes = AgentChangesPresentation {
                ChangesStore(directory: { "/home/dev/src/tracking" }) {
                    try await transport.readChanges($0)
                }
            }
            details.append(
                Self.makeDetail(
                    attach: attach, composer: composer, inputMode: inputMode, defaults: defaults,
                    changes: changes, agent: AgentSurfaceReplacementTests.makeAgent(pane: pane),
                    isVisible: { selection.index == index }, onShowsChanges: { _ in }))
            presentations.append(changes)
            attaches.append(attach)
        }
        let controller = UIHostingController(
            rootView: SwitchingDetails(selection: selection, details: details))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874), rootViewController: controller)
        defer { window.isHidden = true }
        try #require(
            await ChangesViewTests.eventually {
                Self.badgeValue(in: controller) == "12 lines added, 7 lines removed"
            })

        selection.index = 1
        var sawBadge = false
        let deadline = ContinuousClock.now + .seconds(5)
        while await hold.entryCount == 0, ContinuousClock.now < deadline {
            if Self.badgeValue(in: controller) != nil { sawBadge = true }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await hold.entryCount == 1)
        #expect(Self.badgeValue(in: controller) == nil)
        #expect(!sawBadge, "a badge showed before the new Agent's read landed")
        #expect(!presentations[0].isFollowingAgent)
        #expect(presentations[1].isFollowingAgent)

        await hold.open()
        let shown = try await ChangesViewTests.eventually {
            Self.badgeValue(in: controller) == "1 line added, 1 line removed"
        }
        #expect(shown)
        #expect(await first.changesReadRequests.count == 1)
        for attach in attaches { await attach.leave().value }
    }

    /// An Agent that stops reporting a directory while its own Changes are
    /// open leaves them working: the read they started when they opened
    /// still lands, and Agent detail stops following only once they close.
    @Test func losingTheDirectoryWhileTheAgentsChangesAreOpenKeepsTheirRead() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesBadgeTests.read(added: 12, removed: 7)
        await transport.scriptChangesReads([.success(read)])
        let composer = AgentComposerStore(target: "w1:p1") { _ in
            Agent(.fixture(paneID: "w1:p1"))
        }
        let attach = try await Self.makeLiveAttach(transport: transport, composer: composer)
        let suiteName = "changes-lost-directory-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let gate = GitExecGate()
        let clock = ChangesManualSleeper()
        let feed = AgentChangesFollowTests.StatusFeed(.idle)
        defer { feed.finish() }
        let changes = AgentChangesFollowTests.presentation(
            transport: transport, gate: gate, clock: clock, feed: feed)
        let host = UUID()
        let shown = ShownAgent(AgentSurfaceReplacementTests.makeAgent(pane: "w1:p1", host: host))
        let controller = UIHostingController(
            rootView: ChangingAgentDetail(
                shown: shown,
                detail: Self.detailBuilder(
                    attach: attach, composer: composer,
                    inputMode: AgentInputModeSettings(defaults: defaults), defaults: defaults,
                    changes: changes, onShowsChanges: { _ in })))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874), rootViewController: controller)
        defer { window.isHidden = true }
        try #require(
            await ChangesViewTests.eventually {
                controller.view.layoutIfNeeded()
                return !AgentSurfaceReplacementTests.terminals(in: controller.view).isEmpty
            })
        #expect(changes.isFollowingAgent)

        // Another git exec on this Host holds the gate, so the read Changes
        // start on opening waits for it.
        let other = ScriptedTransportCallGate()
        let holder = Task { try await gate.run { await other.waitUntilOpen() } }
        await other.waitForEntry()
        changes.open()
        let store = try #require(changes.store)
        try #require(
            await ChangesViewTests.eventually {
                controller.view.layoutIfNeeded()
                return store.activeRead != nil
            })

        shown.agent = Self.agentWithoutDirectory(pane: "w1:p1", host: host)
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(20))
            controller.view.layoutIfNeeded()
        }
        #expect(changes.isFollowingAgent)

        await other.open()
        try await holder.value
        let landed = try await ChangesViewTests.eventually { store.phase == .loaded(read.changes) }
        #expect(landed, "losing the directory dropped the read Changes started: \(store.phase)")
        #expect(await transport.changesReadRequests.count == 1)

        try #require(
            await ChangesViewTests.eventually {
                ChangesViewTests.activate("Back", in: controller.view)
            })
        let stopped = try await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            return changes.store == nil && !changes.isFollowingAgent
        }
        #expect(stopped, "Back kept following an Agent without a directory")
        await attach.leave().value
    }

    private static func agentWithoutDirectory(pane: String, host: UUID) -> ConsoleAgent {
        ConsoleAgent(
            hostID: host,
            hostName: "devbox",
            agent: Agent(
                terminalID: "term_\(pane)", kind: "claude", title: "",
                status: .idle, workspaceID: "w", tabID: "w:t", paneID: pane,
                cwd: "", revision: 1, name: nil),
            workspaceLabel: nil,
            repositoryCheckout: nil,
            lastOutputSnippet: nil)
    }

    @Test func anAgentWithoutADirectoryHasNoBadge() async throws {
        let transport = ScriptedTransport()
        let composer = AgentComposerStore(target: "w1:p1") { _ in
            Agent(.fixture(paneID: "w1:p1"))
        }
        let attach = try await Self.makeLiveAttach(transport: transport, composer: composer)
        let suiteName = "changes-badge-none-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let changes = AgentChangesPresentation {
            ChangesStore(directory: { nil }) { try await transport.readChanges($0) }
        }
        let agent = ConsoleAgent(
            hostID: UUID(),
            hostName: "devbox",
            agent: Agent(
                terminalID: "term_w1:p1", kind: "claude", title: "",
                status: .idle, workspaceID: "w", tabID: "w:t", paneID: "w1:p1",
                cwd: "", revision: 1, name: nil),
            workspaceLabel: nil,
            repositoryCheckout: nil,
            lastOutputSnippet: nil)
        #expect(agent.directory == nil)
        let detail = Self.makeDetail(
            attach: attach, composer: composer,
            inputMode: AgentInputModeSettings(defaults: defaults), defaults: defaults,
            changes: changes, agent: agent, onShowsChanges: { _ in })
        let controller = UIHostingController(rootView: NavigationStack { detail })
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874), rootViewController: controller)
        defer { window.isHidden = true }
        try #require(
            await ChangesViewTests.eventually {
                controller.view.layoutIfNeeded()
                return !AgentSurfaceReplacementTests.terminals(in: controller.view).isEmpty
            })
        try await Task.sleep(for: .milliseconds(600))
        #expect(Self.badgeValue(in: controller) == nil)
        #expect(await transport.changesReadRequests.isEmpty)
        #expect(changes.agentStore == nil)
        #expect(!changes.isFollowingAgent)
        await attach.leave().value
    }
}

/// The Agent a hosted switch shows, as the Console's selection.
@MainActor
@Observable
private final class DetailSelection {
    var index = 0
}

/// Keys each detail by the selection, as the Console keys its detail column
/// by Agent, so a switch builds a new detail rather than reusing one.
private struct SwitchingDetails: View {
    let selection: DetailSelection
    let details: [AgentDetailView]

    var body: some View {
        NavigationStack {
            details[selection.index].id(selection.index)
        }
    }
}

/// The Agent value a hosted detail is built from, as the Console hands its
/// detail column the Agent's latest state.
@MainActor
@Observable
private final class ShownAgent {
    var agent: ConsoleAgent

    init(_ agent: ConsoleAgent) { self.agent = agent }
}

/// Rebuilds one detail from the Agent's latest value while keeping its
/// identity, as the Console does while the selection stays on that Agent.
private struct ChangingAgentDetail: View {
    let shown: ShownAgent
    let detail: @MainActor (ConsoleAgent) -> AgentDetailView

    var body: some View {
        NavigationStack { detail(shown.agent) }
    }
}

/// A navigation path the test drives to push a view over Agent detail.
@MainActor
@Observable
private final class CoveringPath {
    var path: [Int] = []
}

private struct CoverableStack: View {
    @Bindable var cover: CoveringPath
    let detail: AgentDetailView

    var body: some View {
        NavigationStack(path: $cover.path) {
            detail.navigationDestination(for: Int.self) { _ in Text("Covering") }
        }
    }
}
