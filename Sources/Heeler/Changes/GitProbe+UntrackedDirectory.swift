import Foundation

extension GitProbe.SectionName {
    /// The one framed command in an untracked-directory listing.
    static let untracked = "untracked"
}

/// Lists one untracked directory. Same preamble and framing as a Changes
/// read; the body is a single status, capped like the Changes status.
extension GitProbe {
    /// The pathspec is `directory` exactly as status printed it. Nothing in
    /// the body discovers the repository or asks for branch headers.
    static func untrackedDirectoryScript(
        topLevel: Data, directory: Data, nonce: String
    ) -> Data {
        var body = Data("top=".utf8)
        body.append(singleQuoted(topLevel))
        body.append(
            Data(
                "\nsec \(Cap.status) \(SectionName.untracked) g -C \"$top\" status --porcelain=v2 -z --untracked-files=all -- "
                    .utf8))
        body.append(singleQuoted(directory))
        body.append(Data("\n".utf8))
        return script(nonce: nonce, body: body)
    }

    /// Parses one listing. Omitting `displayLimit` uses the list's ceiling;
    /// tests pass a small one. Throws `ChangesReadError`: `.incomplete` when
    /// the framed status or the final marker is missing, and `.gitFailed`
    /// with git's first error line otherwise. A status cut short is kept.
    static func parseUntrackedDirectory(
        stdout: Data,
        stderr: Data,
        nonce: String,
        directory: Data,
        displayLimit: Int = UntrackedDirectoryLimit.count,
        cap: Int = Cap.status
    ) throws -> UntrackedDirectoryListing {
        let frames = Frames(stdout: stdout, stderr: stderr, nonce: nonce)
        guard frames.reachedEnd else { throw ChangesReadError.incomplete }
        let section = try frames.requiredSection(SectionName.untracked, cap: cap)
        // A cut status can end on SIGPIPE; the kept records are still valid.
        guard section.status == 0 || section.isTruncated else { throw failure(section) }

        var records = section.body.split(separator: 0, omittingEmptySubsequences: false)
        // Complete output ends in NUL, leaving an empty final element; a cut
        // one ends inside its last record.
        if !records.isEmpty { records.removeLast() }
        var isSeparateRepository = false
        var paths: [Data] = []
        for record in records {
            guard let path = untrackedPath(Data(record)) else { continue }
            // Git prints the directory itself when it is a nested repository.
            if path == directory {
                isSeparateRepository = true
                continue
            }
            paths.append(path)
        }
        paths.sort { $0.lexicographicallyPrecedes($1) }
        let shown = displayLimit > 0 ? Array(paths.prefix(displayLimit)) : []
        return UntrackedDirectoryListing(
            directory: directory,
            entries: shown.map {
                ChangedFile(path: $0, originalPath: nil, kind: .untracked, staging: nil)
            },
            total: paths.count,
            isTruncated: section.isTruncated,
            isSeparateRepository: isSeparateRepository,
            limitNotice: UntrackedDirectoryLimit.notice(
                shown: shown.count, total: paths.count, isLowerBound: section.isTruncated))
    }

    /// `? <path>`. Tracked rows, headers and ignored records are not entries.
    private static func untrackedPath(_ record: Data) -> Data? {
        guard
            record.count >= 3,
            record[record.startIndex] == UInt8(ascii: "?"),
            record[record.startIndex + 1] == UInt8(ascii: " ")
        else { return nil }
        let path = record.dropFirst(2)
        guard !path.isEmpty else { return nil }
        return Data(path)
    }
}

/// The Changes list's display ceiling and its sentence, kept privately until
/// #389's shared helper replaces them.
private enum UntrackedDirectoryLimit {
    static let count = 2_000

    /// "Showing 2,000 of 2,345 files." when the total is known, and
    /// "Showing 2,000 of more than 2,345 files." when the status cap cut it.
    static func notice(shown: Int, total: Int, isLowerBound: Bool) -> String? {
        guard isLowerBound || total > shown else { return nil }
        if isLowerBound {
            return "Showing \(shown.formatted()) of more than \(total.formatted()) files."
        }
        return "Showing \(shown.formatted()) of \(total.formatted()) files."
    }
}
