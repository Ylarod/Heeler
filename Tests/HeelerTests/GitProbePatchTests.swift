import Foundation
import Testing

@testable import Heeler

@Suite("GitProbe patch script")
struct GitProbePatchScriptTests {
    static func request(
        path: String = "file.txt", originalPath: String? = nil,
        untracked: Bool = false, limit: FilePatchRequest.Limit = .initial
    ) -> FilePatchRequest {
        FilePatchRequest(
            topLevel: Data("/home/dev/app".utf8), path: Data(path.utf8),
            originalPath: originalPath.map { Data($0.utf8) },
            isUntracked: untracked, limit: limit)
    }

    @Test func trackedReadsUseHEADAndBothRenamePaths() {
        let script = String(decoding: GitProbe.patchScript(
            Self.request(path: "new.txt", originalPath: "old.txt"), nonce: "F00D"), as: UTF8.self)
        #expect(script.contains("top='/home/dev/app'\nb=$(base \"$top\")\n"))
        #expect(script.contains(
            #"sec 262144 patch g -C "$top" diff "$b" --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ -U3 --find-renames --submodule=short -- 'new.txt' 'old.txt'"#))
        #expect(script.hasPrefix("{\n"))
        #expect(script.hasSuffix("\n} </dev/null 3>&1\n"))
        #expect(script.contains("printf '\\n%s done\\n' \"$N\""))
        #expect(script.contains(GitProbe.preamble(nonce: "F00D")))
    }

    @Test func untrackedAndExtendedReadsUseTheEmptyFileAndTheRequestedCap() {
        let script = String(decoding: GitProbe.patchScript(
            Self.request(untracked: true, limit: .extended), nonce: "F00D"), as: UTF8.self)
        #expect(script.contains(
            #"sec 1048576 patch g -C "$top" diff --no-index --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ -U3 -- /dev/null 'file.txt'"#))
        #expect(!script.contains("b=$(base"))
        let direct = script.split(separator: "\n").filter {
            $0.range(of: #"(^|[ ;({])git "#, options: .regularExpression) != nil
        }
        #expect(direct.count == 1)
        #expect(direct.first?.hasPrefix("g() { git ") == true)
    }

    @Test(arguments: GitProbeScriptTests.hostileNames)
    func allThreePathsRemainSingleQuoted(name: String) throws {
        let request = FilePatchRequest(
            topLevel: Data(("/home/dev/" + name).utf8), path: Data(name.utf8),
            originalPath: Data(("old/" + name).utf8), isUntracked: false)
        let script = String(decoding: GitProbe.patchScript(request, nonce: "F00D"), as: UTF8.self)
        let top = try #require(script.range(of: "\ntop="))
        let topWord = try #require(ShellWord.parse(script[top.upperBound...]))
        #expect(topWord.value == "/home/dev/" + name)
        #expect(topWord.isQuotedOnly)
        let paths = try #require(script.range(of: "--submodule=short -- "))
        let pathWord = try #require(ShellWord.parse(script[paths.upperBound...]))
        #expect(pathWord.value == name)
        #expect(pathWord.isQuotedOnly)
        let oldStart = script.index(after: pathWord.end)
        let oldWord = try #require(ShellWord.parse(script[oldStart...]))
        #expect(oldWord.value == "old/" + name)
        #expect(oldWord.isQuotedOnly)
        #expect(script[oldWord.end...].hasPrefix("\nprintf"))
    }

    @Test func rawPathBytesAreNotDecodedOnTheWayToTheHost() {
        let path = Data([0x66, 0x80, 0xFF, 0x27])
        let request = FilePatchRequest(
            topLevel: Data("/tmp".utf8), path: path, originalPath: nil, isUntracked: true)
        #expect(GitProbe.patchScript(request, nonce: "F00D")
            .range(of: GitProbe.singleQuoted(path)) != nil)
    }
}

@Suite("Diff document model")
struct DiffDocumentTests {
    @Test func lineKindsProvideNumbersGlyphsAndSpeech() {
        let added = DiffLine(id: 0, kind: .added, oldNumber: nil, newNumber: 3, text: "new")
        let removed = DiffLine(id: 1, kind: .removed, oldNumber: 4, newNumber: nil, text: "old")
        let context = DiffLine(id: 2, kind: .context, oldNumber: 5, newNumber: 6, text: "same")
        #expect(added.glyph == "+")
        #expect(removed.glyph == "−")
        #expect(context.glyph == " ")
        #expect(added.accessibilityLabel == "Added, line 3: new")
        #expect(removed.accessibilityLabel == "Removed, line 4: old")
        #expect(context.accessibilityLabel == "Unchanged, line 6: same")
        #expect(!added.missingNewline)
    }

    @Test func parsedHunksKeepSectionNamesNumbersAndStableOrdinals() throws {
        let patch = try GitProbePatchParsingTests.parse(GitProbeRecordings.patchSection)
        let hunk = try #require(patch.files.first?.hunks.first)
        #expect(hunk.section == "func example() {")
        #expect(hunk.title == "@@ -11,5 +11,5 @@ func example() {")
        #expect(hunk.lines.map(\.kind) == [.context, .context, .context, .removed, .added, .context])
        #expect(hunk.lines.map(\.oldNumber) == [11, 12, 13, 14, nil, 15])
        #expect(hunk.lines.map(\.newNumber) == [11, 12, 13, nil, 14, 15])
        #expect(hunk.lines.map(\.id) == Array(0..<6))
        let twoFiles = try GitProbePatchParsingTests.parse(GitProbeRecordings.patchRewriteRename)
        #expect(twoFiles.files.map(\.id) == [0, 1])
        #expect(twoFiles.files.flatMap(\.hunks).map(\.id) == [0, 1])
        let lines = twoFiles.files.flatMap(\.hunks).flatMap(\.lines)
        #expect(lines.map(\.id) == Array(0..<lines.count))
    }
}

@Suite("GitProbe patch parsing")
struct GitProbePatchParsingTests {
    typealias Recording = (stdout: Data, stderr: Data)

    static func parse(
        _ recording: Recording, path: String = "file.txt", untracked: Bool = false
    ) throws -> FilePatch {
        try GitProbe.parsePatch(
            stdout: recording.stdout, stderr: recording.stderr, nonce: GitProbeRecordings.nonce,
            request: GitProbePatchScriptTests.request(path: path, untracked: untracked))
    }

    @Test func aModifiedFileCarriesOldAndNewLines() throws {
        let patch = try Self.parse(GitProbeRecordings.patchModified)
        let file = try #require(patch.files.first)
        #expect(file.oldPath == "modified.txt")
        #expect(file.newPath == "modified.txt")
        #expect(!patch.isTruncated)
        #expect(!file.isBinary)
        #expect(file.hunks.first?.lines.map(\.text) == ["first", "old", "new", "last"])
        #expect(file.hunks.first?.lines.map(\.oldNumber) == [1, 2, nil, 3])
        #expect(file.hunks.first?.lines.map(\.newNumber) == [1, nil, 2, 3])
    }

    @Test func contentThatLooksLikeAFileHeaderStaysInsideItsHunk() throws {
        let file = try #require(Self.parse(GitProbeRecordings.patchHeaderText).files.first)
        #expect(file.oldPath == "header-text.txt")
        #expect(file.newPath == "header-text.txt")
        #expect(file.hunks.flatMap(\.lines).map(\.text) == ["-- old header", "++ new header"])
        #expect(file.hunks.flatMap(\.lines).map(\.kind) == [.removed, .added])
    }

    @Test func separatedHunksRestartTheirLineNumbersAndContinueTheirIdentities() throws {
        let file = try #require(Self.parse(GitProbeRecordings.patchMultipleHunks).files.first)
        #expect(file.hunks.count == 2)
        #expect(file.hunks.map(\.id) == [0, 1])
        #expect(file.hunks.map(\.oldStart) == [1, 22])
        #expect(file.hunks.map(\.newStart) == [1, 22])
        let additions = file.hunks.flatMap(\.lines).filter { $0.kind == .added }
        #expect(additions.map(\.newNumber) == [2, 25])
        let lines = file.hunks.flatMap(\.lines)
        #expect(lines.map(\.id) == Array(0..<lines.count))
    }

    @Test func deletedAddedIntentAndUntrackedFilesHaveOnlyTheMatchingSide() throws {
        let deleted = try #require(Self.parse(GitProbeRecordings.patchDeleted).files.first)
        #expect(deleted.oldPath == "deleted.txt")
        #expect(deleted.newPath == nil)
        #expect(deleted.hunks.flatMap(\.lines).map(\.kind) == [.removed, .removed])
        for recording in [GitProbeRecordings.patchAdded, GitProbeRecordings.patchIntentToAdd] {
            let added = try #require(Self.parse(recording).files.first)
            #expect(added.oldPath == nil)
            #expect(added.hunks.flatMap(\.lines).allSatisfy { $0.kind == .added && $0.oldNumber == nil })
        }
        let untracked = try #require(Self.parse(
            GitProbeRecordings.patchUntracked, untracked: true).files.first)
        #expect(untracked.oldPath == nil)
        #expect(untracked.newPath == "untracked space.txt")
        #expect(untracked.hunks.flatMap(\.lines).map(\.newNumber) == [1, 2])
        #expect(untracked.hunks.flatMap(\.lines).last?.missingNewline == true)
    }

    @Test func pureRenamesAndModeChangesExplainTheirMetadata() throws {
        let rename = try #require(Self.parse(GitProbeRecordings.patchPureRename).files.first)
        #expect(rename.oldPath == "pure-old.txt")
        #expect(rename.newPath == "pure-new.txt")
        #expect(rename.hunks.isEmpty)
        #expect(rename.summary == "Renamed from pure-old.txt to pure-new.txt.")
        let mode = try #require(Self.parse(GitProbeRecordings.patchMode).files.first)
        #expect(mode.hunks.isEmpty)
        #expect(mode.summary == "File mode changed from 100644 to 100755.")
        let edited = try #require(Self.parse(GitProbeRecordings.patchEditedRename).files.first)
        #expect(edited.oldPath == "edited-old.txt")
        #expect(edited.newPath == "edited-new.txt")
        #expect(!edited.hunks.isEmpty)
        let rewrite = try Self.parse(GitProbeRecordings.patchRewriteRename)
        #expect(rewrite.files.count == 2)
        #expect(rewrite.files.contains { $0.oldPath == "move-old.txt" && $0.newPath == nil })
        #expect(rewrite.files.contains { $0.oldPath == nil && $0.newPath == "move-new.txt" })
    }

    @Test func missingNewlinesAndCRLFRemainSeparateDisplayLines() throws {
        let noNewline = try #require(Self.parse(GitProbeRecordings.patchMissingNewline).files.first)
        let lines = noNewline.hunks.flatMap(\.lines)
        #expect(lines.map(\.text) == ["old", "new"])
        #expect(lines.allSatisfy { $0.missingNewline })
        #expect(lines.last?.accessibilityLabel == "Added, line 1: new. No newline at end of file.")
        let crlf = try #require(Self.parse(GitProbeRecordings.patchCRLF).files.first)
        #expect(crlf.hunks.flatMap(\.lines).map(\.text) == ["first", "old", "new", "last"])
        #expect(crlf.hunks.flatMap(\.lines).map(\.kind) == [.context, .removed, .added, .context])
    }

    @Test func conflictMarkersAreNormalAddedLinesAgainstHEAD() throws {
        let patch = try Self.parse(GitProbeRecordings.patchConflict)
        let lines = patch.files.flatMap(\.hunks).flatMap(\.lines)
        #expect(lines.contains { $0.kind == .added && $0.text == "<<<<<<< HEAD" })
        #expect(lines.contains { $0.kind == .added && $0.text == "=======" })
        #expect(lines.contains { $0.kind == .added && $0.text == ">>>>>>> other" })
        #expect(lines.contains { $0.kind == .context && $0.text == "ours" })
    }

    @Test func binaryFilesHaveLabelsAndNoHunks() throws {
        for (recording, untracked) in [(GitProbeRecordings.patchBinary, false), (GitProbeRecordings.patchUntrackedBinary, true)] {
            let file = try #require(Self.parse(recording, untracked: untracked).files.first)
            #expect(file.isBinary)
            #expect(file.hunks.isEmpty)
            #expect(file.summary == "Binary file.")
        }
    }

    @Test func nonUTF8ContentAndCQuotedPathsDecodeLossily() throws {
        let latin = try Self.parse(GitProbeRecordings.patchLatin1)
        #expect(latin.files.flatMap(\.hunks).flatMap(\.lines).map(\.text) == ["caf�", "caf�"])
        let raw = try Self.parse(GitProbeRecordings.patchRawPath)
        #expect(raw.files.first?.oldPath == "raw-�.txt")
        #expect(raw.files.first?.newPath == nil)
        for recording in GitProbeRecordings.patchNames {
            let patch = try Self.parse((recording.stdout, recording.stderr))
            let name = String(decoding: recording.path, as: UTF8.self)
            #expect(patch.files.first?.oldPath == name)
            #expect(patch.files.first?.newPath == name)
            #expect(patch.files.first?.hunks.first?.lines.map(\.text) == ["old", "new"])
        }
    }

    @Test func submoduleCommitsUseTheOrdinaryTwoSidedDocument() throws {
        let hunk = try #require(Self.parse(GitProbeRecordings.patchSubmodule).files.first?.hunks.first)
        #expect(hunk.oldStart == 1 && hunk.oldCount == 1)
        #expect(hunk.newStart == 1 && hunk.newCount == 1)
        #expect(hunk.lines.map(\.kind) == [.removed, .added])
        #expect(hunk.lines.allSatisfy { $0.text.hasPrefix("Subproject commit ") })
    }

    @Test func emptyUntrackedAndNoLongerChangedFilesAreDistinct() throws {
        let empty = try #require(Self.parse(GitProbeRecordings.patchEmptyUntracked, untracked: true).files.first)
        #expect(empty.newPath == "empty.txt")
        #expect(empty.oldPath == nil)
        #expect(empty.hunks.isEmpty)
        #expect(empty.summary == "New empty file.")
        #expect(try Self.parse(GitProbeRecordings.patchUnchanged).files.isEmpty)
        #expect(throws: ChangesReadError.gitFailed("error: Could not access 'missing.txt'")) {
            try Self.parse(GitProbeRecordings.patchVanished, untracked: true)
        }
    }

    @Test func missingStatusesFinalMarkersAndOtherNoncesAreIncomplete() throws {
        let original = String(decoding: GitProbeRecordings.patchModified.stdout, as: UTF8.self)
        for text in [
            original.replacingOccurrences(of: "__HEELER_GIT_F00D__ patch rc=0", with: "lost status"),
            original.replacingOccurrences(of: "__HEELER_GIT_F00D__ done", with: "lost final marker"),
            original.replacingOccurrences(of: "F00D", with: "CAFE"),
        ] {
            #expect(throws: ChangesReadError.incomplete) {
                try Self.parse((Data(text.utf8), GitProbeRecordings.patchModified.stderr))
            }
        }
        let noisy = (
            stdout: Data("login noise\n__HEELER_GIT_CAFE__ done\n".utf8) + GitProbeRecordings.patchModified.stdout,
            stderr: Data("login noise\n".utf8) + GitProbeRecordings.patchModified.stderr)
        #expect(try Self.parse(noisy) == Self.parse(GitProbeRecordings.patchModified))
    }

    @Test func aLengthOverrunDropsThePartialLineEvenWithZeroExitStatus() throws {
        let header = "diff --git a/large.txt b/large.txt\n--- a/large.txt\n+++ b/large.txt\n@@ -0,0 +1,999999 @@\n"
        let complete = "+complete line\n"
        var body = Data(header.utf8)
        while body.count + complete.utf8.count < GitProbe.Cap.patch { body.append(Data(complete.utf8)) }
        body.append(Data(("+" + String(repeating: "x", count: 100)).utf8))
        let stdout = Data("\n__HEELER_GIT_F00D__ patch begin\n".utf8)
            + body + Data("\n__HEELER_GIT_F00D__ patch rc=0\n\n__HEELER_GIT_F00D__ done\n".utf8)
        let patch = try Self.parse((stdout, Data()))
        #expect(patch.isTruncated)
        #expect(patch.files.flatMap(\.hunks).flatMap(\.lines).last?.text == "complete line")
        let full = try GitProbe.parsePatch(
            stdout: stdout, stderr: Data(), nonce: "F00D",
            request: GitProbePatchScriptTests.request(limit: .extended))
        #expect(!full.isTruncated)
        let shortLines = patch.files.flatMap(\.hunks).flatMap(\.lines)
        #expect(full.files.flatMap(\.hunks).flatMap(\.lines).prefix(shortLines.count).map(\.id) == shortLines.map(\.id))
    }

    @Test func aCutBeforeTheFirstHunkDoesNotClaimTheNewFileIsEmpty() throws {
        // Synthetic framing boundary: the following metadata line is cut,
        // so the absence of a hunk is not evidence of an empty file.
        let body = "diff --git a/new.txt b/new.txt\nnew file mode 100644\nindex "
            + String(repeating: "x", count: GitProbe.Cap.patch)
        let stdout = Data(("\n__HEELER_GIT_F00D__ patch begin\n" + body
            + "\n__HEELER_GIT_F00D__ patch rc=141\n\n__HEELER_GIT_F00D__ done\n").utf8)
        let patch = try Self.parse((stdout, Data()), untracked: true)
        let file = try #require(patch.files.first)
        #expect(patch.isTruncated)
        #expect(file.hunks.isEmpty)
        #expect(file.summary == nil)
    }
}
