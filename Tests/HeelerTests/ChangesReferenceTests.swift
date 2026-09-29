import Foundation
import Testing

@testable import Heeler

@MainActor
@Suite("Changes references")
struct ChangesReferenceTests {
    @Test func fileReferencesUseTheDiscoveredAgentPrefixAndOneTrailingSpace() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.subdir)
        await transport.scriptChangesReads([.success(read)])
        // The reported directory can be a symlink. Git's prefix owns relativity.
        let store = Self.store(transport)
        await store.appear()
        var inserted: [String] = []
        store.insertReference = { inserted.append($0) }

        let inside = Self.file("pkg/renamed.txt")
        let outside = Self.file("added.txt")
        #expect(store.insertionText(for: inside) == "renamed.txt ")
        #expect(store.insertionText(for: outside) == "/home/dev/src/app/added.txt ")
        #expect(store.insertionText(for: Self.file("pkg-other/file")) == "/home/dev/src/app/pkg-other/file ")
        store.insert(file: inside)
        store.insert(file: outside)
        #expect(inserted == ["renamed.txt ", "/home/dev/src/app/added.txt "])
        #expect(await transport.agentPromptParams.isEmpty)
        #expect(await transport.attachInputs.isEmpty)
    }

    @Test func topLevelAndFixedDirectoryReferencesChooseTheRightBase() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([
            .success(try ChangesStoreTests.read(GitProbeRecordings.hostile))
        ])
        let store = Self.store(transport)
        await store.appear()
        let file = Self.file("sp ace'文件.txt")
        #expect(store.insertionText(for: file) == "sp ace'文件.txt ")

        store.referencesFollowAgentDirectory = false
        #expect(store.insertionText(for: file) == "/home/dev/src/app/sp ace'文件.txt ")
    }

    @Test(arguments: ["line\nbreak.txt", "tab\tname.txt", "return\rname", "escape\u{1B}", "c1\u{85}", "delete\u{7F}"])
    func controlCharacterPathsCannotInsert(path: String) async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([
            .success(try ChangesStoreTests.read(GitProbeRecordings.hostile))
        ])
        let store = Self.store(transport)
        await store.appear()
        var inserted: [String] = []
        store.insertReference = { inserted.append($0) }
        let file = Self.file(path)
        #expect(store.pathReference(for: file) == path)
        #expect(store.insertionText(for: file) == nil)
        store.insert(file: file)
        #expect(inserted.isEmpty)
    }

    private static func store(_ transport: ScriptedTransport) -> ChangesStore {
        ChangesStore(
            directory: { "/symlink/app/pkg" },
            read: { try await transport.readChanges($0) },
            readPatch: { try await transport.readFilePatch($0) })
    }

    private static func file(_ path: String) -> ChangedFile {
        ChangedFile(
            path: Data(path.utf8), originalPath: nil,
            kind: .modified, staging: .unstaged)
    }
}
