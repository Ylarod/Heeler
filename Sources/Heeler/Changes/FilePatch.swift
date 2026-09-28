import Foundation

/// One lazy read, keyed by the Checkout and the status record's raw paths.
struct FilePatchRequest: Sendable, Equatable {
    enum Limit: Sendable, Equatable {
        case initial
        case extended

        var byteCount: Int {
            switch self {
            case .initial: GitProbe.Cap.patch
            case .extended: GitProbe.Cap.patchExtended
            }
        }
    }

    let topLevel: Data
    let path: Data
    let originalPath: Data?
    let isUntracked: Bool
    let limit: Limit

    init(
        topLevel: Data, path: Data, originalPath: Data? = nil,
        isUntracked: Bool, limit: Limit = .initial
    ) {
        self.topLevel = topLevel
        self.path = path
        self.originalPath = originalPath
        self.isUntracked = isUntracked
        self.limit = limit
    }

    /// Status collapses untracked directories. They must be expanded before
    /// an individual file can be read against the empty file.
    init?(file: ChangedFile, checkout: CheckoutLocation, limit: Limit = .initial) {
        guard !(file.kind == .untracked && file.path.last == UInt8(ascii: "/")) else {
            return nil
        }
        self.init(
            topLevel: checkout.topLevel, path: file.path, originalPath: file.originalPath,
            isUntracked: file.kind == .untracked, limit: limit)
    }
}

/// A single request can contain two file sections when an edited rename no
/// longer meets git's similarity threshold. IDs are stable prefix ordinals
/// at each level, so extending the read preserves existing row identities.
struct FilePatch: Sendable, Equatable {
    let files: [DiffFile]
    let isTruncated: Bool
}

struct DiffFile: Sendable, Equatable, Identifiable {
    let id: Int
    let oldPath: String?
    let newPath: String?
    let summary: String?
    let isBinary: Bool
    let hunks: [DiffHunk]
}

struct DiffHunk: Sendable, Equatable, Identifiable {
    let id: Int
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let section: String
    var lines: [DiffLine]

    var title: String {
        let range = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
        return section.isEmpty ? range : range + " " + section
    }
}

struct DiffLine: Sendable, Equatable, Identifiable {
    enum Kind: Sendable, Equatable {
        case added
        case removed
        case context
    }

    let id: Int
    let kind: Kind
    let oldNumber: Int?
    let newNumber: Int?
    let text: String
    var missingNewline = false

    var glyph: String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .context: " "
        }
    }

    var accessibilityLabel: String {
        let action: String
        let number: Int?
        switch kind {
        case .added: action = "Added"; number = newNumber
        case .removed: action = "Removed"; number = oldNumber
        case .context: action = "Unchanged"; number = newNumber
        }
        let location = number.map { ", line \($0)" } ?? ""
        let suffix = missingNewline ? ". No newline at end of file." : ""
        return "\(action)\(location): \(text)\(suffix)"
    }
}
