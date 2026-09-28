import Foundation

extension GitProbe {
    /// The plain probe precedes all commands carrying global options, so an
    /// old git's later "unknown option" cannot hide the actionable version.
    /// Vendor suffixes are display text; only the leading major/minor matter.
    static func requireUsableGit(_ section: Section) throws {
        if isGitMissing(section) { throw ChangesReadError.gitMissing }
        guard section.status == 0 else { throw failure(section) }
        guard !section.isTruncated else { throw ChangesReadError.incomplete }
        let line = String(decoding: section.body, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("git version ") else { return }
        let version = String(line.dropFirst("git version ".count))
        guard let range = version.range(of: #"^[0-9]+\.[0-9]+"#, options: .regularExpression)
        else { return }
        let components = version[range].split(separator: ".")
        guard let major = Int(components[0]), let minor = Int(components[1]) else { return }
        if major < 2 || (major == 2 && minor < 17) {
            throw ChangesReadError.gitTooOld(version)
        }
    }

    /// Apple's git executable can be an installer shim even when PATH lookup
    /// succeeds. Its framed message is the evidence, not the channel status.
    static func isGitMissing(_ section: Section) -> Bool {
        if section.status == 127 { return true }
        let line = section.firstMessageLine?.lowercased() ?? ""
        return (line.hasPrefix("xcode-select:") && line.contains("no developer tools were found"))
            || (line.hasPrefix("xcrun:") && line.contains("invalid active developer path"))
    }
}
