import Foundation

/// Numeric counts are read from the same exec as status. Paths stay as bytes:
/// a tab or newline inside a name is data, and rename paths are NUL-delimited.
extension GitProbe {
    private struct CountedPath: Hashable {
        let path: Data
        var originalPath: Data? = nil
    }

    static func countedFiles(_ files: [ChangedFile], numstat: Section) -> [ChangedFile] {
        let records = numstatRecords(numstat)
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

    static func changesTotals(_ files: [ChangedFile], numstat: Section) -> ChangesTotals {
        var totals = ChangesTotals()
        totals.untrackedItems = files.filter { $0.kind == .untracked }.count
        totals.trackedFiles = files.count - totals.untrackedItems
        totals.linesAreAvailable = numstat.status == 0 || numstat.isTruncated
        totals.linesAreComplete = totals.linesAreAvailable && !numstat.isTruncated
        for counts in numstatRecords(numstat).values {
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

    private static func numstatRecords(_ section: Section) -> [CountedPath: LineCounts] {
        guard section.status == 0 || section.isTruncated else { return [:] }
        var records = section.body.split(separator: 0, omittingEmptySubsequences: false)
        // The last element is empty after a terminating NUL, or an incomplete
        // record at the cap. A rename is kept only with both complete paths.
        if !records.isEmpty { records.removeLast() }
        var counts: [CountedPath: LineCounts] = [:]
        var index = records.startIndex
        while index < records.endIndex {
            let fields = records[index].split(
                separator: 0x09, maxSplits: 2, omittingEmptySubsequences: false)
            index += 1
            guard fields.count == 3 else { continue }
            var path = CountedPath(path: Data(fields[2]))
            if fields[2].isEmpty {
                guard index + 1 < records.endIndex else { break }
                path = CountedPath(path: Data(records[index + 1]), originalPath: Data(records[index]))
                index += 2
            }
            guard !path.path.isEmpty, path.originalPath?.isEmpty != true else { continue }
            let value: LineCounts
            if fields[0].elementsEqual([0x2D]), fields[1].elementsEqual([0x2D]) {
                value = .binary
            } else if let added = decimalCount(fields[0]), let removed = decimalCount(fields[1]) {
                value = .lines(added: added, removed: removed)
            } else {
                continue
            }
            counts[path] = value
        }
        return counts
    }

    private static func decimalCount(_ bytes: Data.SubSequence) -> Int? {
        guard !bytes.isEmpty, bytes.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return Int(String(decoding: bytes, as: UTF8.self))
    }
}
