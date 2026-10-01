import Foundation
import Testing

@testable import Heeler

@MainActor
@Suite("Diff layout settings")
struct DiffLayoutSettingsTests {
    private func makeDefaults() throws -> (UserDefaults, cleanup: () -> Void) {
        let suiteName = "hm-diff-layout-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }

    @Test func defaultsToSideBySide() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }

        let settings = DiffLayoutSettings(defaults: defaults, offersSideBySide: true)

        #expect(settings.layout == .sideBySide)
        #expect(settings.offersSideBySide)
        #expect(!DiffLayoutSettings(defaults: defaults, offersSideBySide: false).offersSideBySide)
    }

    @Test func selectionPersistsAcrossInstances() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let settings = DiffLayoutSettings(defaults: defaults, offersSideBySide: true)

        settings.select(.unified)

        #expect(defaults.string(forKey: "changes.diff-layout") == "unified")
        #expect(DiffLayoutSettings(defaults: defaults, offersSideBySide: true).layout == .unified)
        #expect(DiffLayoutSettings(defaults: defaults, offersSideBySide: false).layout == .unified)
    }

    @Test func unknownStoredValueFallsBackToSideBySide() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        defaults.set("columns", forKey: "changes.diff-layout")

        #expect(DiffLayoutSettings(defaults: defaults, offersSideBySide: true).layout == .sideBySide)
    }

    @Test func segmentsAreSideBySideThenUnified() {
        #expect(DiffLayout.allCases == [.sideBySide, .unified])
        #expect(DiffLayout.allCases.map(\.title) == ["Side by Side", "Unified"])
    }
}
