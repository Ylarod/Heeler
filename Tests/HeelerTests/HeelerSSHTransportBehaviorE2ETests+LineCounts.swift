import Foundation
import Testing

@testable import Heeler

extension HeelerSSHTransportBehaviorE2ETests {
    @Test("a Changes read counts lines from the seeded repository in its one exec")
    func changesLineCountsUseTheOneExec() async throws {
        let environment = try #require(HeelerSSHTransportBehaviorEnvironment.current)
        let transport = try await HeelerSSHTransport.connect(settings: environment.directSettings())
        defer { Task { try? await transport.close() } }
        let root = try #require(RemoteShellPath.quotedAbsolute(
            environment.homePath + "/changes-line-counts-" + UUID().uuidString))
        let seeded = try await transport.runGitScript(Data("""
            {
            set -e
            r=\(root)
            mkdir -p "$r/repo/sub"
            cd "$r/repo"
            git init -q .
            git symbolic-ref HEAD refs/heads/main
            printf 'one\\ntwo\\nthree\\n' > tracked.txt
            printf 'two\\n' > other.txt
            printf '\\000\\001' > logo.bin
            printf 'nested\\n' > sub/nested.txt
            git add -A
            git -c user.name=Heeler -c user.email=fixture@heeler.invalid commit -q -m 'Seed the line counts fixture'
            printf 'one\\nTWO\\nthree\\nfour\\n' > tracked.txt
            git mv other.txt renamed.txt
            printf '\\000\\002\\003' > logo.bin
            printf 'new\\n' > untracked.txt
            touch -t 203001010000 sub/nested.txt
            pwd -P
            } </dev/null

            """.utf8))
        try #require(
            seeded.exitStatus == 0, "seed failed: \(String(decoding: seeded.stderr, as: UTF8.self))")
        let topLevel = try #require(String(decoding: seeded.stdout, as: UTF8.self)
            .split(separator: "\n").last.map(String.init))

        // One real exec produces both the file list and all counts. The
        // public read below must return that same document; readChanges
        // uses this exact script once, with no per-file requests.
        let nonce = GitProbe.makeNonce()
        let exec = try await transport.runGitScript(
            GitProbe.changesScript(directory: topLevel + "/sub", nonce: nonce))
        #expect(exec.exitStatus == 0)
        let single = try GitProbe.parseChanges(stdout: exec.stdout, stderr: exec.stderr, nonce: nonce)
        let read = try await transport.readChanges(ChangesReadRequest(directory: topLevel + "/sub"))
        #expect(read == single)
        #expect(read.directoryPrefix == Data("sub/".utf8))
        let changes = read.changes
        #expect(changes.checkout.topLevel == Data(topLevel.utf8))
        #expect(changes.files.map(\.displayPath) == [
            "logo.bin", "renamed.txt", "tracked.txt", "untracked.txt",
        ])
        #expect(changes.files.first { $0.displayPath == "tracked.txt" }?.lineCounts
            == .lines(added: 2, removed: 1))
        let renamed = try #require(changes.files.first { $0.displayPath == "renamed.txt" })
        #expect(renamed.originalPath == Data("other.txt".utf8))
        #expect(renamed.lineCounts == .lines(added: 0, removed: 0))
        #expect(changes.files.first { $0.displayPath == "logo.bin" }?.lineCounts == .binary)
        #expect(changes.files.first { $0.displayPath == "untracked.txt" }?.lineCounts == nil)
        #expect(changes.totals.trackedFiles == 3)
        #expect(changes.totals.untrackedItems == 1)
        #expect(changes.totals.added == 2)
        #expect(changes.totals.removed == 1)
        #expect(changes.totals.linesAreComplete)

        let removed = try await transport.runGitScript(Data("""
            { rm -rf \(root); } </dev/null

            """.utf8))
        #expect(removed.exitStatus == 0)
    }
}
