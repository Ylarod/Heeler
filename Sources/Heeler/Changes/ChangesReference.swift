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
}
