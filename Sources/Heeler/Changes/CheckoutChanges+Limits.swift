import Foundation

extension CheckoutChanges {
    static let displayLimit = 2_000

    /// The model retains every complete record for totals and later reads.
    /// Only the displayed list is limited; its raw path identities are intact.
    var listedFiles: ArraySlice<ChangedFile> { files.prefix(Self.displayLimit) }

    var listLimitNotice: String? {
        Self.limitNotice(
            shown: listedFiles.count, total: files.count,
            isLowerBound: isStatusTruncated, noun: "changed files")
    }

    /// Shared with untracked-directory listings. A capped status is a lower
    /// bound even when fewer than the display limit's records fit in it.
    static func limitNotice(shown: Int, total: Int, isLowerBound: Bool, noun: String) -> String? {
        guard shown < total || isLowerBound else { return nil }
        let totalText = isLowerBound ? "more than \(total.formatted())" : total.formatted()
        return "Showing \(shown.formatted()) of \(totalText) \(noun)."
    }
}
