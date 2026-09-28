import Foundation

/// `git status --porcelain=v2 -z --branch`: NUL-terminated records, handled
/// as bytes and keyed by the raw bytes of their paths.
extension GitProbe {
    struct StatusReport: Sendable, Equatable {
        var branch: CheckoutHead.Branch = .detached
        /// `# branch.oid`; nil while HEAD is unborn (`(initial)`).
        var commit: String?
        /// Conflicted files first, then by raw path bytes.
        var files: [ChangedFile] = []
        var upstream: CheckoutUpstream? = nil
        var isUnborn = false
        /// Retained separately so branch headers can arrive in either order.
        var divergence: CheckoutUpstream.State? = nil
    }

    /// A body cut at its cap loses its last, partial record (and a rename
    /// whose original path was cut off); every complete record is kept.
    static func parseStatus(_ body: Data) -> StatusReport {
        var records = body.split(separator: 0, omittingEmptySubsequences: false)
        // Complete output ends in NUL, leaving an empty final element; a cut
        // one ends inside its last record.
        if !records.isEmpty { records.removeLast() }
        var report = StatusReport()
        var tracked: [TrackedEntry] = []
        var movedAway: [Data] = []
        var index = records.startIndex
        while index < records.endIndex {
            let record = Data(records[index])
            index += 1
            guard let type = record.first else { continue }
            switch type {
            case UInt8(ascii: "#"):
                applyHeader(record, to: &report)
            case UInt8(ascii: "1"):
                if let entry = ordinaryEntry(record) { tracked.append(entry) }
            case UInt8(ascii: "2"):
                // The original path is the next record.
                guard index < records.endIndex else { continue }
                let originalPath = Data(records[index])
                index += 1
                if let (entry, movedFrom) = renamedEntry(record, originalPath: originalPath) {
                    tracked.append(entry)
                    if let movedFrom { movedAway.append(movedFrom) }
                }
            case UInt8(ascii: "u"):
                if let (_, path) = fields(record, count: 9) {
                    report.files.append(
                        ChangedFile(
                            path: path, originalPath: nil, kind: .conflicted, staging: nil))
                }
            case UInt8(ascii: "?"):
                if let (_, path) = fields(record, count: 0) {
                    report.files.append(
                        ChangedFile(
                            path: path, originalPath: nil, kind: .untracked, staging: nil))
                }
            default:
                // `!` (ignored) is never requested; anything newer is skipped.
                continue
            }
        }
        markDeletedFromWorkingTree(movedAway, in: &tracked, besides: report.files)
        report.files.append(contentsOf: tracked.map(\.file))
        report.files.sort(by: listsBefore)
        return report
    }

    /// A `1` or `2` record's status letters, kept until every record is read
    /// because a later record can change an earlier one's working-tree side.
    private struct TrackedEntry {
        let path: Data
        /// A staged rename's previous path.
        let originalPath: Data?
        let index: UInt8
        var worktree: UInt8

        var file: ChangedFile {
            let kind: ChangedFile.Kind =
                if originalPath != nil {
                    .renamed
                } else if index == UInt8(ascii: "A") || worktree == UInt8(ascii: "A") {
                    .added
                } else if index == UInt8(ascii: "D") || worktree == UInt8(ascii: "D") {
                    .deleted
                } else {
                    .modified
                }
            return ChangedFile(
                path: path, originalPath: originalPath, kind: kind,
                staging: GitProbe.staging(index: index, worktree: worktree))
        }
    }

    /// The original paths of working-tree renames are still in the index but
    /// gone from the working tree. One with a record of its own (a staged
    /// rename moved on) gains the deletion there, as git reports it without
    /// `git add -N` (`RD`); any other becomes an unstaged deletion (`.D`).
    private static func markDeletedFromWorkingTree(
        _ paths: [Data], in tracked: inout [TrackedEntry], besides others: [ChangedFile]
    ) {
        guard !paths.isEmpty else { return }
        var positions: [Data: Int] = [:]
        for (position, entry) in tracked.enumerated() { positions[entry.path] = position }
        let otherPaths = Set(others.map(\.path))
        for path in paths {
            if let position = positions[path] {
                tracked[position].worktree = UInt8(ascii: "D")
            } else if !otherPaths.contains(path) {
                positions[path] = tracked.count
                tracked.append(
                    TrackedEntry(
                        path: path, originalPath: nil, index: UInt8(ascii: "."),
                        worktree: UInt8(ascii: "D")))
            }
        }
    }

    private static func listsBefore(_ lhs: ChangedFile, _ rhs: ChangedFile) -> Bool {
        let lhsConflicted = lhs.kind == .conflicted
        let rhsConflicted = rhs.kind == .conflicted
        if lhsConflicted != rhsConflicted { return lhsConflicted }
        return lhs.path.lexicographicallyPrecedes(rhs.path)
    }

    private static func applyHeader(_ record: Data, to report: inout StatusReport) {
        let text = String(decoding: record, as: UTF8.self)
        if let value = headerValue(text, key: "# branch.oid ") {
            report.commit = value == "(initial)" ? nil : value
            report.isUnborn = value == "(initial)"
            // Without HEAD, a missing branch.ab says nothing about whether
            // the upstream exists. Also handle an upstream header seen first.
            report.upstream?.state = report.divergence ?? (report.isUnborn ? .unknown : .deleted)
        } else if let value = headerValue(text, key: "# branch.head ") {
            report.branch = value == "(detached)" ? .detached : .named(value)
        } else if let value = headerValue(text, key: "# branch.upstream "), !value.isEmpty {
            report.upstream = CheckoutUpstream(
                name: value, state: report.divergence ?? (report.isUnborn ? .unknown : .deleted))
        } else if let value = headerValue(text, key: "# branch.ab ") {
            let state = parseDivergence(value)
            report.divergence = state
            report.upstream?.state = state
        }
    }

    private static func headerValue(_ text: String, key: String) -> String? {
        guard text.hasPrefix(key) else { return nil }
        return String(text.dropFirst(key.count))
    }

    /// `1 XY sub mH mI mW hH hI path`.
    private static func ordinaryEntry(_ record: Data) -> TrackedEntry? {
        guard let (fields, path) = fields(record, count: 7),
            let (index, worktree) = statusPair(fields[0])
        else { return nil }
        return TrackedEntry(path: path, originalPath: nil, index: index, worktree: worktree)
    }

    /// `2 XY sub mH mI mW hH hI Xscore path` followed by the original path.
    /// Git never reports a rename on both sides of one path (wt-status.c
    /// treats that as a bug). `X` is `R` for a staged rename. `Y` is `R` for
    /// a working-tree rename, which git detects only against an intent-to-add
    /// entry (`git add -N`): status pairs only staged renames, so the new
    /// path reads as added and the original, returned as `movedFrom`, as
    /// deleted from the working tree. A copy (`C`, ruled out by
    /// `status.renames=true` wherever git knows that key) leaves its original
    /// in place, so the new path reads as added.
    private static func renamedEntry(
        _ record: Data, originalPath: Data
    ) -> (entry: TrackedEntry, movedFrom: Data?)? {
        guard let (fields, path) = fields(record, count: 8),
            let (index, worktree) = statusPair(fields[0])
        else { return nil }
        let renamed = UInt8(ascii: "R")
        let copied = UInt8(ascii: "C")
        let added = UInt8(ascii: "A")
        if index == renamed {
            let entry = TrackedEntry(
                path: path, originalPath: originalPath, index: index, worktree: worktree)
            return (entry, nil)
        }
        let entry = TrackedEntry(
            path: path, originalPath: nil,
            index: index == copied ? added : index,
            worktree: worktree == renamed || worktree == copied ? added : worktree)
        return (entry, worktree == renamed ? originalPath : nil)
    }

    private static func statusPair(_ field: Data) -> (UInt8, UInt8)? {
        guard field.count == 2 else { return nil }
        return (field[field.startIndex], field[field.startIndex + 1])
    }

    private static func staging(index: UInt8, worktree: UInt8) -> ChangedFile.Staging? {
        let unchanged = UInt8(ascii: ".")
        switch (index != unchanged, worktree != unchanged) {
        case (true, true): return .both
        case (true, false): return .staged
        case (false, true): return .unstaged
        case (false, false): return nil
        }
    }

    /// Splits the record type and the `count` space-separated fields after
    /// it; the rest of the record, spaces included, is the path.
    private static func fields(_ record: Data, count: Int) -> ([Data], Data)? {
        var fields: [Data] = []
        var start = record.startIndex
        // Field 0 is the record type itself.
        for _ in 0...count {
            guard let space = record[start...].firstIndex(of: UInt8(ascii: " ")) else {
                return nil
            }
            fields.append(Data(record[start..<space]))
            start = record.index(after: space)
        }
        let path = Data(record[start...])
        guard !path.isEmpty else { return nil }
        return (Array(fields.dropFirst()), path)
    }
}
