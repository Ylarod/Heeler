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
    }

    /// A body cut at its cap loses its last, partial record (and a rename
    /// whose original path was cut off); every complete record is kept.
    static func parseStatus(_ body: Data) -> StatusReport {
        var records = body.split(separator: 0, omittingEmptySubsequences: false)
        // Complete output ends in NUL, leaving an empty final element; a cut
        // one ends inside its last record.
        if !records.isEmpty { records.removeLast() }
        var report = StatusReport()
        var index = records.startIndex
        while index < records.endIndex {
            let record = Data(records[index])
            index += 1
            guard let type = record.first else { continue }
            switch type {
            case UInt8(ascii: "#"):
                applyHeader(record, to: &report)
            case UInt8(ascii: "1"):
                if let file = ordinaryEntry(record) { report.files.append(file) }
            case UInt8(ascii: "2"):
                // The original path is the next record.
                guard index < records.endIndex else { continue }
                let originalPath = Data(records[index])
                index += 1
                if let file = renamedEntry(record, originalPath: originalPath) {
                    report.files.append(file)
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
        report.files.sort(by: listsBefore)
        return report
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
        } else if let value = headerValue(text, key: "# branch.head ") {
            report.branch = value == "(detached)" ? .detached : .named(value)
        }
    }

    private static func headerValue(_ text: String, key: String) -> String? {
        guard text.hasPrefix(key) else { return nil }
        return String(text.dropFirst(key.count))
    }

    /// `1 XY sub mH mI mW hH hI path`.
    private static func ordinaryEntry(_ record: Data) -> ChangedFile? {
        guard let (fields, path) = fields(record, count: 7),
            let (index, worktree) = statusPair(fields[0])
        else { return nil }
        let kind: ChangedFile.Kind =
            if index == UInt8(ascii: "A") || worktree == UInt8(ascii: "A") {
                .added
            } else if index == UInt8(ascii: "D") || worktree == UInt8(ascii: "D") {
                .deleted
            } else {
                .modified
            }
        return ChangedFile(
            path: path, originalPath: nil, kind: kind,
            staging: staging(index: index, worktree: worktree))
    }

    /// `2 XY sub mH mI mW hH hI Xscore path` followed by the original path.
    /// With rename detection on and copies off, X is `R`.
    private static func renamedEntry(_ record: Data, originalPath: Data) -> ChangedFile? {
        guard let (fields, path) = fields(record, count: 8),
            let (index, worktree) = statusPair(fields[0])
        else { return nil }
        let isRename = index == UInt8(ascii: "R")
        return ChangedFile(
            path: path,
            originalPath: isRename ? originalPath : nil,
            kind: isRename ? .renamed : .added,
            staging: staging(index: index, worktree: worktree))
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
