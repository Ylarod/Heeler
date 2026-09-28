import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Heeler

@MainActor
@Suite("File diff view", .timeLimit(.minutes(1)))
struct FileDiffViewTests {
    @Test func openingAnUntrackedFileAndGoingBackKeepsTheList() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([.success(Self.changesRead())])
        await transport.scriptFilePatchReads([.success(Self.patch())])
        let store = Self.store(transport: transport)
        let backs = ChangesViewTests.Counter()
        let controller = UIHostingController(
            rootView: NavigationStack {
                ChangesView(store: store) { backs.count += 1 }
            })
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874),
            rootViewController: controller)
        defer { window.isHidden = true }

        try #require(await ChangesViewTests.eventually {
            ChangesViewTests.activate("untracked.txt, untracked", in: controller.view)
        })
        try #require(await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains("Added, line 1: new content")
        })
        #expect(!ChangesViewTests.labels(in: controller).contains("untracked.txt, untracked"))
        #expect(await transport.filePatchRequests.count == 1)

        try #require(await ChangesViewTests.eventually {
            ChangesViewTests.activate("Back", in: controller.view)
        })
        try #require(await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains("untracked.txt, untracked")
        })
        #expect(store.fileDiff.current == nil)
        #expect(backs.count == 0)
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func allLineKindsAndTheMissingNewlineReadAtAccessibilityTextSizes() async throws {
        let lines = [
            DiffLine(id: 0, kind: .removed, oldNumber: 8, newNumber: nil, text: "old value"),
            DiffLine(id: 1, kind: .added, oldNumber: nil, newNumber: 8, text: "new value"),
            DiffLine(
                id: 2, kind: .context, oldNumber: 9, newNumber: 9, text: "closing line",
                missingNewline: true),
        ]
        let patch = FilePatch(
            files: [
                DiffFile(
                    id: 0, oldPath: "sample.txt", newPath: "sample.txt", summary: nil,
                    isBinary: false,
                    hunks: [
                        DiffHunk(
                            id: 0, oldStart: 8, oldCount: 2, newStart: 8, newCount: 2,
                            section: "updateValue()", lines: lines)
                    ])
            ], isTruncated: false)
        let store = FileDiffStore(
            file: Self.file, checkout: Self.changesRead().changes.checkout, read: { _ in patch })
        let controller = UIHostingController(
            rootView: FileDiffView(store: store)
                .environment(\.dynamicTypeSize, .accessibility1)
                .environment(\.colorScheme, .dark))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 1200),
            rootViewController: controller)
        defer { window.isHidden = true }

        var labels = Set<String>()
        try #require(await ChangesViewTests.eventually {
            labels = ChangesViewTests.labels(in: controller)
            return labels.contains("Unchanged, line 9: closing line. No newline at end of file.")
        })
        #expect(labels.contains("Removed, line 8: old value"))
        #expect(labels.contains("Added, line 8: new value"))
        #expect(labels.contains("@@ -8,2 +8,2 @@ updateValue()"))
    }

    @Test func loadMoreTurnsIntoTheModelsTooLargeFooter() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([.success(Self.changesRead())])
        await transport.scriptFilePatchReads([
            .success(Self.patch(isTruncated: true)), .success(Self.patch(isTruncated: true)),
        ])
        let changes = Self.store(transport: transport)
        await changes.appear()
        changes.openDiff(Self.file)
        let diff = try #require(changes.fileDiff.current)
        let controller = UIHostingController(rootView: FileDiffView(store: diff))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874),
            rootViewController: controller)
        defer { window.isHidden = true }

        try #require(await ChangesViewTests.eventually {
            ChangesViewTests.activate("Load More", in: controller.view)
        })
        try #expect(await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains(diff.tooLargeMessage)
        })
        #expect(!ChangesViewTests.labels(in: controller).contains("Load More"))
        #expect(await transport.changesReadRequests.count == 1)
    }

    @Test func anUntrackedDirectoryRemainsOnTheFileList() async throws {
        let directory = ChangedFile(
            path: Data("newdir/".utf8), originalPath: nil, kind: .untracked, staging: nil)
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([.success(Self.changesRead(files: [directory]))])
        let store = Self.store(transport: transport)
        let controller = UIHostingController(rootView: ChangesView(store: store) {})
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874),
            rootViewController: controller)
        defer { window.isHidden = true }
        try #require(await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains("newdir/, untracked")
        })
        // A later directory-expansion feature can make this row actionable;
        // it must still never request a patch for the directory itself.
        _ = ChangesViewTests.activate("newdir/, untracked", in: controller.view)
        #expect(store.fileDiff.current == nil)
        #expect(await transport.filePatchRequests.isEmpty)
    }

    @Test func aFailedRefreshKeepsTheReadableDiffBesideItsError() async throws {
        let transport = ScriptedTransport()
        await transport.scriptFilePatchReads([
            .success(Self.patch()), .failure(ChangesReadError.gitFailed("file moved during read")),
        ])
        let store = FileDiffStore(
            file: Self.file, checkout: Self.changesRead().changes.checkout,
            read: { try await transport.readFilePatch($0) })
        let controller = UIHostingController(rootView: FileDiffView(store: store))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874),
            rootViewController: controller)
        defer { window.isHidden = true }
        try #require(await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains("Added, line 1: new content")
        })

        await store.refresh()

        try #require(await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains("file moved during read")
        })
        #expect(ChangesViewTests.labels(in: controller).contains("Added, line 1: new content"))
    }

    @Test func diffInksHaveReadableContrastInLightAndDarkMode() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for kind in [DiffLine.Kind.added, .removed] {
                let foreground = Self.luminance(DiffPalette.ink(for: kind), style: style)
                let background = Self.luminance(DiffPalette.background(for: kind), style: style)
                let contrast = (max(foreground, background) + 0.05)
                    / (min(foreground, background) + 0.05)
                #expect(contrast >= 4.5, "\(kind) in \(style) has contrast \(contrast)")
            }
        }
    }

    private static func luminance(_ color: UIColor, style: UIUserInterfaceStyle) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let linear = [red, green, blue].map { value in
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    static func store(transport: ScriptedTransport) -> ChangesStore {
        ChangesStore(
            directory: { "/home/dev/src/app" },
            read: { try await transport.readChanges($0) },
            readPatch: { try await transport.readFilePatch($0) })
    }

    static func changesRead(files: [ChangedFile] = [file]) -> CheckoutChangesRead {
        CheckoutChangesRead(
            changes: CheckoutChanges(
                checkout: CheckoutLocation(
                    topLevel: Data("/home/dev/src/app".utf8),
                    isLinkedWorktree: false, displayPath: "~/src/app"),
                head: CheckoutHead(branch: .named("main"), commit: nil, latestCommit: nil),
                files: files),
            directoryPrefix: Data())
    }

    static let file = ChangedFile(
        path: Data("untracked.txt".utf8), originalPath: nil, kind: .untracked, staging: nil)

    static func patch(isTruncated: Bool = false) -> FilePatch {
        FilePatch(
            files: [
                DiffFile(
                    id: 0, oldPath: nil, newPath: "untracked.txt", summary: nil,
                    isBinary: false,
                    hunks: [
                        DiffHunk(
                            id: 0, oldStart: 0, oldCount: 0, newStart: 1, newCount: 1,
                            section: "new section",
                            lines: [
                                DiffLine(
                                    id: 0, kind: .added, oldNumber: nil, newNumber: 1,
                                    text: "new content", missingNewline: false)
                            ])
                    ])
            ], isTruncated: isTruncated)
    }
}
