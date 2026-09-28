import Foundation

extension GitProbe.Cap {
    static let patch = 262_144
    static let patchExtended = 1_048_576
}

extension GitProbe.SectionName {
    static let patch = "patch"
}

extension GitProbe {
    /// The raw status paths are quoted without a UTF-8 round trip. A tracked
    /// rename supplies both paths; untracked files compare with the null
    /// device. No path reaches the SSH command line.
    static func patchScript(_ request: FilePatchRequest, nonce: String) -> Data {
        var body = Data("top=".utf8)
        body.append(singleQuoted(request.topLevel))
        body.append(Data("\n".utf8))
        if !request.isUntracked { body.append(Data("b=$(base \"$top\")\n".utf8)) }
        let base = request.isUntracked ? "--no-index" : "\"$b\""
        let options = request.isUntracked ? " -- /dev/null " : " --find-renames --submodule=short -- "
        body.append(Data(
            "sec \(request.limit.byteCount) \(SectionName.patch) g -C \"$top\" diff \(base) --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ -U3\(options)".utf8))
        body.append(singleQuoted(request.path))
        if !request.isUntracked, let originalPath = request.originalPath {
            body.append(Data(" ".utf8))
            body.append(singleQuoted(originalPath))
        }
        body.append(Data("\n".utf8))
        return script(nonce: nonce, body: body)
    }

    /// Both the framed command status and the final marker are required.
    /// `--no-index` uses 1 for differences and failures alike, so only a
    /// patch header makes that status a successful untracked-file read.
    static func parsePatch(
        stdout: Data, stderr: Data, nonce: String, request: FilePatchRequest
    ) throws -> FilePatch {
        let frames = Frames(stdout: stdout, stderr: stderr, nonce: nonce)
        guard frames.reachedEnd else { throw ChangesReadError.incomplete }
        let section = try frames.requiredSection(SectionName.patch, cap: request.limit.byteCount)
        let hasPatch = section.body.starts(with: Data("diff --git ".utf8))
        guard section.status == 0 || section.isTruncated
            || (request.isUntracked && section.status == 1 && hasPatch)
        else { throw failure(section) }
        var body = section.body
        // Only whole physical lines are displayable. A cap may split a
        // multibyte scalar, a path escape, or the hunk's next source line.
        if section.isTruncated, body.last != 0x0A {
            if let end = body.lastIndex(of: 0x0A) {
                body = Data(body[...end])
            } else {
                body.removeAll()
            }
        }
        return FilePatch(
            files: parsePatchFiles(body, isTruncated: section.isTruncated),
            isTruncated: section.isTruncated)
    }
}
