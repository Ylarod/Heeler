import Foundation

/// References use Host path bytes, never the file row's control-picture label.
enum ChangesReference {
    static func path(file: Data, topLevel: Data, directoryPrefix: Data?) -> String? {
        let bytes: Data
        if let directoryPrefix, file.starts(with: directoryPrefix) {
            bytes = Data(file.dropFirst(directoryPrefix.count))
        } else {
            bytes = topLevel + (topLevel.last == UInt8(ascii: "/") ? Data() : Data([0x2F])) + file
        }
        return String(data: bytes, encoding: .utf8)
    }

    /// A reference must never carry a terminal control or a submit character.
    /// Copying is separate and preserves the path's original text.
    static func insertion(_ reference: String) -> String? {
        guard !reference.isEmpty,
            reference.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
                    && !CharacterSet.newlines.contains($0)
            })
        else { return nil }
        return reference + " "
    }

    static func lineNumber(of line: DiffLine, in hunk: DiffHunk) -> Int? {
        guard let index = hunk.lines.firstIndex(where: { $0.id == line.id }) else { return nil }
        if let number = line.newNumber { return max(1, number) }
        let preceding = hunk.lines[..<index].filter { $0.kind != .removed }.count
        // At EOF (or in a deleted file), use the last available new-file line.
        let lastLine = max(1, hunk.newStart + hunk.newCount - 1)
        return min(lastLine, max(1, hunk.newStart + preceding))
    }

    static func hunkText(_ hunk: DiffHunk) -> String {
        func range(_ start: Int, _ count: Int) -> String {
            count == 1 ? "\(start)" : "\(start),\(count)"
        }
        var text = "@@ -\(range(hunk.oldStart, hunk.oldCount)) +\(range(hunk.newStart, hunk.newCount)) @@"
        if !hunk.section.isEmpty { text += " " + hunk.section }
        text += "\n"
        for line in hunk.lines {
            let prefix: String
            switch line.kind {
            case .context: prefix = " "
            case .removed: prefix = "-"
            case .added: prefix = "+"
            }
            text += prefix + line.text + "\n"
            if line.missingNewline { text += "\\ No newline at end of file\n" }
        }
        return text
    }
}
