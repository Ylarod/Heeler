import Observation
import UIKit

/// Changes shown in place of Agent detail, as the Shell Terminal is. Held in
/// Agent detail's own state, so it goes with Agent detail (another Agent or
/// terminal selected, the Host leaving Connected, the Agent exiting).
///
/// The Agent's own Changes keep one store for that whole lifetime: the Agent
/// switcher's badge reads it while Changes is closed, and Changes shows it,
/// so neither reads twice and Back hands Changes' latest read to the badge.
/// Worktree Changes get a store of their own, which closing discards.
@MainActor
@Observable
final class AgentChangesPresentation {
    /// The open Changes; nil while Agent detail shows its terminal.
    private(set) var store: ChangesStore?
    /// The Agent's own Changes, following its current directory. Created on
    /// first use and kept until Agent detail goes.
    private(set) var agentStore: ChangesStore?
    @ObservationIgnored private var pendingInsertion: String?
    /// Agent detail's reads for the badge. Owned here rather than by a
    /// SwiftUI task, which restarts when Changes and the terminal swap.
    @ObservationIgnored private var following: Task<Void, Never>?

    /// Nil follows the Agent. A Worktree directory stays fixed for the
    /// life of that store, even if the Agent later moves.
    @ObservationIgnored private let makeStoreIn: @MainActor (String?) -> ChangesStore

    init(makeStoreIn: @escaping @MainActor (_ directory: String?) -> ChangesStore) {
        self.makeStoreIn = makeStoreIn
    }

    /// The Agent menu, which follows the Agent's current directory.
    convenience init(makeStore: @escaping @MainActor () -> ChangesStore) {
        self.init(makeStoreIn: { _ in makeStore() })
    }

    deinit {
        following?.cancel()
    }

    var isFollowingAgent: Bool { following != nil }

    /// The Agent's own store, created on first use.
    func ensureAgentStore() -> ChangesStore {
        if let agentStore { return agentStore }
        let store = makeStoreIn(nil)
        store.referencesFollowAgentDirectory = true
        store.announcesAutomaticUpdates = false
        // Worktree Changes of this same Checkout follow the same Agent and
        // read for each exit from Working; Back hands their read over.
        store.automaticRefreshIsCoveredElsewhere = { [weak self, weak store] in
            guard let self, let store, let shown = self.store, shown !== store,
                let own = store.checkout, let other = shown.checkout
            else { return false }
            return own.topLevel == other.topLevel
        }
        prepare(store)
        agentStore = store
        return store
    }

    /// Agent detail is on screen: read once it settles, then whenever the
    /// Agent leaves Working. A second start while following keeps it.
    func startFollowingAgent() {
        guard following == nil else { return }
        let store = ensureAgentStore()
        following = Task { await store.followForAgentDetail() }
    }

    /// Agent detail left the screen: no more reads for it, and a read still
    /// queued at the Host gate is dropped.
    func stopFollowingAgent() {
        guard let following else { return }
        following.cancel()
        self.following = nil
        agentStore?.stopFollowingForAgentDetail()
    }

    /// Opens Changes. `directory` is a Worktree's checkout path; nil shows
    /// the Agent's own store. A second open while one is shown keeps it.
    func open(directory: String? = nil) {
        guard store == nil else { return }
        pendingInsertion = nil
        let store: ChangesStore
        if let directory {
            store = makeStoreIn(directory)
            store.referencesFollowAgentDirectory = false
            prepare(store)
        } else {
            store = ensureAgentStore()
        }
        store.announcesAutomaticUpdates = true
        self.store = store
    }

    /// Back: returns to Agent detail. The Agent's store keeps its document
    /// for the badge; a Worktree's store is dropped.
    func close() {
        pendingInsertion = nil
        leaveShown()
    }

    /// Agent detail takes this after acquiring the Attach it will actually show.
    func takePendingInsertion() -> String? {
        defer { pendingInsertion = nil }
        return pendingInsertion
    }

    private func prepare(_ store: ChangesStore) {
        if store.copyToPasteboard == nil {
            store.copyToPasteboard = { UIPasteboard.general.string = $0 }
        }
        // Only the shown store inserts, so a departing menu cannot hand
        // another reference to the next view.
        store.insertReference = { [weak self, weak store] text in
            guard let self, let store, self.store === store else { return }
            self.pendingInsertion = text
            self.leaveShown()
        }
    }

    private func leaveShown() {
        guard let shown = store else { return }
        store = nil
        if shown === agentStore {
            shown.leavePresentation()
        } else if let agentStore {
            agentStore.adoptNewerRead(of: shown)
            agentStore.resumeAutomaticRefresh(after: shown)
        }
    }
}

extension AgentChangesPresentation {
    /// Agent detail's Changes: the Console's reads through the Host's git
    /// exec gate, following the Agent's directory and status.
    static func forAgentDetail(
        agentID: ConsoleAgent.ID,
        hostID: Host.ID,
        openingDirectory: String?,
        console: ConsoleStore
    ) -> AgentChangesPresentation {
        AgentChangesPresentation { [console] fixedDirectory in
            ChangesStore(
                // Where the Agent is now: a later read follows it into
                // another Checkout.
                directory: {
                    fixedDirectory ?? console.agents.first { $0.id == agentID }?.directory
                        ?? openingDirectory
                },
                read: { request in
                    try await console.readChanges(request, on: hostID)
                },
                readPatch: { request in
                    try await console.readFilePatch(request, on: hostID)
                },
                listUntrackedDirectory: { request in
                    try await console.listUntrackedDirectory(request, on: hostID)
                },
                gate: console.gitExecGate(for: hostID),
                agentStatus: { [console] in console.agentStatusUpdates(for: agentID) })
        }
    }
}
