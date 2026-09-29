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

    func insertionText(forLine lineID: DiffLine.ID) -> String? {
        guard let diff = fileDiff.current,
            let (line, hunk) = lineAndHunk(lineID),
            let path = referencePath(file: diff.file, checkout: diff.checkout),
            let number = ChangesReference.lineNumber(of: line, in: hunk)
        else { return nil }
        return ChangesReference.insertion("\(path):\(number)")
    }

    func insert(line lineID: DiffLine.ID) {
        guard let text = insertionText(forLine: lineID) else { return }
        insertReference?(text)
    }

    func copyPath(_ file: ChangedFile) {
        guard let path = pathReference(for: file) else { return }
        copyToPasteboard?(path)
    }

    /// Diff sections in an edited rename all refer to the opened status path.
    var diffPathReference: String? {
        guard let diff = fileDiff.current else { return nil }
        return referencePath(file: diff.file, checkout: diff.checkout)
    }

    var diffPathInsertionText: String? {
        diffPathReference.flatMap(ChangesReference.insertion)
    }

    func copyDiffPath() {
        guard let path = diffPathReference else { return }
        copyToPasteboard?(path)
    }

    func insertDiffPath() {
        guard let text = diffPathInsertionText else { return }
        insertReference?(text)
    }

    func copyLine(_ lineID: DiffLine.ID) {
        guard let (line, _) = lineAndHunk(lineID) else { return }
        copyToPasteboard?(line.text)
    }

    func copyHunk(_ hunkID: DiffHunk.ID) {
        guard let diff = fileDiff.current, case .loaded(let patch) = diff.phase,
            let hunk = patch.files.lazy.flatMap(\.hunks).first(where: { $0.id == hunkID })
        else { return }
        copyToPasteboard?(ChangesReference.hunkText(hunk))
    }

    func copyHunk(containingLine lineID: DiffLine.ID) {
        guard let (_, hunk) = lineAndHunk(lineID) else { return }
        copyToPasteboard?(ChangesReference.hunkText(hunk))
    }

    private func lineAndHunk(_ lineID: DiffLine.ID) -> (DiffLine, DiffHunk)? {
        guard let diff = fileDiff.current, case .loaded(let patch) = diff.phase else { return nil }
        for file in patch.files {
            for hunk in file.hunks {
                if let line = hunk.lines.first(where: { $0.id == lineID }) {
                    return (line, hunk)
                }
            }
        }
        return nil
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
