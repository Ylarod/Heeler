import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Heeler

@MainActor
@Suite("Changes failure view", .timeLimit(.minutes(1)))
struct ChangesFailureViewTests {
    @Test func eachFailureExplainsWhatHappened() async throws {
        let cases: [(any Error, String, String)] = [
            (ChangesReadError.gitMissing, "Git Not Found", "Install git"),
            (ChangesReadError.gitTooOld("2.16.6"), "Git Version Too Old", "2.17 or later"),
            (ChangesReadError.notOwnedByAccount, "Checkout Ownership Protected", "ownership protection"),
            (ChangesReadError.directoryMissing, "Directory No Longer Exists", "no longer exists"),
            (ChangesReadError.incomplete, "Incomplete Changes", "reply ended early"),
            (TransportError.gitTimedOut, "Reading Changes Timed Out", "Pull to try again"),
            (ChangesReadError.gitFailed("fatal: bad config line 1"), "Couldn't Read Changes", "fatal: bad config line 1"),
        ]
        for (error, title, explanation) in cases {
            let transport = ScriptedTransport()
            await transport.scriptChangesReads([.failure(error)])
            let (controller, window, _) = try await ChangesViewTests.host(transport: transport)
            defer { window.isHidden = true }
            var labels = Set<String>()
            let shown = try await ChangesViewTests.eventually {
                labels = ChangesViewTests.labels(in: controller)
                return labels.contains(title) && labels.contains { $0.contains(explanation) }
                    && labels.contains("Try Again")
            }
            #expect(shown, "Missing failure state: \(labels.sorted())")
        }
    }

    @Test func aTimedOutRefreshKeepsTheListAndExplainsTheEarlierRead() async throws {
        let transport = ScriptedTransport()
        let read = try ChangesStoreTests.read(GitProbeRecordings.clean)
        await transport.scriptChangesReads([.success(read), .failure(TransportError.gitTimedOut)])
        let store = ChangesStore(directory: { "/home/dev/src/app" }) { request in
            try await transport.readChanges(request)
        }
        await store.appear()
        await store.refresh()
        let controller = UIHostingController(rootView: AnyView(
            NavigationStack { ChangesView(store: store) {} }))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874), rootViewController: controller)
        defer { window.isHidden = true }
        var labels = Set<String>()
        let shown = try await ChangesViewTests.eventually {
            labels = ChangesViewTests.labels(in: controller)
            return labels.contains("No uncommitted changes")
                && labels.contains { $0.contains("Showing the earlier read") }
        }
        #expect(shown, "Missing kept content or notice: \(labels.sorted())")
        #expect(!labels.contains("Couldn't Read Changes"))
        #expect(await transport.changesReadRequests.count == 2)
    }

    @Test func tryAgainRecoversFromAnIncompleteRead() async throws {
        let transport = ScriptedTransport()
        await transport.scriptChangesReads([
            .failure(ChangesReadError.incomplete),
            .success(try ChangesStoreTests.read(GitProbeRecordings.clean)),
        ])
        let (controller, window, _) = try await ChangesViewTests.host(transport: transport)
        defer { window.isHidden = true }
        try #require(await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains("Incomplete Changes")
        })
        try #require(await ChangesViewTests.eventually {
            ChangesViewTests.activate("Try Again", in: controller.view)
        })
        let recovered = try await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains("No uncommitted changes")
        }
        #expect(recovered)
        #expect(await transport.changesReadRequests.count == 2)
    }

    @Test func aTruncatedStatusShowsALowerBoundInsteadOfClean() async throws {
        let (controller, window, _) = try await ChangesViewTests.host(
            GitProbeRecordings.failureStatusWithFiles(0, truncated: true))
        defer { window.isHidden = true }
        var labels = Set<String>()
        let shown = try await ChangesViewTests.eventually {
            labels = ChangesViewTests.labels(in: controller)
            return labels.contains("Showing 0 of more than 0 changed files.")
        }
        #expect(shown, "Missing partial notice: \(labels.sorted())")
        #expect(!labels.contains("No uncommitted changes"))
    }

    @Test func truncatedMetadataIsMarkedEvenWhenStatusIsComplete() async throws {
        let recording = GitProbeRecordings.failureReplacingSection(
            "head", in: GitProbeRecordings.clean,
            body: Data(repeating: 0x78, count: GitProbe.Cap.head + 1))
        let (controller, window, _) = try await ChangesViewTests.host(recording)
        defer { window.isHidden = true }
        let shown = try await ChangesViewTests.eventually {
            ChangesViewTests.labels(in: controller).contains(
                "Some Changes details were truncated.")
        }
        #expect(shown)
    }
}
