import Foundation

extension GitProbe {
    /// Even a failed command is not a complete read if a later command began
    /// without reporting its status. Zero-byte bodies avoid copying output
    /// here; the regular parse applies each command's own cap afterwards.
    static func validateChangesFraming(_ frames: Frames) throws {
        for name in [
            SectionName.version, SectionName.home, SectionName.discover,
            SectionName.status, SectionName.numstat, SectionName.head,
        ] {
            _ = try frames.section(name, cap: 0)
        }
    }

    /// Git's C-locale diagnostics distinguish an absent directory from an
    /// inaccessible one. No ownership failure ever changes Host config.
    static func classifyCommandFailure(_ section: Section) -> ChangesReadError {
        if isGitMissing(section) { return .gitMissing }
        let line = section.firstMessageLine ?? "git exited with status \(section.status)."
        if line.hasPrefix("fatal: detected dubious ownership in repository at ")
            || (line.hasPrefix("fatal: unsafe repository (") && line.hasSuffix("is owned by someone else)"))
        {
            return .notOwnedByAccount
        }
        if line.hasPrefix("fatal: cannot change to '") && line.hasSuffix("': No such file or directory") {
            return .directoryMissing
        }
        if line.hasPrefix("fatal: not a git repository") || line == "fatal: this operation must be run in a work tree" {
            return .notAGitWorkingTree
        }
        return .gitFailed(line)
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
