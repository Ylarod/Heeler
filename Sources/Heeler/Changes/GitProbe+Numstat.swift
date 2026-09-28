import Foundation

/// Numeric counts are read from the same exec as status. Paths stay as bytes:
/// a tab or newline inside a name is data, and rename paths are NUL-delimited.
extension GitProbe {
    fileprivate struct CountedPath: Hashable {
        let path: Data
        var originalPath: Data? = nil
    }

    struct NumstatReport {
        fileprivate var records: [CountedPath: LineCounts] = [:]
        var linesAreComplete = true
        var linesAreAvailable = true
    }

    static func countedFiles(_ files: [ChangedFile], numstat: NumstatReport) -> [ChangedFile] {
        let records = numstat.records
        return files.map { file in
            var file = file
            guard file.kind != .untracked else { return file }
            file.lineCounts = records[CountedPath(path: file.path, originalPath: file.originalPath)]
            // Status pairs staged renames against the index. A rewrite in
            // the working tree can make diff against HEAD split that same
            // rename into an addition and a deletion. Require both records:
            // a cut or differently paired diff cannot supply exact counts.
            if file.lineCounts == nil, let originalPath = file.originalPath,
                let added = records[CountedPath(path: file.path)],
                let removed = records[CountedPath(path: originalPath)]
            {
                file.lineCounts = combinedCounts(added, removed)
            }
            return file
        }
    }

    private static func combinedCounts(_ lhs: LineCounts, _ rhs: LineCounts) -> LineCounts? {
        if case .lines(let leftAdded, let leftRemoved) = lhs,
            case .lines(let rightAdded, let rightRemoved) = rhs
        {
            let added = leftAdded.addingReportingOverflow(rightAdded)
            let removed = leftRemoved.addingReportingOverflow(rightRemoved)
            guard !added.overflow, !removed.overflow else { return nil }
            return .lines(added: added.partialValue, removed: removed.partialValue)
        }
        return .binary
    }

    static func changesTotals(_ files: [ChangedFile], numstat: NumstatReport) -> ChangesTotals {
        var totals = ChangesTotals()
        totals.untrackedItems = files.filter { $0.kind == .untracked }.count
        totals.trackedFiles = files.count - totals.untrackedItems
        totals.linesAreAvailable = numstat.linesAreAvailable
        totals.linesAreComplete = numstat.linesAreComplete
        for counts in numstat.records.values {
            if case .lines(let added, let removed) = counts {
                let sumAdded = totals.added.addingReportingOverflow(added)
                let sumRemoved = totals.removed.addingReportingOverflow(removed)
                totals.added = sumAdded.overflow ? Int.max : sumAdded.partialValue
                totals.removed = sumRemoved.overflow ? Int.max : sumRemoved.partialValue
                if sumAdded.overflow || sumRemoved.overflow { totals.linesAreComplete = false }
            }
        }
        return totals
    }

    static func parseNumstat(_ section: Section) -> NumstatReport {
        var report = NumstatReport()
        report.linesAreAvailable = section.status == 0 || section.isTruncated
        report.linesAreComplete = report.linesAreAvailable && !section.isTruncated
        guard report.linesAreAvailable else { return report }
        if !section.body.isEmpty, section.body.last != 0 { report.linesAreComplete = false }
        var records = section.body.split(separator: 0, omittingEmptySubsequences: false)
        // The last element is empty after a terminating NUL, or an incomplete
        // record at the cap. A rename is kept only with both complete paths.
        if !records.isEmpty { records.removeLast() }
        var index = records.startIndex
        while index < records.endIndex {
            let fields = records[index].split(
                separator: 0x09, maxSplits: 2, omittingEmptySubsequences: false)
            index += 1
            guard fields.count == 3 else {
                report.linesAreComplete = false
                continue
            }
            var path = CountedPath(path: Data(fields[2]))
            if fields[2].isEmpty {
                guard index + 1 < records.endIndex else {
                    report.linesAreComplete = false
                    break
                }
                path = CountedPath(path: Data(records[index + 1]), originalPath: Data(records[index]))
                index += 2
            }
            guard !path.path.isEmpty, path.originalPath?.isEmpty != true else {
                report.linesAreComplete = false
                continue
            }
            let value: LineCounts
            if fields[0].elementsEqual([0x2D]), fields[1].elementsEqual([0x2D]) {
                value = .binary
            } else if let added = decimalCount(fields[0]), let removed = decimalCount(fields[1]) {
                value = .lines(added: added, removed: removed)
            } else {
                report.linesAreComplete = false
                continue
            }
            // Some unmerged forms emit a zero placeholder beside the real
            // record. Keep the nonzero counts once, in either order.
            if let previous = report.records[path] {
                if value == .lines(added: 0, removed: 0) || value == previous { continue }
                if previous != .lines(added: 0, removed: 0) {
                    report.linesAreComplete = false
                    continue
                }
            }
            report.records[path] = value
        }
        return report
    }

    private static func decimalCount(_ bytes: Data.SubSequence) -> Int? {
        guard !bytes.isEmpty, bytes.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return Int(String(decoding: bytes, as: UTF8.self))
    }
}
