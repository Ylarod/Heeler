import Observation
import UIKit

/// Changes shown in place of Agent detail, as the Shell Terminal is. Held in
/// Agent detail's own state, so it closes with Agent detail (another Agent or
/// terminal selected, the Host leaving Connected, the Agent exiting), and it
/// holds the only reference to its store, so closing discards the content.
@MainActor
@Observable
final class AgentChangesPresentation {
    /// The open Changes; nil while Agent detail shows its terminal.
    private(set) var store: ChangesStore?
    @ObservationIgnored private var pendingInsertion: String?

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

    /// Opens Changes. `directory` is a Worktree's checkout path; nil follows
    /// the Agent. A second open while one is shown keeps it.
    func open(directory: String? = nil) {
        guard store == nil else { return }
        pendingInsertion = nil
        let store = makeStoreIn(directory)
        store.referencesFollowAgentDirectory = directory == nil
        if store.copyToPasteboard == nil {
            store.copyToPasteboard = { UIPasteboard.general.string = $0 }
        }
        store.insertReference = { [weak self, weak store] text in
            guard let self, let store, self.store === store else { return }
            self.pendingInsertion = text
            self.store = nil
        }
        self.store = store
    }

    /// Back: returns to Agent detail and drops the document.
    func close() {
        pendingInsertion = nil
        store = nil
    }

    /// Agent detail takes this after acquiring the Attach it will actually show.
    func takePendingInsertion() -> String? {
        defer { pendingInsertion = nil }
        return pendingInsertion
    }
}
