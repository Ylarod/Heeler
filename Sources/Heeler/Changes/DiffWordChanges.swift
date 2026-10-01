import Foundation

/// The words that changed inside paired removed and added lines. Within one
/// block, removed and added lines pair in order, as Side by Side shows them,
/// up to `maximumPairs`. Tokens are identifier runs, whitespace runs, and
/// single other characters, diffed with `CollectionDifference`. A pair
/// highlights only when at least half of the longer line's tokens are
/// unchanged; otherwise the line's wash alone marks it.
enum DiffWordChanges {
    static let maximumPairs = 20
    /// Longer lines keep the wash alone, bounding the difference's cost.
    static let maximumTokens = 400

    /// Changed words per line id, as Character offsets into the line's text.
    /// Lines without a highlighted pair are absent.
    static func ranges(in hunk: DiffHunk) -> [Int: [Range<Int>]] {
        var result: [Int: [Range<Int>]] = [:]
        var removed: [DiffLine] = []
        var added: [DiffLine] = []

        func flush() {
            for (old, new) in zip(removed, added).prefix(maximumPairs) {
                guard let changes = ranges(old: old.text, new: new.text) else { continue }
                if !changes.old.isEmpty { result[old.id] = changes.old }
                if !changes.new.isEmpty { result[new.id] = changes.new }
            }
            removed.removeAll()
            added.removeAll()
        }

        for line in hunk.lines {
            switch line.kind {
            case .context:
                flush()
            case .removed:
                // Git emits a block's removals before its additions; a
                // removal after an addition starts a new block.
                if !added.isEmpty { flush() }
                removed.append(line)
            case .added:
                added.append(line)
            }
        }
        flush()
        return result
    }

    /// Changed words on each side, or nil when the pair should not highlight.
    static func ranges(old: String, new: String) -> (old: [Range<Int>], new: [Range<Int>])? {
        let oldTokens = tokens(old)
        let newTokens = tokens(new)
        let longer = max(oldTokens.count, newTokens.count)
        guard longer > 0, longer <= maximumTokens else { return nil }
        let difference = newTokens.map(\.text).difference(from: oldTokens.map(\.text))
        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removedOffsets.insert(offset)
            case .insert(let offset, _, _): insertedOffsets.insert(offset)
            }
        }
        let unchanged = oldTokens.count - removedOffsets.count
        guard unchanged * 2 >= longer else { return nil }
        return (
            merged(oldTokens, changed: removedOffsets),
            merged(newTokens, changed: insertedOffsets)
        )
    }

    struct Token: Equatable {
        let text: Substring
        /// Character offsets into the line.
        let range: Range<Int>
        let isWhitespace: Bool
    }

    static func tokens(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        var offset = 0
        while index < text.endIndex {
            let character = text[index]
            let start = index
            let startOffset = offset
            let kind = Kind(character)
            index = text.index(after: index)
            offset += 1
            if kind != .other {
                while index < text.endIndex, Kind(text[index]) == kind {
                    index = text.index(after: index)
                    offset += 1
                }
            }
            tokens.append(Token(
                text: text[start..<index], range: startOffset..<offset,
                isWhitespace: kind == .whitespace))
        }
        return tokens
    }

    private enum Kind {
        case identifier
        case whitespace
        case other

        init(_ character: Character) {
            if character.isWhitespace {
                self = .whitespace
            } else if character.isLetter || character.isNumber || character == "_" {
                self = .identifier
            } else {
                self = .other
            }
        }
    }

    /// Changed words, with adjacent ones joined. Whitespace alone never
    /// highlights: an indentation change is the wash's to show.
    private static func merged(_ tokens: [Token], changed: Set<Int>) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for (offset, token) in tokens.enumerated()
        where changed.contains(offset) && !token.isWhitespace {
            if let last = ranges.last, last.upperBound == token.range.lowerBound {
                ranges[ranges.count - 1] = last.lowerBound..<token.range.upperBound
            } else {
                ranges.append(token.range)
            }
        }
        return ranges
    }
}
