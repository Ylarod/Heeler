import Foundation

extension GitProbe {
    /// Git's C-locale diagnostics distinguish an absent directory from an
    /// inaccessible one. No ownership failure ever changes Host config.
    static func classifyCommandFailure(_ section: Section) -> ChangesReadError {
        if isGitMissing(section) { return .gitMissing }
        let messages = String(decoding: section.messages, as: UTF8.self)
        if messages.contains("detected dubious ownership")
            || (messages.contains("unsafe repository") && messages.contains("owned by someone else"))
        {
            return .notOwnedByAccount
        }
        if messages.contains("cannot change to") && messages.contains("No such file or directory") {
            return .directoryMissing
        }
        if messages.contains("not a git repository") || messages.contains("must be run in a work tree") {
            return .notAGitWorkingTree
        }
        return .gitFailed(section.firstMessageLine ?? "git exited with status \(section.status).")
    }

    /// Counts and latest-commit reads must not silently turn failures into
    /// missing metadata. A capped body can finish with zero or SIGPIPE;
    /// either way the list remains readable but must carry a partial notice.
    static func validateChangesMetadata(_ frames: Frames) throws -> Bool {
        let sections = [
            try frames.requiredSection(SectionName.numstat, cap: Cap.numstat),
            try frames.requiredSection(SectionName.head, cap: Cap.head),
        ]
        for section in sections where section.status != 0 && !section.isTruncated {
            throw failure(section)
        }
        return sections.contains { $0.isTruncated }
    }
}
