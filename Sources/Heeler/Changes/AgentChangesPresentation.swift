import Observation

/// Changes shown in place of Agent detail, as the Shell Terminal is. Held in
/// Agent detail's own state, so it closes with Agent detail (another Agent or
/// terminal selected, the Host leaving Connected, the Agent exiting), and it
/// holds the only reference to its store, so closing discards the content.
@MainActor
@Observable
final class AgentChangesPresentation {
    /// The open Changes; nil while Agent detail shows its terminal.
    private(set) var store: ChangesStore?

    @ObservationIgnored private let makeStore: @MainActor () -> ChangesStore

    init(makeStore: @escaping @MainActor () -> ChangesStore) {
        self.makeStore = makeStore
    }

    /// Opens Changes; a second open while one is shown keeps it.
    func open() {
        guard store == nil else { return }
        store = makeStore()
    }

    /// Back: returns to Agent detail and drops the document.
    func close() {
        store = nil
    }
}
