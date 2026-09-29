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
        onShowsChanges: @escaping (Bool) -> Void
    ) -> AgentDetailView {
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
        return AgentDetailView(
            agent: AgentSurfaceReplacementTests.makeAgent(pane: "w1:p1"),
            console: console,
            terminal: terminal,
            inputMode: inputMode,
            hosts: [],
            activity: AppActivityCoordinator(),
            keyboardHandoff: TerminalKeyboardHandoff(),
            keyboardInset: TerminalKeyboardInset(),
            stage: AgentDetailStage(isVisible: { true }, terminalAccess: { .holds }),
            onSwitch: { _ in },
            onClosed: {},
            onShowsChanges: onShowsChanges,
            composerStore: composer,
            attachStore: attach,
            changesPresentation: changes)
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
