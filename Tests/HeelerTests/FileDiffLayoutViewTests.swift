import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Heeler

/// Hosted stand-ins for the iPad detail column. Settings are injected, so
/// these tests never read `UIDevice` or `UserDefaults.standard`.
@MainActor
@Suite("File diff layout", .serialized, .timeLimit(.minutes(1)))
struct FileDiffLayoutViewTests {
    private static let pairedLabel = "Removed, line 8: old value. Added, line 8: new value"
    private static let removedLabel = "Removed, line 8: old value"
    private static let addedLabel = "Added, line 8: new value"
    private static let contextLabel = "Unchanged, line 9: closing line. No newline at end of file."

    @Test func wideDetailReadsAPairAsRemovedThenAddedAndEnablesTheToggle() async throws {
        let (settings, _, cleanup) = try makeSettings(offersSideBySide: true)
        defer { cleanup() }
        let (controller, window) = try await host(
            patch: Self.pairedPatch(), settings: settings,
            size: CGSize(width: 1376, height: 1032))
        defer { window.isHidden = true }

        var labels = Set<String>()
        try #require(await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            labels = ChangesViewTests.labels(in: controller)
            return labels.contains(Self.pairedLabel)
        })
        try #require(abs(controller.view.bounds.width - 1376) < 1)
        #expect(labels.contains(Self.contextLabel))
        #expect(!labels.contains(Self.removedLabel))
        #expect(!labels.contains(Self.addedLabel))
        let control = Self.layoutControl(in: controller.view)
        #expect(labels.contains("Side by Side"))
        #expect(control.present)
        #expect(!control.disabled)
        #expect(settings.layout == .sideBySide)
    }

    @Test func narrowDetailStaysUnifiedAndDisablesTheToggle() async throws {
        let (settings, _, cleanup) = try makeSettings(offersSideBySide: true)
        defer { cleanup() }
        let (controller, window) = try await host(
            patch: Self.pairedPatch(), settings: settings,
            size: CGSize(width: 996, height: 1032))
        defer { window.isHidden = true }

        var labels = Set<String>()
        try #require(await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            labels = ChangesViewTests.labels(in: controller)
            return labels.contains(Self.removedLabel) && labels.contains(Self.addedLabel)
        })
        try #require(abs(controller.view.bounds.width - 996) < 1)
        #expect(!labels.contains(Self.pairedLabel))
        #expect(labels.contains(Self.contextLabel))
        let control = Self.layoutControl(in: controller.view)
        #expect(control.present)
        #expect(control.disabled)
        #expect(settings.layout == .sideBySide)
    }

    @Test func xxxLargeFallsBackToUnifiedAtTheWideWidth() async throws {
        let (settings, _, cleanup) = try makeSettings(offersSideBySide: true)
        defer { cleanup() }
        let (controller, window) = try await host(
            patch: Self.pairedPatch(), settings: settings,
            size: CGSize(width: 1376, height: 1032), dynamicType: .xxxLarge)
        defer { window.isHidden = true }

        var labels = Set<String>()
        try #require(await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            labels = ChangesViewTests.labels(in: controller)
            return labels.contains(Self.removedLabel) && labels.contains(Self.addedLabel)
        })
        #expect(!labels.contains(Self.pairedLabel))
        let control = Self.layoutControl(in: controller.view)
        #expect(control.present)
        #expect(control.disabled)
    }

    @Test func anIPhoneShowsNoToggle() async throws {
        let (settings, _, cleanup) = try makeSettings(offersSideBySide: false)
        defer { cleanup() }
        let (controller, window) = try await host(
            patch: Self.pairedPatch(), settings: settings,
            size: CGSize(width: 1376, height: 1032))
        defer { window.isHidden = true }

        var labels = Set<String>()
        try #require(await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            labels = ChangesViewTests.labels(in: controller)
            return labels.contains(Self.removedLabel) && labels.contains(Self.addedLabel)
        })
        #expect(!labels.contains(Self.pairedLabel))
        #expect(!labels.contains("Side by Side"))
        #expect(!labels.contains("Unified"))
        #expect(!labels.contains("Diff Layout"))
        #expect(!Self.layoutControl(in: controller.view).present)
    }

    @Test func choosingUnifiedPersistsForTheNextPresentation() async throws {
        let (settings, defaults, cleanup) = try makeSettings(offersSideBySide: true)
        defer { cleanup() }
        let (controller, window) = try await host(
            patch: Self.pairedPatch(), settings: settings,
            size: CGSize(width: 1376, height: 1032))
        defer { window.isHidden = true }

        try #require(await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            return ChangesViewTests.labels(in: controller).contains(Self.pairedLabel)
                && Self.chooseUnified(in: controller.view)
        })
        try #require(await ChangesViewTests.eventually {
            let labels = ChangesViewTests.labels(in: controller)
            return labels.contains(Self.removedLabel)
                && labels.contains(Self.addedLabel)
                && !labels.contains(Self.pairedLabel)
        })
        #expect(settings.layout == .unified)
        #expect(DiffLayoutSettings(defaults: defaults, offersSideBySide: true).layout == .unified)
        #expect(DiffLayoutSettings(defaults: defaults, offersSideBySide: false).layout == .unified)
    }

    @Test func aLayoutSwitchKeepsTheTopmostLine() async throws {
        let (settings, _, cleanup) = try makeSettings(offersSideBySide: true)
        defer { cleanup() }
        let (controller, window) = try await host(
            patch: Self.longContextPatch(), settings: settings,
            size: CGSize(width: 1376, height: 1032))
        defer { window.isHidden = true }

        // Stay in the middle of the document. A line near the end cannot sit
        // at the top once a shorter layout clamps the scroll view.
        try #require(await ChangesViewTests.eventually(timeout: .seconds(8)) {
            controller.view.layoutIfNeeded()
            guard let scroll = Self.diffScrollView(in: controller.view) else { return false }
            return scroll.contentSize.height > scroll.bounds.height + 400
        })
        var captured: Int?
        try #require(await ChangesViewTests.eventually(timeout: .seconds(8)) {
            controller.view.layoutIfNeeded()
            guard let scroll = Self.diffScrollView(in: controller.view) else { return false }
            let top = Self.topLineID(in: controller.view, viewport: scroll)
            if let top, top >= 40 {
                captured = top
                return true
            }
            let travel = max(0, scroll.contentSize.height - scroll.bounds.height)
            let y = min(CGFloat(3200), travel * 0.35)
            if abs(scroll.contentOffset.y - y) > 1 {
                scroll.setContentOffset(CGPoint(x: 0, y: y), animated: false)
                scroll.delegate?.scrollViewDidScroll?(scroll)
            }
            return false
        })
        let expected = try #require(captured)

        settings.select(.unified)
        try await Self.expectTop(expected, in: controller)
        settings.select(.sideBySide)
        try await Self.expectTop(expected, in: controller)
        Self.resize(window, to: CGSize(width: 996, height: 1032))
        try #require(await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            guard let scroll = Self.diffScrollView(in: controller.view) else { return false }
            return Self.topLineID(in: controller.view, viewport: scroll) == expected
                && Self.layoutControl(in: controller.view).disabled
        })
        Self.resize(window, to: CGSize(width: 1376, height: 1032))
        try #require(await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            guard let scroll = Self.diffScrollView(in: controller.view) else { return false }
            let control = Self.layoutControl(in: controller.view)
            return Self.topLineID(in: controller.view, viewport: scroll) == expected
                && control.present && !control.disabled
        })
    }

    private func makeSettings(
        offersSideBySide: Bool
    ) throws -> (DiffLayoutSettings, UserDefaults, () -> Void) {
        let name = "hm-diff-layout-view-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = DiffLayoutSettings(defaults: defaults, offersSideBySide: offersSideBySide)
        return (settings, defaults, { defaults.removePersistentDomain(forName: name) })
    }

    private func host(
        patch: FilePatch,
        settings: DiffLayoutSettings,
        size: CGSize,
        dynamicType: DynamicTypeSize = .large
    ) async throws -> (UIHostingController<AnyView>, UIWindow) {
        let store = FileDiffStore(
            file: FileDiffViewTests.file,
            checkout: FileDiffViewTests.changesRead().changes.checkout,
            read: { _ in patch })
        let controller = UIHostingController(
            rootView: AnyView(
                NavigationStack {
                    FileDiffView(store: store)
                }
                .environment(\.diffLayoutSettings, settings)
                .environment(\.dynamicTypeSize, dynamicType)))
        let window = try await makeTestWindow(
            frame: CGRect(origin: .zero, size: size), rootViewController: controller)
        return (controller, window)
    }

    private static func expectTop(_ expected: Int, in controller: UIViewController) async throws {
        try #require(await ChangesViewTests.eventually {
            controller.view.layoutIfNeeded()
            guard let scroll = diffScrollView(in: controller.view) else { return false }
            return topLineID(in: controller.view, viewport: scroll) == expected
        })
    }

    private static func resize(_ window: UIWindow, to size: CGSize) {
        window.frame = CGRect(origin: window.frame.origin, size: size)
        window.rootViewController?.view.frame = window.bounds
        window.layoutIfNeeded()
    }

    private static func pairedPatch() -> FilePatch {
        FilePatch(
            files: [
                DiffFile(
                    id: 0, oldPath: "sample.txt", newPath: "sample.txt", summary: nil,
                    isBinary: false,
                    hunks: [
                        DiffHunk(
                            id: 0, oldStart: 8, oldCount: 2, newStart: 8, newCount: 2,
                            section: "updateValue()",
                            lines: [
                                DiffLine(
                                    id: 0, kind: .removed, oldNumber: 8, newNumber: nil,
                                    text: "old value"),
                                DiffLine(
                                    id: 1, kind: .added, oldNumber: nil, newNumber: 8,
                                    text: "new value"),
                                DiffLine(
                                    id: 2, kind: .context, oldNumber: 9, newNumber: 9,
                                    text: "closing line", missingNewline: true),
                            ])
                    ])
            ], isTruncated: false)
    }

    /// Context rows use the same id in both layouts, and the line is long
    /// enough to wrap in a column but not across the full 1376 pt width.
    private static func longContextPatch(count: Int = 600) -> FilePatch {
        let text = String(repeating: "context ", count: 15)
        let lines = (0..<count).map { index in
            DiffLine(
                id: index, kind: .context, oldNumber: index + 1, newNumber: index + 1,
                text: text)
        }
        return FilePatch(
            files: [
                DiffFile(
                    id: 0, oldPath: "large.txt", newPath: "large.txt", summary: nil,
                    isBinary: false,
                    hunks: [
                        DiffHunk(
                            id: 0, oldStart: 1, oldCount: count, newStart: 1, newCount: count,
                            section: "wrapped context", lines: lines)
                    ])
            ], isTruncated: false)
    }

    private struct LayoutControl {
        var sawIdentifier = false
        var identifierDisabled = false
        var segments = 0
        var disabledSegments = 0

        var present: Bool { sawIdentifier || segments > 0 }
        var disabled: Bool {
            if identifierDisabled { return true }
            return segments > 0 && disabledSegments == segments
        }
    }

    private static func layoutControl(in root: UIView) -> LayoutControl {
        var control = LayoutControl()
        visit(root.window ?? root) { node in
            let label = node.accessibilityLabel
            let identifier = accessibilityIdentifier(of: node)
            if identifier == "diff-layout-picker" || label == "Diff Layout" {
                control.sawIdentifier = true
                if isDisabled(node) { control.identifierDisabled = true }
            }
            if label == "Side by Side" || label == "Unified" {
                control.segments += 1
                if isDisabled(node) { control.disabledSegments += 1 }
            }
        }
        return control
    }

    private static func chooseUnified(in root: UIView) -> Bool {
        if ChangesViewTests.activate("Unified", in: root) { return true }
        var chosen = false
        visit(root.window ?? root) { node in
            guard !chosen, let control = node as? UISegmentedControl else { return }
            for index in 0..<control.numberOfSegments where control.titleForSegment(at: index) == "Unified" {
                control.selectedSegmentIndex = index
                control.sendActions(for: .valueChanged)
                chosen = true
            }
        }
        return chosen
    }

    private static func topLineID(in root: UIView, viewport scroll: UIScrollView) -> Int? {
        let viewport = UIAccessibility.convertToScreenCoordinates(scroll.bounds, in: scroll)
        guard !viewport.isNull, !viewport.isEmpty else { return nil }
        let probe = CGPoint(x: viewport.midX, y: viewport.minY + 4)
        var best: (id: Int, minY: CGFloat)?
        visit(root.window ?? root) { node in
            guard let identifier = accessibilityIdentifier(of: node),
                identifier.hasPrefix("file-diff-line-"),
                let id = Int(identifier.dropFirst("file-diff-line-".count))
            else { return }
            let frame = node.accessibilityFrame
            guard frame.contains(probe) else { return }
            if best == nil || frame.minY < best!.minY {
                best = (id, frame.minY)
            }
        }
        return best?.id
    }

    private static func diffScrollView(in root: UIView) -> UIScrollView? {
        var scrolls: [UIScrollView] = []
        func walk(_ view: UIView) {
            if let scroll = view as? UIScrollView { scrolls.append(scroll) }
            view.subviews.forEach(walk)
        }
        walk(root)
        if let identified = scrolls.first(where: { $0.accessibilityIdentifier == "file-diff-scroll" }) {
            return identified
        }
        return scrolls.max { $0.contentSize.height < $1.contentSize.height }
    }

    private static func isDisabled(_ node: NSObject) -> Bool {
        if node.accessibilityTraits.contains(.notEnabled) { return true }
        if let control = node as? UIControl, !control.isEnabled { return true }
        return false
    }

    private static func accessibilityIdentifier(of node: NSObject) -> String? {
        let getter = #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)
        guard node.responds(to: getter) else { return nil }
        return node.value(forKey: "accessibilityIdentifier") as? String
    }

    private static func visit(_ root: NSObject, _ body: (NSObject) -> Void) {
        if let view = root as? UIView { view.layoutIfNeeded() }
        var visited = Set<ObjectIdentifier>()
        func walk(_ node: NSObject) {
            guard visited.insert(ObjectIdentifier(node)).inserted,
                !node.accessibilityElementsHidden
            else { return }
            body(node)
            for child in node.accessibilityElements ?? [] {
                if let child = child as? NSObject { walk(child) }
            }
            let count = node.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<count {
                    if let child = node.accessibilityElement(at: index) as? NSObject {
                        walk(child)
                    }
                }
            }
            if let view = node as? UIView {
                for child in view.subviews { walk(child) }
            }
        }
        walk(root)
    }
}
