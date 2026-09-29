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
        #expect(store.pathReference(for: Self.file("pkg/")) == ".")
        #expect(store.insertionText(for: Self.file("pkg/")) == ". ")
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

    @Test func changedAndRemovedLinesReferenceTheNewFileWithoutSubmitting() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadedDiff(transport, patch: Self.modifiedPatch)
        var inserted: [String] = []
        store.insertReference = { inserted.append($0) }
        #expect(store.insertionText(forLine: 0) == "modified.txt:1 ")
        #expect(store.insertionText(forLine: 1) == "modified.txt:2 ")
        #expect(store.insertionText(forLine: 2) == "modified.txt:2 ")
        #expect(store.insertionText(forLine: 3) == "modified.txt:3 ")
        store.insert(line: 1)
        store.insert(line: 2)
        #expect(inserted == ["modified.txt:2 ", "modified.txt:2 "])
        #expect(await transport.agentPromptParams.isEmpty)
        #expect(await transport.attachInputs.isEmpty)
    }

    @Test(arguments: [
        ("@@ -1,2 +0,0 @@\n-gone\n-again\n", "modified.txt:1 "),
        ("@@ -1,3 +1 @@\n first\n-old\n-last\n", "modified.txt:1 "),
        ("@@ -20,2 +20 @@\n first\n-last\n", "modified.txt:20 "),
    ])
    func removalsAtTheEndClampToAnAvailableNewLine(hunk: String, expected: String) async throws {
        let transport = ScriptedTransport()
        let patch = "diff --git a/pkg/modified.txt b/pkg/modified.txt\n" + hunk
        let store = try await Self.loadedDiff(transport, patch: patch)
        #expect(store.insertionText(forLine: 1) == expected)
    }

    @Test func aFailedListRefreshFallsBackToTheOpenDiffsAbsolutePath() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadedDiff(transport, patch: Self.modifiedPatch)
        await transport.scriptChangesReads([.failure(ChangesReadError.incomplete)])
        await store.refresh()
        #expect(store.insertionText(forLine: 1) == "/home/dev/src/app/pkg/modified.txt:2 ")
    }

    @Test func copiesUseTheInjectedPasteboardAndPreserveRemovedText() async throws {
        let transport = ScriptedTransport()
        let store = try await Self.loadedDiff(transport, patch: Self.modifiedPatch)
        var copied: [String] = []
        store.copyToPasteboard = { copied.append($0) }
        store.copyPath(Self.file("pkg/modified.txt"))
        store.copyLine(1)
        store.copyHunk(0)
        #expect(copied == [
            "modified.txt",
            "old",
            "@@ -1,3 +1,3 @@ section\n first\n-old\n+new\n last\n",
        ])
        #expect(await transport.agentPromptParams.isEmpty)
        #expect(await transport.attachInputs.isEmpty)
    }

    @Test func copyingAHunkKeepsGitRangeSyntaxAndMissingNewlineMarkers() async throws {
        let transport = ScriptedTransport()
        let patch = "diff --git a/pkg/modified.txt b/pkg/modified.txt\n"
            + "@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file\n"
        let store = try await Self.loadedDiff(transport, patch: patch)
        var copied: [String] = []
        store.copyToPasteboard = { copied.append($0) }
        store.copyHunk(0)
        #expect(copied == [
            "@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file\n"
        ])
    }

    @Test func controlCharactersRemainCopyableButNotInsertableFromTheDiff() async throws {
        let transport = ScriptedTransport()
        let file = Self.file("pkg/line\nbreak.txt")
        let store = try await Self.loadedDiff(transport, patch: Self.modifiedPatch, file: file)
        var copied: [String] = []
        var inserted: [String] = []
        store.copyToPasteboard = { copied.append($0) }
        store.insertReference = { inserted.append($0) }
        store.copyPath(file)
        store.copyLine(1)
        store.insert(line: 1)
        #expect(copied == ["line\nbreak.txt", "old"])
        #expect(store.insertionText(forLine: 1) == nil)
        #expect(inserted.isEmpty)
    }

    private static let modifiedPatch = """
        diff --git a/pkg/modified.txt b/pkg/modified.txt
        --- a/pkg/modified.txt
        +++ b/pkg/modified.txt
        @@ -1,3 +1,3 @@ section
         first
        -old
        +new
         last

        """

    private static func loadedDiff(
        _ transport: ScriptedTransport, patch: String,
        file: ChangedFile? = nil
    ) async throws -> ChangesStore {
        await transport.scriptChangesReads([
            .success(try ChangesStoreTests.read(GitProbeRecordings.subdir))
        ])
        let parsed = FilePatch(
            files: GitProbe.parsePatchFiles(Data(patch.utf8), isTruncated: false),
            isTruncated: false)
        await transport.scriptFilePatchReads([.success(parsed)])
        let store = Self.store(transport)
        await store.appear()
        store.openDiff(file ?? Self.file("pkg/modified.txt"))
        let diff = try #require(store.fileDiff.current)
        await diff.appear()
        return store
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
