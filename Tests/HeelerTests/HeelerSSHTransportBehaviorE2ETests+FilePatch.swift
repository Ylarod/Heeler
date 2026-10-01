import Foundation
import Testing

@testable import Heeler

extension HeelerSSHTransportBehaviorE2ETests {
    @Test("file patches read tracked and untracked content through real SSH without changing the Checkout")
    func filePatchesReadTrackedAndUntrackedContent() async throws {
        let environment = try #require(HeelerSSHTransportBehaviorEnvironment.current)
        let transport = try await HeelerSSHTransport.connect(settings: environment.directSettings())
        defer { Task { try? await transport.close() } }
        let root = try #require(RemoteShellPath.quotedAbsolute(
            environment.homePath + "/changes-file-patch-" + UUID().uuidString))
        let cleanup = Data("{ rm -rf \(root); } </dev/null\n".utf8)
        do {
            let seeded = try await transport.runGitScript(Data("""
                {
                set -e
                r=\(root)
                mkdir -p "$r"
                cd "$r"
                git init -q .
                git symbolic-ref HEAD refs/heads/main
                printf 'before\\nunchanged\\n' > tracked.txt
                git add tracked.txt
                git -c user.name=Heeler -c user.email=fixture@heeler.invalid commit -q -m 'Seed the file patch fixture'
                printf 'staged\\nunchanged\\n' > tracked.txt
                git add tracked.txt
                printf 'after\\nunchanged\\n' > tracked.txt
                printf 'new file\\nsecond line' > 'untracked file.txt'
                printf '#!/bin/sh\\n: > "%s/fsmonitor-ran"\\n' "$r" > "$r/fsmonitor.sh"
                printf '#!/bin/sh\\n: > "%s/post-index-change-ran"\\n' "$r" > .git/hooks/post-index-change
                chmod +x "$r/fsmonitor.sh" .git/hooks/post-index-change
                git config core.fsmonitor "$r/fsmonitor.sh"
                pwd -P
                stat -f '%i %Fm' .git/index
                } </dev/null

                """.utf8))
            try #require(
                seeded.exitStatus == 0,
                "seed failed: \(String(decoding: seeded.stderr, as: UTF8.self))")
            let seedLines = String(decoding: seeded.stdout, as: UTF8.self)
                .split(separator: "\n").map(String.init)
            try #require(seedLines.count == 2)
            let topLevel = Data(seedLines[0].utf8)
            let indexBefore = seedLines[1]
            let checkout = CheckoutLocation(
                topLevel: topLevel, isLinkedWorktree: false, displayPath: seedLines[0])
            let tracked = ChangedFile(
                path: Data("tracked.txt".utf8), originalPath: nil,
                kind: .modified, staging: .both)
            let untracked = ChangedFile(
                path: Data("untracked file.txt".utf8), originalPath: nil,
                kind: .untracked, staging: nil)
            let trackedRequest = try #require(FilePatchRequest(file: tracked, checkout: checkout))
            let untrackedRequest = try #require(FilePatchRequest(file: untracked, checkout: checkout))

            // Exercise the purpose-built protocol requirements, including
            // no-index's successful exit status of 1 for the untracked file.
            let reader: any Transport = transport
            let trackedPatch = try await reader.readFilePatch(trackedRequest)
            let untrackedPatch = try await reader.readFilePatch(untrackedRequest)
            let trackedLines = trackedPatch.files.flatMap(\.hunks).flatMap(\.lines)
            #expect(trackedLines.map(\.text) == ["before", "after", "unchanged"])
            #expect(trackedLines.map(\.kind) == [.removed, .added, .context])
            #expect(trackedLines.map(\.oldNumber) == [1, nil, 2])
            #expect(trackedLines.map(\.newNumber) == [nil, 1, 2])
            #expect(!trackedPatch.isTruncated)

            let newLines = untrackedPatch.files.flatMap(\.hunks).flatMap(\.lines)
            #expect(newLines.map(\.text) == ["new file", "second line"])
            #expect(newLines.allSatisfy { $0.kind == .added })
            #expect(newLines.map(\.newNumber) == [1, 2])
            #expect(newLines.last?.missingNewline == true)
            #expect(untrackedPatch.files.first?.newPath == "untracked file.txt")
            #expect(!untrackedPatch.isTruncated)

            let after = try await transport.runGitScript(Data("""
                { r=\(root); cd "$r"; stat -f '%i %Fm' .git/index
                for marker in fsmonitor-ran post-index-change-ran; do
                  if [ -e "$r/$marker" ]; then echo "$marker"; fi
                done
                } </dev/null

                """.utf8))
            #expect(after.exitStatus == 0)
            #expect(String(decoding: after.stdout, as: UTF8.self) == indexBefore + "\n")
        } catch {
            _ = try? await transport.runGitScript(cleanup)
            throw error
        }
        let cleaned = try await transport.runGitScript(cleanup)
        #expect(cleaned.exitStatus == 0)
    }
}
