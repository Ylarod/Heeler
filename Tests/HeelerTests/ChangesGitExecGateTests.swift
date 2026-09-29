import Foundation
import Testing

@testable import Heeler

@MainActor
@Suite("Changes git exec gate", .timeLimit(.minutes(1)))
struct ChangesGitExecGateTests {
    private static func store(_ transport: ScriptedTransport, gate: GitExecGate?) -> ChangesStore {
        ChangesStore(
            directory: { "/home/dev/src/app" },
            read: { try await transport.readChanges($0) },
            readPatch: { try await transport.readFilePatch($0) },
            listUntrackedDirectory: { try await transport.listUntrackedDirectory($0) },
            gate: gate)
    }

    @Test func twoStoresOnOneHostShareOneExecAndTheWaiterShowsLoading() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        await transport.scriptChangesReads([.success(read), .success(read)])
        let localExec = ScriptedTransportCallGate()
        await transport.gateNextChangesRead(using: localExec)
        let gate = GitExecGate()
        let first = Self.store(transport, gate: gate)
        let second = Self.store(transport, gate: gate)
        let a = Task { await first.appear() }
        await localExec.waitForEntry()
        let b = Task { await second.appear() }
        await Self.drain()
        #expect(second.phase == .loading)
        #expect(await transport.changesReadRequests.count == 1)
        await localExec.open()
        await a.value
        await b.value
        #expect(first.phase == .loaded(read.changes))
        #expect(second.phase == .loaded(read.changes))
        #expect(await transport.changesReadRequests.count == 2)
    }

    private static func drain() async {
        for _ in 0..<100 { await Task.yield() }
    }
}
