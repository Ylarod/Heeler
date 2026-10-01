import Foundation
import Testing

@testable import Heeler

extension HeelerSSHTransportBehaviorE2ETests {
    @Test("a Changes read distinguishes an outside directory from a missing directory")
    func changesReadDistinguishesDirectoryFailures() async throws {
        let environment = try #require(HeelerSSHTransportBehaviorEnvironment.current)
        let root = try #require(RemoteShellPath.quotedAbsolute(
            environment.homePath + "/changes-failure-states-" + UUID().uuidString))
        let transport = try await HeelerSSHTransport.connect(settings: environment.directSettings())
        defer { Task { try? await transport.close() } }
        let cleanup = Data("{ rm -rf \(root); } </dev/null\n".utf8)

        do {
            let seeded = try await transport.runGitScript(Data("""
                {
                set -e
                r=\(root)
                mkdir -p "$r/repo" "$r/outside"
                cd "$r/repo"
                git init -q .
                git symbolic-ref HEAD refs/heads/main
                git -c user.name=Heeler -c user.email=fixture@heeler.invalid commit -q --allow-empty -m 'Seed the Changes failure fixture'
                pwd -P
                cd "$r"
                pwd -P
                } </dev/null

                """.utf8))
            try #require(
                seeded.exitStatus == 0,
                "seed failed: \(String(decoding: seeded.stderr, as: UTF8.self))")
            let seedLines = String(decoding: seeded.stdout, as: UTF8.self)
                .split(separator: "\n").map(String.init)
            try #require(seedLines.count >= 2)
            let topLevel = seedLines[seedLines.count - 2]
            let physicalRoot = seedLines[seedLines.count - 1]

            let read = try await transport.readChanges(ChangesReadRequest(directory: topLevel))
            #expect(read.changes.checkout.topLevel == Data(topLevel.utf8))
            #expect(read.changes.files.isEmpty)

            await #expect(throws: ChangesReadError.notAGitWorkingTree) {
                _ = try await transport.readChanges(
                    ChangesReadRequest(directory: physicalRoot + "/outside"))
            }
            await #expect(throws: ChangesReadError.directoryMissing) {
                _ = try await transport.readChanges(
                    ChangesReadRequest(directory: physicalRoot + "/missing"))
            }
            #expect(await transport.isConnected)
        } catch {
            _ = try? await transport.runGitScript(cleanup)
            throw error
        }

        let cleaned = try await transport.runGitScript(cleanup)
        #expect(cleaned.exitStatus == 0)
    }
}
