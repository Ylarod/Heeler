import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Heeler

@MainActor
@Suite("Changes freshness", .serialized, .timeLimit(.minutes(1)))
struct ChangesFreshnessTests {
    @Test func readTimeIncludesTheDateOnlyOutsideToday() throws {
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US_POSIX")
        let date = Date(timeIntervalSince1970: 86_400 + 14 * 3_600 + 5 * 60)
        let freshness = ChangesFreshness(readAt: date)
        let today = freshness.text(relativeTo: date, locale: locale, calendar: calendar, timeZone: zone)
        #expect(today.hasPrefix("Possibly incomplete · Read at "))
        #expect(today.contains("2:05"))
        let yesterday = freshness.text(
            relativeTo: date.addingTimeInterval(86_400), locale: locale,
            calendar: calendar, timeZone: zone)
        #expect(yesterday.hasPrefix("Possibly incomplete · Read Jan 2, 1970 at "))
        #expect(yesterday.contains("2:05"))
    }

    @Test func theHostedHeaderIncludesFreshnessInOneCheckoutSummary() async throws {
        let read = try ChangesStoreTests.read(GitProbeRecordings.hostile)
        let (stream, updates) = AsyncStream.makeStream(of: ConsoleStore.AgentStatusUpdate.self)
        updates.yield(.init(status: .working, liveUpdatesAvailable: true))
        let store = ChangesStore(
            directory: { "/app" }, read: { _ in read }, agentStatus: { stream },
            now: { Date(timeIntervalSince1970: 0) })
        let controller = UIHostingController(rootView: NavigationStack {
            ChangesView(store: store, onBack: {})
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        })
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874), rootViewController: controller)
        defer { window.isHidden = true; store.cancel(); updates.finish() }
        var labels = Set<String>()
        for _ in 0..<2_000 {
            labels = ChangesViewTests.labels(in: controller)
            if labels.contains(where: { $0.contains("Possibly incomplete.") }) { break }
            await Task.yield()
        }
        let header = try #require(labels.first { $0.contains("Possibly incomplete.") })
        #expect(header.contains(read.changes.checkout.displayPath))
        #expect(header.contains("Read "))
        #expect(!header.lowercased().contains("agent"))
        #expect(labels.filter { $0.contains("Possibly incomplete") }.count == 1)
    }
}
