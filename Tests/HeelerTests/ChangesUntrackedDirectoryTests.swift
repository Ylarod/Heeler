import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Heeler

/// Expanding an untracked directory over the scripted Transport, and what a
/// refresh does to that expansion.
@MainActor
@Suite("Changes untracked directories", .timeLimit(.minutes(1)))
struct ChangesUntrackedDirectoryStoreTests {
    @Test func aTransportWithoutGitReportsTheListingUnavailable() async {
        let transport = FakeTransport(
            pingResult: .success(ServerInfo(version: "0.9.0", protocolVersion: 22)))
        let request = UntrackedDirectoryRequest(
            topLevel: Data("/home/dev/src/app".utf8), directory: Data("newdir/".utf8))
        await #expect(throws: ChangesReadError.unavailable) {
            _ = try await transport.listUntrackedDirectory(request)
        }
    }

    @Test func anUnscriptedListingReportsChangesUnavailable() async {
        let transport = ScriptedTransport()
        let request = UntrackedDirectoryRequest(
            topLevel: Data("/home/dev/src/app".utf8), directory: Data("newdir/".utf8))
        await #expect(throws: ChangesReadError.unavailable) {
            _ = try await transport.listUntrackedDirectory(request)
        }
    }

    @Test func tappingADirectoryListsItsFilesAndTappingAgainCollapsesIt() async throws {
        let transport = ScriptedTransport()
        let (store, read, directory) = try await Self.loaded(transport)
        let listing = try Self.listing()
        await transport.scriptUntrackedDirectoryListings([.success(listing)])
        let gate = ScriptedTransportCallGate()
        await transport.gateNextUntrackedDirectoryListing(using: gate)

        let expanding = Task { await store.toggleDirectory(directory) }
        await gate.waitForEntry()
        #expect(store.untrackedDirectories.expansion(for: directory.path) == .loading)
        #expect(store.phase == .loaded(read.changes))

        await gate.open()
        await expanding.value
        #expect(store.untrackedDirectories.expansion(for: directory.path) == .loaded(listing))
        let requests = await transport.untrackedDirectoryRequests
        #expect(
            requests == [
                UntrackedDirectoryRequest(
                    topLevel: read.changes.checkout.topLevel, directory: directory.path)
            ])
        #expect(requests.first?.directory == Data("newdir/".utf8))

        await store.toggleDirectory(directory)
        #expect(store.untrackedDirectories.expansion(for: directory.path) == nil)
        #expect(await transport.untrackedDirectoryRequests.count == 1)
    }

    @Test func theListingReachesTheStoreUnchanged() async throws {
        let transport = ScriptedTransport()
        let (store, _, directory) = try await Self.loaded(transport)
        let listing = try GitProbe.parseUntrackedDirectory(
            stdout: GitProbeRecordings.untrackedListing.stdout,
            stderr: GitProbeRecordings.untrackedListing.stderr,
            nonce: GitProbeRecordings.nonce,
            directory: Data("newdir/".utf8),
            displayLimit: 2)
        await transport.scriptUntrackedDirectoryListings([.success(listing)])

        await store.toggleDirectory(directory)

        #expect(store.untrackedDirectories.expansion(for: directory.path) == .loaded(listing))
        #expect(listing.total == 18)
        #expect(listing.entries.count == 2)
        #expect(listing.limitNotice != nil)
    }

    @Test func aRefreshCollapsesExpandedDirectoriesWithoutListingAgain() async throws {
        let transport = ScriptedTransport()
        let (store, read, directory) = try await Self.loaded(transport)
        await transport.scriptUntrackedDirectoryListings([.success(try Self.listing())])
        await store.toggleDirectory(directory)
        #expect(store.untrackedDirectories.expansion(for: directory.path) != nil)

        await transport.scriptChangesReads([.success(read)])
        await store.refresh()

        #expect(store.untrackedDirectories.expansion(for: directory.path) == nil)
        #expect(await transport.untrackedDirectoryRequests.count == 1)
        #expect(await transport.changesReadRequests.count == 2)
    }

    @Test func aFailedRefreshKeepsTheExpansionUntilTheNextSuccess() async throws {
        let transport = ScriptedTransport()
        let (store, read, directory) = try await Self.loaded(transport)
        let listing = try Self.listing()
        await transport.scriptUntrackedDirectoryListings([.success(listing)])
        await store.toggleDirectory(directory)

        await transport.scriptChangesReads([.failure(TransportError.gitTimedOut)])
        await store.refresh()
        #expect(store.untrackedDirectories.expansion(for: directory.path) == .loaded(listing))

        await transport.scriptChangesReads([.success(read)])
        await store.refresh()
        #expect(store.untrackedDirectories.expansion(for: directory.path) == nil)
    }

    @Test func aListingThatLandsAfterARefreshIsDiscarded() async throws {
        let transport = ScriptedTransport()
        let (store, read, directory) = try await Self.loaded(transport)
        await transport.scriptChangesReads([.success(read)])
        await transport.scriptUntrackedDirectoryListings([.success(try Self.listing())])
        let gate = ScriptedTransportCallGate()
        await transport.gateNextUntrackedDirectoryListing(using: gate)

        let expanding = Task { await store.toggleDirectory(directory) }
        await gate.waitForEntry()
        #expect(store.untrackedDirectories.expansion(for: directory.path) == .loading)

        await store.refresh()
        #expect(store.untrackedDirectories.expansion(for: directory.path) == nil)

        await gate.open()
        await expanding.value
        #expect(store.untrackedDirectories.expansion(for: directory.path) == nil)
        #expect(await transport.untrackedDirectoryRequests.count == 1)
    }

    @Test func collapsingWhileAListingIsInFlightDropsTheLateResult() async throws {
        let transport = ScriptedTransport()
        let (store, _, directory) = try await Self.loaded(transport)
        await transport.scriptUntrackedDirectoryListings([.success(try Self.listing())])
        let gate = ScriptedTransportCallGate()
        await transport.gateNextUntrackedDirectoryListing(using: gate)

        let expanding = Task { await store.toggleDirectory(directory) }
        await gate.waitForEntry()
        await store.toggleDirectory(directory)
        #expect(store.untrackedDirectories.expansion(for: directory.path) == nil)

        await gate.open()
        await expanding.value
        #expect(store.untrackedDirectories.expansion(for: directory.path) == nil)
    }

    /// A is expanded and B is waiting on its listing. Collapsing A must not
    /// leave B on loading after B's listing lands.
    @Test func collapsingOneDirectoryLeavesAnothersInFlightListing() async throws {
        let transport = ScriptedTransport()
        let (store, read, directory) = try await Self.loaded(transport)
        let listing = try Self.listing()
        let other = ChangedFile(
            path: Data("other/".utf8), originalPath: nil, kind: .untracked, staging: nil)
        let kept = UntrackedDirectoryListing(
            directory: other.path,
            entries: [
                ChangedFile(
                    path: Data("other/a.txt".utf8), originalPath: nil, kind: .untracked,
                    staging: nil)
            ],
            total: 1,
            isTruncated: false,
            isSeparateRepository: false,
            limitNotice: nil)
        await transport.scriptUntrackedDirectoryListings([
            .success(listing),
            .success(kept),
        ])
        await store.toggleDirectory(directory)
        #expect(store.untrackedDirectories.expansion(for: directory.path) == .loaded(listing))

        let gate = ScriptedTransportCallGate()
        await transport.gateNextUntrackedDirectoryListing(using: gate)
        let expanding = Task { await store.toggleDirectory(other) }
        await gate.waitForEntry()
        #expect(store.untrackedDirectories.expansion(for: other.path) == .loading)

        await store.toggleDirectory(directory)
        #expect(store.untrackedDirectories.expansion(for: directory.path) == nil)
        #expect(store.untrackedDirectories.expansion(for: other.path) == .loading)

        await gate.open()
        await expanding.value
        #expect(store.untrackedDirectories.expansion(for: other.path) == .loaded(kept))
        #expect(store.untrackedDirectories.expansion(for: directory.path) == nil)
        #expect(store.phase == .loaded(read.changes))
        #expect(await transport.untrackedDirectoryRequests.count == 2)
    }

    /// Collapsing and opening the same directory again drops the listing that
    /// was already in flight, then keeps the new one.
    @Test func reopeningADirectoryDropsTheListingThatWasCollapsed() async throws {
        let transport = ScriptedTransport()
        let (store, _, directory) = try await Self.loaded(transport)
        let stale = try Self.listing()
        let fresh = UntrackedDirectoryListing(
            directory: directory.path,
            entries: [],
            total: 0,
            isTruncated: false,
            isSeparateRepository: false,
            limitNotice: nil)
        await transport.scriptUntrackedDirectoryListings([
            .success(stale),
            .success(fresh),
        ])
        let firstGate = ScriptedTransportCallGate()
        await transport.gateNextUntrackedDirectoryListing(using: firstGate)
        let first = Task { await store.toggleDirectory(directory) }
        await firstGate.waitForEntry()

        await store.toggleDirectory(directory)
        #expect(store.untrackedDirectories.expansion(for: directory.path) == nil)

        let secondGate = ScriptedTransportCallGate()
        await transport.gateNextUntrackedDirectoryListing(using: secondGate)
        let second = Task { await store.toggleDirectory(directory) }
        await secondGate.waitForEntry()
        #expect(store.untrackedDirectories.expansion(for: directory.path) == .loading)

        await firstGate.open()
        await first.value
        #expect(store.untrackedDirectories.expansion(for: directory.path) == .loading)

        await secondGate.open()
        await second.value
        #expect(store.untrackedDirectories.expansion(for: directory.path) == .loaded(fresh))
        #expect(await transport.untrackedDirectoryRequests.count == 2)
    }

    @Test func aFailedListingStaysOnThatDirectoryAndTheNextTapReadsAgain() async throws {
        let transport = ScriptedTransport()
        let (store, read, directory) = try await Self.loaded(transport)
        let listing = try Self.listing()
        await transport.scriptUntrackedDirectoryListings([
            .failure(ChangesReadError.gitFailed("fatal: cannot change to '/home/dev/src/app'")),
            .success(listing),
        ])

        await store.toggleDirectory(directory)
        #expect(
            store.untrackedDirectories.expansion(for: directory.path)
                == .failed("fatal: cannot change to '/home/dev/src/app'"))
        #expect(store.phase == .loaded(read.changes))
        #expect(await transport.untrackedDirectoryRequests.count == 1)

        await store.toggleDirectory(directory)
        #expect(store.untrackedDirectories.expansion(for: directory.path) == nil)
        #expect(await transport.untrackedDirectoryRequests.count == 1)

        await store.toggleDirectory(directory)
        #expect(store.untrackedDirectories.expansion(for: directory.path) == .loaded(listing))
        #expect(await transport.untrackedDirectoryRequests.count == 2)
    }

    @Test func aCancelledListingLeavesTheDirectoryCollapsed() async throws {
        let transport = ScriptedTransport()
        let (store, read, directory) = try await Self.loaded(transport)
        await transport.scriptUntrackedDirectoryListings([.failure(TransportError.cancelled)])

        await store.toggleDirectory(directory)

        #expect(store.untrackedDirectories.expansion(for: directory.path) == nil)
        #expect(store.phase == .loaded(read.changes))
        #expect(await transport.untrackedDirectoryRequests.count == 1)
    }

    private static func listing() throws -> UntrackedDirectoryListing {
        try GitProbe.parseUntrackedDirectory(
            stdout: GitProbeRecordings.untrackedListing.stdout,
            stderr: GitProbeRecordings.untrackedListing.stderr,
            nonce: GitProbeRecordings.nonce,
            directory: Data("newdir/".utf8))
    }

    private static func loaded(
        _ transport: ScriptedTransport
    ) async throws -> (ChangesStore, CheckoutChangesRead, ChangedFile) {
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        await transport.scriptChangesReads([.success(read)])
        let store = ChangesStore(
            directory: { "/home/dev/src/app" },
            read: { request in try await transport.readChanges(request) },
            listUntrackedDirectory: { request in
                try await transport.listUntrackedDirectory(request)
            })
        await store.appear()
        let directory = try #require(read.changes.files.first { $0.isUntrackedDirectory })
        return (store, read, directory)
    }
}

/// Tapping the directory row in the list.
@MainActor
@Suite("Changes untracked directory rows", .timeLimit(.minutes(1)))
struct ChangesUntrackedDirectoryViewTests {
    @Test func tappingTheRowListsItsFilesAndTappingAgainCollapsesThem() async throws {
        let transport = ScriptedTransport()
        let (read, directory) = try Self.document()
        let listing = Self.children
        await transport.scriptChangesReads([.success(read)])
        await transport.scriptUntrackedDirectoryListings([.success(listing)])
        let (controller, window) = try await Self.host(transport)
        defer { window.isHidden = true }

        let ready = try await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains("newdir/, untracked")
        }
        try #require(ready)
        #expect(Self.value(of: "newdir/, untracked", in: controller.view) == "Collapsed")

        let expanded = try await ChangesViewTests.eventually {
            ChangesViewTests.activate("newdir/, untracked", in: controller.view)
        }
        try #require(expanded)
        var labels = Set<String>()
        let showed = try await ChangesViewTests.eventually {
            labels = ChangesViewTests.labels(in: controller)
            return labels.contains("newdir/a.txt, untracked")
                && labels.contains("newdir/inner/, untracked")
        }
        try #require(showed, "children missing: \(labels.sorted())")
        #expect(Self.value(of: "newdir/, untracked", in: controller.view) == "Expanded")
        #expect(await transport.untrackedDirectoryRequests.count == 1)

        _ = ChangesViewTests.activate("newdir/inner/, untracked", in: controller.view)
        #expect(await transport.untrackedDirectoryRequests.count == 1)
        #expect(!ChangesViewTests.labels(in: controller).contains("Listing newdir/inner/"))

        let collapsed = try await ChangesViewTests.eventually {
            ChangesViewTests.activate("newdir/, untracked", in: controller.view)
        }
        try #require(collapsed)
        let hid = try await ChangesViewTests.eventually {
            !ChangesViewTests.labels(in: controller).contains("newdir/a.txt, untracked")
        }
        #expect(hid)
        #expect(Self.value(of: "newdir/, untracked", in: controller.view) == "Collapsed")
        #expect(await transport.untrackedDirectoryRequests.count == 1)
    }

    @Test func aCutListingShowsItsTotal() async throws {
        let transport = ScriptedTransport()
        let (read, _) = try Self.document()
        let notice = "Showing \(1.formatted()) of \(4.formatted()) files."
        var listing = Self.children
        listing = UntrackedDirectoryListing(
            directory: listing.directory,
            entries: Array(listing.entries.prefix(1)),
            total: 4,
            isTruncated: false,
            isSeparateRepository: false,
            limitNotice: notice)
        await transport.scriptChangesReads([.success(read)])
        await transport.scriptUntrackedDirectoryListings([.success(listing)])
        let (controller, window) = try await Self.host(transport)
        defer { window.isHidden = true }
        try #require(
            await ChangesViewTests.eventually {
                ChangesViewTests.activate("newdir/, untracked", in: controller.view)
            })
        var labels = Set<String>()
        let showed = try await ChangesViewTests.eventually {
            labels = ChangesViewTests.labels(in: controller)
            return labels.contains(notice) && labels.contains("newdir/a.txt, untracked")
        }
        #expect(showed, "notice missing: \(labels.sorted())")
        #expect(!labels.contains("newdir/inner/, untracked"))
    }

    @Test func aSeparateRepositoryShowsItsNote() async throws {
        let transport = ScriptedTransport()
        let (read, directory) = try Self.document()
        let listing = UntrackedDirectoryListing(
            directory: directory.path,
            entries: [],
            total: 0,
            isTruncated: false,
            isSeparateRepository: true,
            limitNotice: nil)
        let note = try #require(listing.repositoryNotice)
        await transport.scriptChangesReads([.success(read)])
        await transport.scriptUntrackedDirectoryListings([.success(listing)])
        let (controller, window) = try await Self.host(transport)
        defer { window.isHidden = true }
        try #require(
            await ChangesViewTests.eventually {
                ChangesViewTests.activate("newdir/, untracked", in: controller.view)
            })
        var labels = Set<String>()
        let showed = try await ChangesViewTests.eventually {
            labels = ChangesViewTests.labels(in: controller)
            return labels.contains(note)
        }
        #expect(showed, "note missing: \(labels.sorted())")
        #expect(note == "This directory is a separate Git repository.")
        #expect(!labels.contains("newdir/a.txt, untracked"))
    }

    @Test func theRowShowsThatItIsListingUntilTheFilesArrive() async throws {
        let transport = ScriptedTransport()
        let (read, _) = try Self.document()
        await transport.scriptChangesReads([.success(read)])
        await transport.scriptUntrackedDirectoryListings([.success(Self.children)])
        let gate = ScriptedTransportCallGate()
        await transport.gateNextUntrackedDirectoryListing(using: gate)
        let (controller, window) = try await Self.host(transport)
        defer { window.isHidden = true }
        try #require(
            await ChangesViewTests.eventually {
                ChangesViewTests.labels(in: controller).contains("newdir/, untracked")
            })

        try #require(
            await ChangesViewTests.eventually {
                ChangesViewTests.activate("newdir/, untracked", in: controller.view)
            })
        let listing = try await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains("Listing newdir/")
        }
        #expect(listing)
        #expect(Self.value(of: "newdir/, untracked", in: controller.view) == "Expanded")

        await gate.open()
        let showed = try await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains("newdir/a.txt, untracked")
        }
        #expect(showed)
    }

    private static var children: UntrackedDirectoryListing {
        UntrackedDirectoryListing(
            directory: Data("newdir/".utf8),
            entries: [
                ChangedFile(
                    path: Data("newdir/a.txt".utf8), originalPath: nil, kind: .untracked,
                    staging: nil),
                ChangedFile(
                    path: Data("newdir/inner/".utf8), originalPath: nil, kind: .untracked,
                    staging: nil),
            ],
            total: 2,
            isTruncated: false,
            isSeparateRepository: false,
            limitNotice: nil)
    }

    private static func document() throws -> (CheckoutChangesRead, ChangedFile) {
        let full = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        let directory = try #require(full.changes.files.first { $0.isUntrackedDirectory })
        let read = CheckoutChangesRead(
            changes: CheckoutChanges(
                checkout: full.changes.checkout, head: full.changes.head, files: [directory]),
            directoryPrefix: Data())
        return (read, directory)
    }

    private static func host(
        _ transport: ScriptedTransport
    ) async throws -> (UIHostingController<AnyView>, UIWindow) {
        let store = ChangesStore(
            directory: { "/home/dev/src/app" },
            read: { request in try await transport.readChanges(request) },
            listUntrackedDirectory: { request in
                try await transport.listUntrackedDirectory(request)
            })
        let controller = UIHostingController(
            rootView: AnyView(NavigationStack { ChangesView(store: store) {} }))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874),
            rootViewController: controller)
        return (controller, window)
    }

    private static func value(of label: String, in root: UIView) -> String? {
        var visited = Set<ObjectIdentifier>()
        func visit(_ node: NSObject) -> String? {
            guard visited.insert(ObjectIdentifier(node)).inserted,
                !node.accessibilityElementsHidden
            else { return nil }
            if node.accessibilityLabel == label,
                let value = node.accessibilityValue, !value.isEmpty
            {
                return value
            }
            for object in node.accessibilityElements ?? [] {
                if let object = object as? NSObject, let value = visit(object) { return value }
            }
            let count = node.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<count {
                    if let object = node.accessibilityElement(at: index) as? NSObject,
                        let value = visit(object)
                    {
                        return value
                    }
                }
            }
            if let view = node as? UIView {
                for subview in view.subviews {
                    if let value = visit(subview) { return value }
                }
            }
            return nil
        }
        root.layoutIfNeeded()
        return visit(root.window ?? root)
    }
}
