import Foundation
import Testing

@testable import Heeler

/// The Changes script as the Host's shell will parse it. Nothing here runs a
/// shell: the fixture end-to-end test does that. These pin the shape that
/// keeps paths off the command line and git from locking or running programs.
@Suite("GitProbe script")
struct GitProbeScriptTests {
    /// The hostile names from docs/research/mobile-git-changes.md, plus the
    /// ones a directory can also carry.
    static let hostileNames = [
        "--", "-dash.txt", "sp ace.txt", "quo\"te.txt", "sq'uote.txt",
        #"two\\bs.txt"#, #"trail\"#, "bang!.txt", "$HOME.txt", "*.txt",
        "[ab].txt", "ünï.txt", "中文.txt", "line\nbreak.txt", "tab\tname.txt",
        "''", "$(touch pwned)", "`id`", "; rm -rf ~ #", "a'\\''b",
    ]

    private static func text(_ script: Data) -> String {
        String(decoding: script, as: UTF8.self)
    }

    @Test func theScriptTravelsToOneFixedShellInvocation() {
        #expect(GitProbe.shellInvocation == "/bin/sh -s")
        #expect(HeelerSSHTransport.gitScriptCommand == GitProbe.shellInvocation)
    }

    @Test func theScriptIsOneBraceGroupReadingTheNullDevice() {
        let script = Self.text(GitProbe.changesScript(directory: "/home/dev/app", nonce: "F00D"))
        #expect(script.hasPrefix("{\n"))
        #expect(script.hasSuffix("\n} </dev/null 3>&1\n"))
        #expect(script.contains("\nprintf '\\n%s done\\n' \"$N\"\n"))
        #expect(script.contains("N='__HEELER_GIT_F00D__'\n"))
    }

    @Test(arguments: hostileNames)
    func aHostileDirectoryAppearsOnlyInsideSingleQuotes(name: String) throws {
        let directory = "/home/dev/src/\(name)"
        let script = Self.text(GitProbe.changesScript(directory: directory, nonce: "F00D"))
        let assignment = try #require(script.range(of: "\ndir="))
        let word = try #require(
            ShellWord.parse(script[assignment.upperBound...]),
            "dir= must be followed by one shell word")
        #expect(word.value == directory)
        #expect(word.isQuotedOnly, "every character must sit inside single quotes")

        // Nowhere else: not on another line, not after the word.
        var rest = script
        rest.removeSubrange(assignment.upperBound..<word.end)
        #expect(!rest.contains("/home/dev/src/"))
        // The variable is only ever expanded inside double quotes.
        let expansions = script.ranges(of: "$dir")
        #expect(!expansions.isEmpty)
        for range in expansions {
            #expect(script[..<range.lowerBound].hasSuffix("\""))
            #expect(script[range.upperBound...].hasPrefix("\""))
        }
    }

    @Test func singleQuotingKeepsEveryByte() {
        var bytes = Data("a'b\n\t\\".utf8)
        bytes.append(contentsOf: [0x80, 0xFF, 0x27])
        var expected = Data("'a'\\''b\n\t\\".utf8)
        expected.append(contentsOf: [0x80, 0xFF])
        expected.append(Data("'\\'''".utf8))
        #expect(GitProbe.singleQuoted(bytes) == expected)
    }

    @Test func everyGitCommandButTheVersionProbeIsNeutralized() throws {
        let script = Self.text(GitProbe.changesScript(directory: "/home/dev/app", nonce: "F00D"))
        let lines = script.split(separator: "\n").map(String.init)
        let definition = try #require(lines.first { $0.hasPrefix("g() { git ") })
        let words = definition.split(separator: " ").map(String.init)
        func hasOption(_ key: String, _ value: String) -> Bool {
            zip(words, words.dropFirst()).contains { $0 == "-c" && $1 == "\(key)=\(value)" }
        }
        // Empty, never `false`: git 2.35.1 and older run a program named false.
        #expect(hasOption("core.fsmonitor", ""))
        #expect(!definition.contains("core.fsmonitor=false"))
        // `git diff` rewrites the index through auto-refresh otherwise.
        #expect(hasOption("diff.autoRefreshIndex", "false"))
        #expect(hasOption("status.renames", "true"))
        #expect(hasOption("core.hooksPath", "/dev/null"))
        #expect(hasOption("core.quotePath", "false"))
        #expect(hasOption("color.ui", "false"))
        #expect(hasOption("diff.relative", "false"))
        #expect(hasOption("log.showSignature", "false"))
        #expect(words.contains("--no-optional-locks"))
        #expect(words.contains("--literal-pathspecs"))
        #expect(words.contains("--no-pager"))
        #expect(words.suffix(2) == ["\"$@\";", "}"])

        // Only the version probe and the helper itself spell out `git`.
        let direct = lines.filter { $0.range(of: #"(^|[ ;({])git "#, options: .regularExpression) != nil }
        #expect(direct == [definition, "sec 4096 version git --version"])
        #expect(script.contains("unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE "))
        #expect(script.contains("LC_ALL=C "))
        #expect(script.contains("GIT_OPTIONAL_LOCKS=0"))
        #expect(script.contains("GIT_NO_LAZY_FETCH=1"))
        #expect(script.contains(HerdrHostPath.pathExport))
    }

    @Test func theReadListsStatusAndCountsFromTheTopLevel() {
        let script = Self.text(GitProbe.changesScript(directory: "/home/dev/app", nonce: "F00D"))
        #expect(script.contains(
            #"sec 65536 discover g -C "$dir" rev-parse --show-toplevel --show-prefix --absolute-git-dir --git-common-dir"#))
        #expect(script.contains(
            #"sec 2097152 status g -C "$top" status --porcelain=v2 -z --branch --untracked-files=normal"#))
        #expect(script.contains(
            #"sec 1048576 numstat g -C "$top" diff "$b" --numstat -z --no-ext-diff --no-textconv --find-renames --submodule=short --"#))
        #expect(script.contains(#"sec 65536 head latest "$top""#))
    }

    @Test func eachRequestGetsAFreshShellSafeNonce() {
        let first = GitProbe.makeNonce()
        let second = GitProbe.makeNonce()
        #expect(first != second)
        #expect(first.allSatisfy { $0.isHexDigit })
        #expect(first.count == 32)
    }
}

/// Recorded output from real runs (see `GitProbeRecordings`) parsed into the
/// display-ready document.
@Suite("GitProbe Changes parsing")
struct GitProbeChangesParsingTests {
    private typealias Recording = (stdout: Data, stderr: Data)

    private static func parse(
        _ recording: Recording, nonce: String = GitProbeRecordings.nonce
    ) throws -> CheckoutChangesRead {
        try GitProbe.parseChanges(
            stdout: recording.stdout, stderr: recording.stderr, nonce: nonce)
    }

    private static func failure(
        _ recording: Recording, nonce: String = GitProbeRecordings.nonce
    ) -> ChangesReadError? {
        do {
            _ = try parse(recording, nonce: nonce)
            return nil
        } catch let error as ChangesReadError {
            return error
        } catch {
            Issue.record("unexpected error \(error)")
            return nil
        }
    }

    private struct Row: Equatable, CustomStringConvertible {
        let path: String
        let kind: ChangedFile.Kind
        let staging: ChangedFile.Staging?
        var original: String?

        var description: String { "\(path) \(kind) \(String(describing: staging))" }
    }

    private static func rows(_ files: [ChangedFile]) -> [Row] {
        files.map {
            Row(
                path: String(decoding: $0.path, as: UTF8.self), kind: $0.kind,
                staging: $0.staging,
                original: $0.originalPath.map { String(decoding: $0, as: UTF8.self) })
        }
    }

    @Test func hostileNamesRenamesConflictsAndUntrackedFilesParseExactly() throws {
        let read = try Self.parse(GitProbeRecordings.hostile)
        let changes = read.changes

        #expect(changes.checkout.topLevel == Data("/home/dev/src/app".utf8))
        #expect(changes.checkout.displayPath == "~/src/app")
        #expect(!changes.checkout.isLinkedWorktree)
        #expect(read.directoryPrefix.isEmpty)
        #expect(changes.head.branch == .named("main"))
        #expect(changes.head.commit == "a7d75683c107bbe72aad2574b0ba0e6c47629e08")
        #expect(
            changes.head.latestCommit
                == LatestCommit(
                    subject: #"Main edit to "conflict.txt""#,
                    committedAt: Date(timeIntervalSince1970: 1_790_587_800)))

        // Conflicted first, then raw path byte order; untracked directories
        // stay collapsed; the staged rename is one row despite the
        // repository's own `status.renames=false`.
        #expect(
            Self.rows(changes.files) == [
                Row(path: "conflict.txt", kind: .conflicted, staging: nil),
                Row(path: "$HOME.txt", kind: .modified, staging: .unstaged),
                Row(path: "*.txt", kind: .modified, staging: .unstaged),
                Row(path: "--", kind: .modified, staging: .unstaged),
                Row(path: "-dash.txt", kind: .modified, staging: .unstaged),
                Row(path: "[ab].txt", kind: .modified, staging: .unstaged),
                Row(path: "added.txt", kind: .added, staging: .staged),
                Row(path: "bang!.txt", kind: .modified, staging: .unstaged),
                Row(path: "bin.dat", kind: .modified, staging: .unstaged),
                Row(path: "gone.txt", kind: .deleted, staging: .unstaged),
                Row(path: "line\nbreak.txt", kind: .modified, staging: .unstaged),
                Row(path: "newdir/", kind: .untracked, staging: nil),
                Row(
                    path: "pkg/renamed.txt", kind: .renamed, staging: .staged,
                    original: "old/name.txt"),
                Row(path: "quo\"te.txt", kind: .modified, staging: .unstaged),
                Row(path: "sp ace.txt", kind: .modified, staging: .both),
                Row(path: "sq'uote.txt", kind: .modified, staging: .staged),
                Row(path: "tab\tname.txt", kind: .modified, staging: .unstaged),
                Row(path: #"trail\"#, kind: .modified, staging: .unstaged),
                Row(path: #"two\\bs.txt"#, kind: .modified, staging: .unstaged),
                Row(path: "untracked.txt", kind: .untracked, staging: nil),
                Row(path: "ünï.txt", kind: .modified, staging: .unstaged),
                Row(path: "中文.txt", kind: .modified, staging: .unstaged),
            ])
    }

    @Test func rowsShowControlCharactersVisiblyAndReadAsPathAndKind() throws {
        let files = try Self.parse(GitProbeRecordings.hostile).changes.files
        func file(_ path: String) throws -> ChangedFile {
            try #require(files.first { $0.path == Data(path.utf8) })
        }
        #expect(try file("line\nbreak.txt").displayPath == "line\u{240A}break.txt")
        #expect(try file("tab\tname.txt").displayPath == "tab\u{2409}name.txt")
        #expect(try file("中文.txt").displayPath == "中文.txt")
        #expect(try file(#"two\\bs.txt"#).displayPath == #"two\\bs.txt"#)

        #expect(try file("conflict.txt").accessibilityLabel == "conflict.txt, conflicted")
        #expect(try file("untracked.txt").accessibilityLabel == "untracked.txt, untracked")
        #expect(try file("gone.txt").accessibilityLabel == "gone.txt, deleted, unstaged")
        #expect(
            try file("sp ace.txt").accessibilityLabel
                == "sp ace.txt, modified, staged and unstaged")
        #expect(
            try file("pkg/renamed.txt").accessibilityLabel
                == "pkg/renamed.txt, renamed from old/name.txt, staged")
        #expect(try file("pkg/renamed.txt").detail == "Renamed from old/name.txt · Staged")
        #expect(try file("added.txt").detail == "Added · Staged")
        #expect(try file("untracked.txt").detail == "Untracked")
    }

    /// `git add -N` on a moved file makes git pair the move as a working-tree
    /// rename (`2 .R`). Status pairs only staged renames, so the move reads
    /// as the original's deletion plus the new path's addition, and the
    /// deleted original sorts into place by its path.
    @Test func anIntentToAddMoveReadsAsADeletionPlusAnAddition() throws {
        let files = try Self.parse(GitProbeRecordings.intentToAddMove).changes.files
        #expect(
            Self.rows(files) == [
                Row(path: "a.txt", kind: .deleted, staging: .unstaged),
                Row(path: "b.txt", kind: .added, staging: .unstaged),
            ])
        #expect(
            files.map(\.accessibilityLabel) == [
                "a.txt, deleted, unstaged", "b.txt, added, unstaged",
            ])
    }

    /// A staged rename moved on in the working tree and marked with
    /// `git add -N`: its row keeps the staged rename and gains the
    /// working-tree deletion, as git reports it without `-N` (`2 RD`), and
    /// no path is listed twice.
    @Test func anIntentToAddMoveOfAStagedRenameKeepsTheRenameAndItsDeletion() throws {
        let files = try Self.parse(GitProbeRecordings.intentToAddMoveAfterStagedRename)
            .changes.files
        #expect(
            Self.rows(files) == [
                Row(path: "b.txt", kind: .renamed, staging: .both, original: "a.txt"),
                Row(path: "c.txt", kind: .added, staging: .unstaged),
            ])
        #expect(files.first?.detail == "Renamed from a.txt · Staged and unstaged")
    }

    /// Two Agents in one Checkout, one at its top and one in a subdirectory,
    /// read the same Changes; only the directory's own prefix differs.
    @Test func everyDirectoryInACheckoutReadsTheSameChanges() throws {
        let top = try Self.parse(GitProbeRecordings.hostile)
        let subdirectory = try Self.parse(GitProbeRecordings.subdir)
        #expect(subdirectory.changes == top.changes)
        #expect(subdirectory.directoryPrefix == Data("pkg/".utf8))
    }

    @Test func aLinkedWorktreeOnADetachedHeadIsNamedAsSuch() throws {
        let read = try Self.parse(GitProbeRecordings.worktree)
        #expect(read.changes.checkout.isLinkedWorktree)
        #expect(read.changes.checkout.displayPath == "~/src/app-wt")
        #expect(read.changes.checkout.topLevel == Data("/home/dev/src/app-wt".utf8))
        #expect(read.directoryPrefix == Data("src/".utf8))
        #expect(read.changes.head.branch == .detached)
        #expect(read.changes.head.branchTitle == "Detached at 4f87954")
        #expect(read.changes.head.latestCommit?.subject == "Seed the fixture repository")
        #expect(
            Self.rows(read.changes.files) == [
                Row(path: "src/main.c", kind: .modified, staging: .unstaged)
            ])
    }

    @Test func aCleanCheckoutHasNoFiles() throws {
        let changes = try Self.parse(GitProbeRecordings.clean).changes
        #expect(changes.isClean)
        #expect(changes.head.branchTitle == "main")
        #expect(changes.head.latestCommit?.subject == "Clean tree")
    }

    @Test func anUnbornHeadHasNoCommitButStillHasChanges() throws {
        let changes = try Self.parse(GitProbeRecordings.unborn).changes
        #expect(changes.head.commit == nil)
        #expect(changes.head.latestCommit == nil)
        #expect(changes.head.branch == .named("main"))
        #expect(
            Self.rows(changes.files) == [
                Row(path: "loose.txt", kind: .untracked, staging: nil),
                Row(path: "staged.txt", kind: .added, staging: .staged),
            ])
    }

    @Test func sha256ObjectIdsParse() throws {
        let changes = try Self.parse(GitProbeRecordings.sha256).changes
        #expect(
            changes.head.commit
                == "96cb513b57469caefccadcc0cd6e2ddfcf9697b779213889cb888f601223f79e")
        #expect(changes.head.branchTitle == "main")
        #expect(
            Self.rows(changes.files) == [
                Row(path: "a.txt", kind: .modified, staging: .unstaged)
            ])
    }

    @Test func aDirectoryOutsideAnyWorkingTreeIsNotAGitWorkingTree() {
        #expect(Self.failure(GitProbeRecordings.plain) == .notAGitWorkingTree)
        #expect(Self.failure(GitProbeRecordings.gitdir) == .notAGitWorkingTree)
    }

    @Test func loginShellNoiseOnBothStreamsIsIgnored() throws {
        #expect(
            GitProbeRecordings.noise.stdout.starts(with: Data("Last login:".utf8)))
        #expect(try Self.parse(GitProbeRecordings.noise) == Self.parse(GitProbeRecordings.clean))
    }

    @Test(arguments: ["version", "home", "discover", "status", "numstat", "head"])
    func aMissingFramedStatusIsIncomplete(section: String) {
        let stdout = String(decoding: GitProbeRecordings.clean.stdout, as: UTF8.self)
        let line = "\n__HEELER_GIT_F00D__ \(section) rc=0\n"
        #expect(stdout.contains(line))
        let cut = stdout.replacingOccurrences(of: line, with: "\n")
        #expect(
            Self.failure((Data(cut.utf8), GitProbeRecordings.clean.stderr)) == .incomplete)
    }

    @Test func aStatusKilledBeforeItsNumberIsIncomplete() {
        // `echo "$?"` never ran: the framed status is empty.
        let stdout = String(decoding: GitProbeRecordings.clean.stdout, as: UTF8.self)
            .replacingOccurrences(
                of: "__HEELER_GIT_F00D__ status rc=0\n", with: "__HEELER_GIT_F00D__ status rc=\n")
        #expect(
            Self.failure((Data(stdout.utf8), GitProbeRecordings.clean.stderr)) == .incomplete)
    }

    @Test func aMissingFinalMarkerIsIncomplete() {
        let stdout = String(decoding: GitProbeRecordings.clean.stdout, as: UTF8.self)
            .replacingOccurrences(of: "\n__HEELER_GIT_F00D__ done\n", with: "\n")
        #expect(
            Self.failure((Data(stdout.utf8), GitProbeRecordings.clean.stderr)) == .incomplete)
    }

    @Test func markersCarryingAnotherRequestsNonceAreIgnored() throws {
        // Complete output, but from another request: nothing matches.
        #expect(Self.failure(GitProbeRecordings.clean, nonce: "BEEF") == .incomplete)

        // Another request's complete output ahead of this one's.
        func renonced(_ data: Data) -> Data {
            Data(
                String(decoding: data, as: UTF8.self)
                    .replacingOccurrences(of: "__HEELER_GIT_F00D__", with: "__HEELER_GIT_BEEF__")
                    .utf8)
        }
        let stdout = GitProbeRecordings.hostile.stdout + renonced(GitProbeRecordings.clean.stdout)
        let stderr = GitProbeRecordings.hostile.stderr + renonced(GitProbeRecordings.clean.stderr)
        #expect(
            try Self.parse((stdout, stderr), nonce: "BEEF")
                == Self.parse(GitProbeRecordings.clean))
    }

    @Test func outputOverItsCapIsCutAndMarkedTruncatedByLengthAlone() throws {
        let marker = "__HEELER_GIT_F00D__"
        let stdout = Data("\n\(marker) status begin\n1234567890\n\(marker) status rc=0\n".utf8)
        let frames = GitProbe.Frames(stdout: stdout, stderr: Data(), nonce: "F00D")
        let cut = try #require(try frames.section("status", cap: 4))
        #expect(cut.body == Data("1234".utf8))
        #expect(cut.isTruncated)
        #expect(cut.status == 0)
        let whole = try #require(try frames.section("status", cap: 10))
        #expect(!whole.isTruncated)
        #expect(whole.body == Data("1234567890".utf8))
    }

    @Test func aCutStatusKeepsOnlyItsCompleteRecords() {
        let body = Data(
            "# branch.oid (initial)\0# branch.head main\0? kept.txt\0? cut-o".utf8)
        let report = GitProbe.parseStatus(body)
        #expect(Self.rows(report.files) == [Row(path: "kept.txt", kind: .untracked, staging: nil)])

        // A rename whose original path was cut off is dropped, not guessed.
        let rename = Data(
            "2 R. N... 100644 100644 100644 a a R100 new.txt\0".utf8)
        #expect(GitProbe.parseStatus(rename).files.isEmpty)
    }

    @Test func failuresCarryGitsFirstFramedErrorLine() throws {
        let marker = "__HEELER_GIT_F00D__"
        let stdout = Data(
            """

            \(marker) version begin
            git version 2.55.0

            \(marker) version rc=0

            \(marker) home begin
            /home/dev
            \(marker) home rc=0

            \(marker) discover begin

            \(marker) discover rc=128

            \(marker) done

            """.utf8)
        let stderr = Data(
            """

            \(marker) discover begin
            fatal: bad config line 3 in file .git/config
            hint: fix the file and try again

            \(marker) discover end

            """.utf8)
        #expect(
            Self.failure((stdout, stderr))
                == .gitFailed("fatal: bad config line 3 in file .git/config"))
    }

    @Test func theLatestCommitAgeIsRelativeAndNeverInTheFuture() {
        let now = Date(timeIntervalSince1970: 1_790_600_000)
        let locale = Locale(identifier: "en_US")
        let twoHoursAgo = LatestCommit(
            subject: "s", committedAt: now.addingTimeInterval(-7_200))
        #expect(twoHoursAgo.age(relativeTo: now, locale: locale) == "2 hours ago")
        let ahead = LatestCommit(subject: "s", committedAt: now.addingTimeInterval(600))
        #expect(ahead.age(relativeTo: now, locale: locale) == "just now")
    }
}

/// Just enough POSIX sh word parsing to check quoting: single-quoted spans,
/// backslash escapes outside quotes, and the word's end at unquoted blank.
private struct ShellWord {
    let value: String
    /// True when nothing but `\'` sits outside single quotes.
    let isQuotedOnly: Bool
    let end: String.Index

    static func parse(_ text: Substring) -> ShellWord? {
        var value = ""
        var quotedOnly = true
        var index = text.startIndex
        var inQuotes = false
        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "'" { inQuotes = false } else { value.append(character) }
            } else if character == "'" {
                inQuotes = true
            } else if character == "\\" {
                let next = text.index(after: index)
                guard next < text.endIndex else { return nil }
                if text[next] != "'" { quotedOnly = false }
                value.append(text[next])
                index = next
            } else if character == " " || character == "\n" || character == "\t"
                || character == ";"
            {
                break
            } else {
                quotedOnly = false
                value.append(character)
            }
            index = text.index(after: index)
        }
        guard !inQuotes, !value.isEmpty else { return nil }
        return ShellWord(value: value, isQuotedOnly: quotedOnly, end: index)
    }
}
