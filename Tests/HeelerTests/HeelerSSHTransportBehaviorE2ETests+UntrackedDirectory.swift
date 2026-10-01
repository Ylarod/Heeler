import Foundation
import Testing

@testable import Heeler

extension HeelerSSHTransportBehaviorE2ETests {
    @Test("an untracked directory lists its files over one exec")
    func untrackedDirectoryListsItsFiles() async throws {
        let environment = try #require(HeelerSSHTransportBehaviorEnvironment.current)
        let transport = try await HeelerSSHTransport.connect(settings: environment.directSettings())
        defer { Task { try? await transport.close() } }
        let root = try #require(
            RemoteShellPath.quotedAbsolute(
                environment.homePath + "/changes-untracked-" + UUID().uuidString))
        let cleanup = Data(
            """
            { rm -rf \(root); } </dev/null

            """.utf8)
        do {
            try await listSeededDirectory(on: transport, root: root)
        } catch {
            _ = try? await transport.runGitScript(cleanup)
            throw error
        }
        _ = try await transport.runGitScript(cleanup)
    }

    private func listSeededDirectory(on transport: HeelerSSHTransport, root: String) async throws {
        let seeded = try await transport.runGitScript(
            Data(
                """
                {
                set -e
                r=\(root)
                mkdir -p "$r/repo/newdir/deep" "$r/repo/newdir/inner"
                cd "$r/repo"
                git init -q .
                git symbolic-ref HEAD refs/heads/main
                printf 'one\\n' > tracked.txt
                git add tracked.txt
                git -c user.name=Heeler -c user.email=fixture@heeler.invalid commit -q -m 'Seed an untracked directory'
                printf 'a\\n' > newdir/a.txt
                printf 'b\\n' > newdir/deep/b.txt
                printf 's\\n' > 'newdir/sp ace.txt'
                printf 'c\\n' > 'newdir/[ab].txt'
                printf 'skip\\n' > newdir/skip.log
                printf '%s\\n' '*.log' >> .git/info/exclude
                git init -q newdir/inner
                printf 'hidden\\n' > newdir/inner/secret.txt
                pwd -P
                stat -f '%i %Fm' .git/index
                } </dev/null

                """.utf8))
        try #require(
            seeded.exitStatus == 0,
            "seed failed: \(String(decoding: seeded.stderr, as: UTF8.self))")
        let seedLines = String(decoding: seeded.stdout, as: UTF8.self)
            .split(separator: "\n").map(String.init)
        try #require(seedLines.count >= 2)
        let topLevel = seedLines[seedLines.count - 2]
        let indexBefore = seedLines[seedLines.count - 1]

        let read = try await transport.readChanges(ChangesReadRequest(directory: topLevel))
        let changes = read.changes
        #expect(changes.checkout.topLevel == Data(topLevel.utf8))
        #expect(changes.head.branch == .named("main"))
        let directory = try #require(changes.files.first { $0.isUntrackedDirectory })
        #expect(directory.path == Data("newdir/".utf8))
        #expect(directory.kind == .untracked)
        #expect(directory.staging == nil)

        let listing = try await transport.listUntrackedDirectory(
            UntrackedDirectoryRequest(
                topLevel: changes.checkout.topLevel, directory: directory.path))
        #expect(
            listing.entries.map { String(decoding: $0.path, as: UTF8.self) } == [
                "newdir/[ab].txt",
                "newdir/a.txt",
                "newdir/deep/b.txt",
                "newdir/inner/",
                "newdir/sp ace.txt",
            ])
        #expect(listing.total == 5)
        #expect(!listing.isTruncated)
        #expect(!listing.isSeparateRepository)
        #expect(listing.limitNotice == nil)
        #expect(
            listing.entries.allSatisfy {
                $0.kind == .untracked && $0.staging == nil && $0.originalPath == nil
            })
        let nested = try #require(
            listing.entries.first { $0.path == Data("newdir/inner/".utf8) })
        #expect(nested.isUntrackedDirectory)
        #expect(
            !listing.entries.contains {
                let path = String(decoding: $0.path, as: UTF8.self)
                return path.contains("skip.log") || path.contains("secret.txt")
            })

        let after = try await transport.runGitScript(
            Data(
                """
                { r=\(root); cd "$r/repo"; stat -f '%i %Fm' .git/index
                } </dev/null

                """.utf8))
        let afterLines = String(decoding: after.stdout, as: UTF8.self)
            .split(separator: "\n").map(String.init)
        #expect(afterLines == [indexBefore])
    }
}
