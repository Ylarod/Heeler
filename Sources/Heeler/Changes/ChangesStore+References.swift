import Foundation

extension ChangesStore {
    func pathReference(for file: ChangedFile) -> String? {
        guard let checkout else { return nil }
        return referencePath(file: file, checkout: checkout)
    }

    func insertionText(for file: ChangedFile) -> String? {
        pathReference(for: file).flatMap(ChangesReference.insertion)
    }

    func insert(file: ChangedFile) {
        guard let text = insertionText(for: file) else { return }
        insertReference?(text)
    }

    private func referencePath(file: ChangedFile, checkout location: CheckoutLocation) -> String? {
        // A failed refresh may leave an open diff but no trustworthy prefix.
        // A fixed Worktree directory is not the Agent's directory either.
        let prefix = referencesFollowAgentDirectory && checkout?.topLevel == location.topLevel
            ? directoryPrefix : nil
        return ChangesReference.path(
            file: file.path, topLevel: location.topLevel, directoryPrefix: prefix)
    }
}
