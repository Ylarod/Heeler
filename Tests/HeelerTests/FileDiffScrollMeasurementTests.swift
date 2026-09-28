import Foundation
import QuartzCore
import SwiftUI
import Testing
import UIKit

@testable import Heeler

/// A simulator proxy, not an on-device Instruments result. The window hosts
/// the real file presentation, including its lazy rows, gutters and rotors.
@MainActor
@Suite("File diff scroll measurement", .serialized, .timeLimit(.minutes(1)))
struct FileDiffScrollMeasurementTests {
    @Test func measuresOpeningAndScrollingFiveThousandWrappedLines() async throws {
        let lineCount = 5_000
        var openMilliseconds = -1.0
        var sampler: DiffScrollSampler?
        // Report even if window setup, a bounded wait or cancellation fails.
        defer {
            sampler?.stop()
            print(DiffScrollSampler.report(
                lineCount: lineCount, openMilliseconds: openMilliseconds, sampler: sampler))
        }
        let patch = Self.patch(lineCount: lineCount)
        let store = FileDiffStore(
            file: FileDiffViewTests.file,
            checkout: FileDiffViewTests.changesRead().changes.checkout,
            read: { _ in patch })
        let started = CACurrentMediaTime()
        let controller = UIHostingController(rootView: FileDiffView(store: store))
        let window = try await makeTestWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874),
            rootViewController: controller)
        defer { window.isHidden = true }

        // Include loading the store and laying out the first real row in the
        // open time; a nonzero contentSize alone could still be an estimate.
        let opened = try await Self.waitUntil(timeout: .seconds(10)) {
            controller.view.layoutIfNeeded()
            return Self.lineIsVisible(0, in: controller.view)
        }
        try #require(opened, "the first diff line did not lay out in the viewport within 10 seconds")
        openMilliseconds = (CACurrentMediaTime() - started) * 1_000
        let scroll = try #require(
            Self.scrollView(in: controller.view), "the laid-out diff has no underlying scroll view")
        let activeSampler = DiffScrollSampler(
            scroll: scroll, root: controller.view, lastLine: lineCount - 1,
            maximumFramesPerSecond: window.screen.maximumFramesPerSecond)
        sampler = activeSampler
        activeSampler.start()
        let completed = try await Self.waitUntil(timeout: .seconds(15)) {
            activeSampler.finished
        }
        activeSampler.stop()

        // Timing is data for the checker. Only real end-to-end navigation is
        // asserted; the deadlines bound missing layout or display-link work.
        #expect(completed, "scrolling did not complete within 15 seconds; the display link or endpoint layout stalled")
        #expect(activeSampler.reachedBottom, "the last diff line never entered the scroll viewport")
        #expect(activeSampler.returnedToTop, "the first diff line never returned to the scroll viewport")
    }

    private static func waitUntil(timeout: Duration, _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private static func patch(lineCount: Int) -> FilePatch {
        var oldNumber = 0
        var newNumber = 0
        let lines = (0..<lineCount).map { index in
            let kind: DiffLine.Kind = index % 3 == 0 ? .added : (index % 3 == 1 ? .removed : .context)
            if kind != .added { oldNumber += 1 }
            if kind != .removed { newNumber += 1 }
            // Even a wide iPad wraps these lines. Every seventh line is
            // longer, exercising corrections to LazyVStack's height estimate.
            let text = "Row \(index): " + String(
                repeating: "wrapped content with spaces and indented continuation ",
                count: index % 7 == 0 ? 12 : 5)
            return DiffLine(
                id: index, kind: kind,
                oldNumber: kind == .added ? nil : oldNumber,
                newNumber: kind == .removed ? nil : newNumber,
                text: text)
        }
        return FilePatch(
            files: [
                DiffFile(
                    id: 0, oldPath: "large.txt", newPath: "large.txt", summary: nil,
                    isBinary: false,
                    hunks: [
                        DiffHunk(
                            id: 0, oldStart: 1, oldCount: oldNumber,
                            newStart: 1, newCount: newNumber,
                            section: "synthetic wrapped document", lines: lines)
                    ])
            ], isTruncated: false)
    }

    private static func scrollView(in root: UIView) -> UIScrollView? {
        if let scroll = root as? UIScrollView { return scroll }
        for child in root.subviews {
            if let found = scrollView(in: child) { return found }
        }
        return nil
    }

    fileprivate static func lineIsVisible(_ id: Int, in root: UIView) -> Bool {
        let identifier = "file-diff-line-\(id)"
        var visited = Set<ObjectIdentifier>()
        let viewportView = scrollView(in: root) ?? root
        let viewport = UIAccessibility.convertToScreenCoordinates(viewportView.bounds, in: viewportView)
        let identifierGetter = #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)
        func visit(_ object: NSObject) -> Bool {
            guard visited.insert(ObjectIdentifier(object)).inserted,
                !object.accessibilityElementsHidden
            else { return false }
            // SwiftUI's accessibility nodes expose the getter without
            // declaring conformance to UIAccessibilityIdentification.
            if object.responds(to: identifierGetter),
                object.value(forKey: "accessibilityIdentifier") as? String == identifier
            {
                let frame = object.accessibilityFrame
                return !frame.isEmpty && viewport.intersects(frame)
            }
            for child in object.accessibilityElements ?? [] {
                if let child = child as? NSObject, visit(child) { return true }
            }
            let count = object.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject,
                        visit(child)
                    {
                        return true
                    }
                }
            }
            if let view = object as? UIView {
                for child in view.subviews where visit(child) { return true }
            }
            return false
        }
        return visit(root)
    }
}

@MainActor
private final class DiffScrollSampler: NSObject {
    private let scroll: UIScrollView
    private let root: UIView
    private let lastLine: Int
    private let maximumFramesPerSecond: Int
    private var displayLink: CADisplayLink?
    private var firstTimestamp: CFTimeInterval?
    private var previousTimestamp: CFTimeInterval?
    private var returnStarted: CFTimeInterval?
    private var returnOffset: CGFloat = 0
    private var intervals: [CFTimeInterval] = []
    private var returnSampleIndex: Int?
    private var budget: CFTimeInterval
    private var duration: CFTimeInterval = 0
    private(set) var finished = false
    private(set) var reachedBottom = false
    private(set) var returnedToTop = false

    init(scroll: UIScrollView, root: UIView, lastLine: Int, maximumFramesPerSecond: Int) {
        self.scroll = scroll
        self.root = root
        self.lastLine = lastLine
        self.maximumFramesPerSecond = maximumFramesPerSecond
        budget = 1 / Double(max(1, maximumFramesPerSecond))
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.preferredFramesPerSecond = maximumFramesPerSecond
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        if firstTimestamp == nil {
            firstTimestamp = link.timestamp
            let scheduled = link.targetTimestamp - link.timestamp
            if scheduled > 0 { budget = scheduled }
        }
        if let previousTimestamp { intervals.append(link.timestamp - previousTimestamp) }
        previousTimestamp = link.timestamp
        let elapsed = link.timestamp - (firstTimestamp ?? link.timestamp)
        duration = elapsed
        let top = -scroll.adjustedContentInset.top

        if let returnStarted {
            let progress = min(1, (link.timestamp - returnStarted) / 2)
            scroll.setContentOffset(
                CGPoint(x: 0, y: returnOffset + (top - returnOffset) * progress), animated: false)
            root.layoutIfNeeded()
            if progress == 1 {
                // Accessibility traversal is harness work. Do not sample
                // the following interval, which includes that traversal.
                previousTimestamp = nil
                returnedToTop = FileDiffScrollMeasurementTests.lineIsVisible(0, in: root)
                if returnedToTop {
                    finished = true
                    stop()
                }
            }
        } else {
            // Recompute every frame: a lazy stack refines its estimated
            // content height as wrapped rows enter the viewport.
            let bottom = max(
                top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let progress = min(1, elapsed / 2)
            scroll.setContentOffset(CGPoint(x: 0, y: top + (bottom - top) * progress), animated: false)
            root.layoutIfNeeded()
            if progress == 1 {
                previousTimestamp = nil
                reachedBottom = FileDiffScrollMeasurementTests.lineIsVisible(lastLine, in: root)
                if reachedBottom {
                    returnStarted = link.timestamp
                    returnOffset = scroll.contentOffset.y
                    returnSampleIndex = intervals.count
                }
            }
        }
    }

    static func report(lineCount: Int, openMilliseconds: Double, sampler: DiffScrollSampler?) -> String {
        let intervals = sampler?.intervals ?? []
        let budget = sampler?.budget ?? 0
        let sorted = intervals.sorted()
        func percentile(_ fraction: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            return sorted[Int(Double(sorted.count - 1) * fraction)] * 1_000
        }
        var longFrames = 0
        var run = 0
        var longestRun = 0
        for (index, interval) in intervals.enumerated() {
            // The endpoint check separates the two sampled scrolling legs.
            if index == sampler?.returnSampleIndex { run = 0 }
            if interval > 2 * budget {
                longFrames += 1
                run += 1
                longestRun = max(longestRun, run)
            } else {
                run = 0
            }
        }
        return String(
            format: "DIFF-SCROLL-MEASUREMENT lines=%d open_ms=%.2f frames=%d scroll_s=%.3f p50_ms=%.2f p95_ms=%.2f max_ms=%.2f budget_ms=%.2f frames_over_2x=%d longest_run_over_2x=%d reached_bottom=%d returned_to_top=%d",
            lineCount, openMilliseconds, intervals.count, sampler?.duration ?? 0,
            percentile(0.5), percentile(0.95), (sorted.last ?? 0) * 1_000,
            budget * 1_000, longFrames, longestRun,
            sampler?.reachedBottom == true ? 1 : 0, sampler?.returnedToTop == true ? 1 : 0)
    }
}
