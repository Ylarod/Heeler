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
        while !Self.lineIsVisible(0, in: controller.view) {
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        let openMilliseconds = (CACurrentMediaTime() - started) * 1_000
        let scroll = try #require(Self.scrollView(in: controller.view))
        let sampler = DiffScrollSampler(
            scroll: scroll, root: controller.view, lastLine: lineCount - 1,
            maximumFramesPerSecond: window.screen.maximumFramesPerSecond)
        sampler.start()
        defer { sampler.stop() }
        while !sampler.finished {
            try await Task.sleep(for: .milliseconds(10))
        }

        print(sampler.report(lineCount: lineCount, openMilliseconds: openMilliseconds))
        // Timing is data for the checker. Only real end-to-end navigation is
        // an assertion, so a slow simulator does not become a flaky test.
        #expect(sampler.reachedBottom, "the last diff line never entered the viewport")
        #expect(sampler.returnedToTop, "the first diff line never returned to the viewport")
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
        let viewport = root.convert(root.bounds, to: nil)
        func visit(_ object: NSObject) -> Bool {
            guard visited.insert(ObjectIdentifier(object)).inserted,
                !object.accessibilityElementsHidden
            else { return false }
            if (object as? any UIAccessibilityIdentification)?.accessibilityIdentifier == identifier {
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
                returnedToTop = FileDiffScrollMeasurementTests.lineIsVisible(0, in: root)
                if returnedToTop || link.timestamp - returnStarted > 3 {
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
                reachedBottom = FileDiffScrollMeasurementTests.lineIsVisible(lastLine, in: root)
                if reachedBottom || elapsed > 3 {
                    returnStarted = link.timestamp
                    returnOffset = scroll.contentOffset.y
                }
            }
        }
    }

    func report(lineCount: Int, openMilliseconds: Double) -> String {
        let sorted = intervals.sorted()
        func percentile(_ fraction: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            return sorted[Int(Double(sorted.count - 1) * fraction)] * 1_000
        }
        var longFrames = 0
        var run = 0
        var longestRun = 0
        for interval in intervals {
            if interval > 2 * budget {
                longFrames += 1
                run += 1
                longestRun = max(longestRun, run)
            } else {
                run = 0
            }
        }
        return String(
            format: "DIFF-SCROLL-MEASUREMENT lines=%d open_ms=%.2f frames=%d scroll_s=%.3f p50_ms=%.2f p95_ms=%.2f max_ms=%.2f budget_ms=%.2f frames_over_2x=%d longest_run_over_2x=%d",
            lineCount, openMilliseconds, intervals.count, duration,
            percentile(0.5), percentile(0.95), (sorted.last ?? 0) * 1_000,
            budget * 1_000, longFrames, longestRun)
    }
}
