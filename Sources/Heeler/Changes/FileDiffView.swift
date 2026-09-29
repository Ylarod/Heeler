import SwiftUI
import UIKit

/// One file's lazy read. Pulling and retrying belong to this file, not the
/// Checkout's list, and leaving cancels every read owned by the presentation.
struct FileDiffView: View {
    let store: FileDiffStore
    @State private var action: Task<Void, Never>?

    var body: some View {
        ZStack {
            switch store.phase {
            case .loading:
                ProgressView("Reading Diff…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let patch):
                FileDiffDocumentView(patch: patch, refreshError: store.refreshError) {
                    FileDiffFooter(store: store) {
                        action = Task { await store.loadMore() }
                    }
                }
                .refreshable { await store.refresh() }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't Read Diff", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        action = Task { await store.refresh() }
                    }
                    .disabled(store.isRefreshing)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .task { await store.appear() }
        .onDisappear {
            action?.cancel()
            store.cancel()
        }
    }
}

/// Flattening the document makes each line a direct lazy child: one large
/// hunk must not cause SwiftUI to lay out every line when its header appears.
private struct FileDiffDocumentView<Footer: View>: View {
    let patch: FilePatch
    let refreshError: String?
    let footer: Footer
    private let rows: [Row]
    private let pairedRows: [Row]
    private let pairRowIDByLineID: [Int: Int]
    private let numberDigits: Int
    @Namespace private var rotor
    @Environment(\.diffLayoutSettings) private var injectedSettings
    @ScaledMetric(relativeTo: .callout) private var columnWidth: CGFloat =
        DiffLayoutPolicy.defaultColumnWidth
    @ScaledMetric(relativeTo: .caption) private var digitWidth: CGFloat =
        DiffLayoutPolicy.defaultDigitWidth
    @ScaledMetric(relativeTo: .callout) private var glyphWidth: CGFloat =
        DiffLayoutPolicy.defaultGlyphWidth
    @State private var usableWidth: CGFloat?
    /// Not observable: writing it as the user scrolls would rebuild every row.
    @State private var anchor = DiffScrollAnchor<Row.ID>()

    init(patch: FilePatch, refreshError: String?, @ViewBuilder footer: () -> Footer) {
        self.patch = patch
        self.refreshError = refreshError
        self.footer = footer()
        var rows: [Row] = []
        var maximumNumber = 1
        for file in patch.files {
            rows.append(.file(file))
            for hunk in file.hunks {
                rows.append(.hunk(hunk))
                for line in hunk.lines {
                    rows.append(.line(line))
                    maximumNumber = max(maximumNumber, max(line.oldNumber ?? 0, line.newNumber ?? 0))
                }
            }
        }
        self.rows = rows
        numberDigits = String(maximumNumber).count
        var paired: [Row] = []
        var lineMap: [Int: Int] = [:]
        for file in patch.files {
            paired.append(.file(file))
            for hunk in file.hunks {
                paired.append(.hunk(hunk))
                for side in SideBySideDiff.rows(for: hunk) {
                    paired.append(.pair(side))
                    if let left = side.left { lineMap[left.id] = side.id }
                    if let right = side.right { lineMap[right.id] = side.id }
                }
            }
        }
        self.pairedRows = paired
        self.pairRowIDByLineID = lineMap
    }

    var body: some View {
        let decision = self.decision
        // Freeze the current top line before this pass replaces row heights.
        // The following sample would otherwise record whichever line now sits
        // at the old content offset.
        let _ = anchor.holdIfChanging(
            layoutKey: decision.layout.rawValue, width: usableWidth, columnWidth: columnWidth)
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let refreshError {
                        Text(refreshError)
                            .font(.callout)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground))
                    }
                    if rows.isEmpty {
                        Text("No changes in this file.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                    ForEach(decision.layout == .sideBySide ? pairedRows : rows) { row in
                        rowView(row)
                            .id(row.id)
                    }
                    footer
                }
                .background(alignment: .topLeading) {
                    ScrollLineProbe(anchor: anchor, rowID: { Row.ID.line($0) })
                        .frame(width: 0, height: 0)
                }
                .scrollTargetLayout()
            }
            .accessibilityIdentifier("file-diff-scroll")
            .onGeometryChange(for: CGFloat.self) { proxy in
                DiffLayoutPolicy.usableWidth(
                    width: proxy.size.width,
                    leadingInset: proxy.safeAreaInsets.leading,
                    trailingInset: proxy.safeAreaInsets.trailing)
            } action: { usableWidth = $0 }
            .onAppear { anchor.adopt(scroll) }
            .onChange(of: decision.layout) { _, layout in
                keepTopLine(for: layout, proxy: scroll)
            }
            .onChange(of: usableWidth) { old, new in
                guard let old, let new, abs(new - old) >= 1 else {
                    anchor.adopt(scroll)
                    return
                }
                keepTopLine(for: resolvedLayout(usableWidth: new, columnWidth: columnWidth), proxy: scroll)
            }
            .onChange(of: columnWidth) { _, columnWidth in
                guard let usableWidth else { return }
                keepTopLine(
                    for: resolvedLayout(usableWidth: usableWidth, columnWidth: columnWidth),
                    proxy: scroll)
            }
            .animation(nil, value: decision.layout)
            .accessibilityRotor("Hunks") {
                ForEach(patch.files) { file in
                    ForEach(file.hunks) { hunk in
                        AccessibilityRotorEntry(Text(hunk.title), id: Row.ID.hunk(hunk.id), in: rotor) {
                            scroll.scrollTo(Row.ID.hunk(hunk.id), anchor: .top)
                        }
                    }
                }
            }
            .accessibilityRotor("Files") {
                ForEach(patch.files) { file in
                    AccessibilityRotorEntry(
                        Text(file.newPath ?? file.oldPath ?? "File"),
                        id: Row.ID.file(file.id), in: rotor
                    ) {
                        scroll.scrollTo(Row.ID.file(file.id), anchor: .top)
                    }
                }
            }
            .toolbar {
                if decision.toggle != .hidden {
                    ToolbarItem(placement: .topBarTrailing) {
                        Picker("Diff Layout", selection: layoutSelection) {
                            ForEach(DiffLayout.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(decision.toggle == .disabled)
                        .accessibilityIdentifier("diff-layout-picker")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .pair(let pair):
            FileDiffSideBySideRow(row: pair, numberDigits: numberDigits)
        case .file(let file):
            VStack(alignment: .leading, spacing: 6) {
                Text(file.newPath ?? file.oldPath ?? "File")
                    .font(.headline.monospaced())
                if let summary = file.summary {
                    Text(summary)
                        .font(.callout)
                }
                if file.isBinary, file.summary == nil {
                    Label("Binary file", systemImage: "doc")
                        .font(.callout)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityRotorEntry(id: row.id, in: rotor)
        case .hunk(let hunk):
            Text(hunk.title)
                .font(.callout.monospaced().weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
                .accessibilityAddTraits(.isHeader)
                .accessibilityRotorEntry(id: row.id, in: rotor)
        case .line(let line):
            FileDiffLineRow(line: line, numberDigits: numberDigits)
        }
    }

    private enum Row: Identifiable {
        enum ID: Hashable {
            case file(Int)
            case hunk(Int)
            case line(Int)
        }

        case file(DiffFile)
        case hunk(DiffHunk)
        case line(DiffLine)
        case pair(SideBySideRow)

        var id: ID {
            switch self {
            case .file(let file): .file(file.id)
            case .hunk(let hunk): .hunk(hunk.id)
            case .line(let line): .line(line.id)
            case .pair(let pair): .line(pair.id)
            }
        }
    }

    private var settings: DiffLayoutSettings {
        injectedSettings ?? .shared
    }

    private var decision: DiffLayoutDecision {
        let settings = settings
        guard settings.offersSideBySide else {
            return DiffLayoutDecision(layout: .unified, toggle: .hidden)
        }
        let preference = settings.layout
        guard let usableWidth else {
            return DiffLayoutDecision(layout: .unified, toggle: .disabled)
        }
        return DiffLayoutPolicy.resolve(
            preference: preference,
            offersSideBySide: true,
            usableWidth: usableWidth,
            columnWidth: columnWidth,
            digitWidth: digitWidth,
            glyphWidth: glyphWidth,
            numberDigits: numberDigits)
    }

    private var layoutSelection: Binding<DiffLayout> {
        let settings = settings
        return Binding(get: { settings.layout }, set: { settings.select($0) })
    }

    /// A side-by-side row id is already a unified line id. The other way
    /// maps whichever line is at the top onto the pair that shows it.
    private func anchorTarget(for remembered: Row.ID, layout: DiffLayout) -> Row.ID {
        guard layout == .sideBySide, case .line(let lineID) = remembered,
            let pairID = pairRowIDByLineID[lineID]
        else { return remembered }
        return .line(pairID)
    }

    private func resolvedLayout(usableWidth: CGFloat, columnWidth: CGFloat) -> DiffLayout {
        DiffLayoutPolicy.resolve(
            preference: settings.layout,
            offersSideBySide: settings.offersSideBySide,
            usableWidth: usableWidth,
            columnWidth: columnWidth,
            digitWidth: digitWidth,
            glyphWidth: glyphWidth,
            numberDigits: numberDigits
        ).layout
    }

    private func keepTopLine(for layout: DiffLayout, proxy: ScrollViewProxy) {
        anchor.adopt(proxy)
        guard anchor.needsRestore, let top = anchor.top else { return }
        let target = anchorTarget(for: top, layout: layout)
        let line: Int?
        if case .line(let number) = target {
            line = number
        } else {
            line = nil
        }
        anchor.restore(target, line: line)
    }

}

/// Reference box for the topmost row. Observable state here would
/// re-render the whole document on every scrolled line. It lives outside
/// the generic document view so the deferred scroll can hold it weakly.
///
/// `scrollPosition` does not move when content offset is set directly, and a
/// layout switch keeps that offset while row heights change. The visible
/// line is read from the same accessibility probe the tests use.
@MainActor
private final class DiffScrollAnchor<ID: Hashable> {
    var top: ID?
    var needsRestore = false
    fileprivate var isAdjusting = false
    private var proxy: ScrollViewProxy?
    private var pending: ID?
    private var pendingLine: Int?
    private var generation = 0
    private var frozen = false
    private var aligned = false
    private var targetIsRealized = false
    private var attempts = 0
    private var issuedMinY: CGFloat?
    private var seenLayout: String?
    private var seenWidth: CGFloat?
    private var seenColumn: CGFloat?
    private var resample: (@MainActor () -> Void)?

    func adopt(_ proxy: ScrollViewProxy) {
        self.proxy = proxy
    }

    func setResample(_ resample: @escaping @MainActor () -> Void) {
        self.resample = resample
    }

    /// Freeze the current top line once a real width is already on screen.
    /// The first resolved width is the appearance transition, not a switch.
    func holdIfChanging(layoutKey: String, width: CGFloat?, columnWidth: CGFloat) {
        let hadWidth = seenWidth != nil
        let layoutChanged = seenLayout != nil && seenLayout != layoutKey
        let widthChanged: Bool
        if let seenWidth, let width {
            widthChanged = abs(width - seenWidth) >= 1
        } else {
            widthChanged = false
        }
        let columnChanged = seenColumn.map { abs(columnWidth - $0) >= 0.01 } ?? false
        if hadWidth, top != nil, layoutChanged || widthChanged || columnChanged {
            if !frozen { frozen = true }
            needsRestore = true
        }
        seenLayout = layoutKey
        if let width { seenWidth = width }
        seenColumn = columnWidth
    }

    func restore(_ target: ID, line: Int?) {
        top = target
        pending = target
        pendingLine = line
        frozen = true
        needsRestore = false
        aligned = false
        targetIsRealized = false
        attempts = 0
        issuedMinY = nil
        generation += 1
        let generation = generation
        Task { [weak self] in
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(32))
                guard let self, self.generation == generation else { return }
                if self.aligned || self.pending == nil { return }
                self.scrollPending()
                self.resample?()
            }
        }
    }

    /// Moves the pending line under the probe. Returns the content-offset
    /// delta to apply, or nil when no scroll is required.
    func consume(_ reading: DiffLineProbe.Reading, row: (Int) -> ID) -> CGFloat? {
        guard let pendingLine else {
            // A layout pass freezes the remembered line before `restore`
            // publishes the pending id. Sampling in that gap must not
            // replace it with whatever row now lies on the old offset.
            if !frozen, let line = reading.topLine {
                note(row(line))
            }
            return nil
        }
        if reading.topLine == pendingLine {
            land(on: pendingLine, row: row)
            return nil
        }
        guard let minY = reading.minY(for: pendingLine) else {
            targetIsRealized = false
            return nil
        }
        targetIsRealized = true
        if attempts >= 5 {
            land(on: pendingLine, row: row)
            return nil
        }
        if let issuedMinY, abs(issuedMinY - minY) < 0.5 {
            return nil
        }
        attempts += 1
        issuedMinY = minY
        return minY - reading.viewportMinY
    }

    private func note(_ id: ID) {
        top = id
    }

    private func land(on line: Int, row: (Int) -> ID) {
        let id = pending ?? row(line)
        pending = nil
        pendingLine = nil
        frozen = false
        aligned = true
        issuedMinY = nil
        top = id
    }

    private func scrollPending() {
        guard !targetIsRealized, let proxy, let pending else { return }
        withTransaction(Transaction(animation: nil)) {
            proxy.scrollTo(pending, anchor: .top)
        }
    }
}

/// The line identifier the viewport probe hits, plus each realized line's
/// screen minY. Matches `FileDiffLayoutViewTests.topLineID`.
@MainActor
private enum DiffLineProbe {
    struct Reading {
        var topLine: Int? = nil
        var viewportMinY: CGFloat = 0
        fileprivate var minYByLine: [Int: CGFloat] = [:]

        func minY(for line: Int) -> CGFloat? {
            minYByLine[line]
        }
    }

    static func read(_ scroll: UIScrollView) -> Reading {
        let viewport = UIAccessibility.convertToScreenCoordinates(scroll.bounds, in: scroll)
        guard !viewport.isNull, !viewport.isEmpty else { return Reading() }
        let probe = CGPoint(x: viewport.midX, y: viewport.minY + 4)
        var reading = Reading(viewportMinY: viewport.minY)
        var bestMinY = CGFloat.greatestFiniteMagnitude
        visit(scroll.window ?? scroll) { node in
            guard let identifier = accessibilityIdentifier(of: node),
                identifier.hasPrefix("file-diff-line-"),
                let line = Int(identifier.dropFirst("file-diff-line-".count))
            else { return }
            let frame = node.accessibilityFrame
            guard !frame.isNull, !frame.isEmpty else { return }
            if let existing = reading.minYByLine[line] {
                if frame.minY < existing { reading.minYByLine[line] = frame.minY }
            } else {
                reading.minYByLine[line] = frame.minY
            }
            guard frame.contains(probe), frame.minY < bestMinY else { return }
            bestMinY = frame.minY
            reading.topLine = line
        }
        return reading
    }

    private static func accessibilityIdentifier(of node: NSObject) -> String? {
        let getter = #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)
        guard node.responds(to: getter) else { return nil }
        return node.value(forKey: "accessibilityIdentifier") as? String
    }

    private static func visit(_ root: NSObject, _ body: @MainActor (NSObject) -> Void) {
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

/// Watches the file-diff scroll view and keeps the anchored line under the
/// same probe a layout switch would otherwise move off.
private struct ScrollLineProbe<ID: Hashable>: UIViewRepresentable {
    var anchor: DiffScrollAnchor<ID>
    var rowID: (Int) -> ID

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        let anchor = anchor
        let rowID = rowID
        let sample: @MainActor () -> Void = { @MainActor [weak view, weak anchor] in
            guard let view, let anchor, let scroll = ProbeView.scrollView(from: view) else { return }
            Self.adjust(scroll, anchor: anchor, rowID: rowID)
        }
        view.onSample = sample
        anchor.setResample(sample)
        view.attach()
        sample()
    }

    @MainActor
    private static func adjust(
        _ scroll: UIScrollView, anchor: DiffScrollAnchor<ID>, rowID: (Int) -> ID
    ) {
        guard !anchor.isAdjusting else { return }
        anchor.isAdjusting = true
        defer { anchor.isAdjusting = false }
        let reading = DiffLineProbe.read(scroll)
        guard let delta = anchor.consume(reading, row: rowID) else { return }
        let y = scroll.contentOffset.y + delta
        scroll.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        let follow = DiffLineProbe.read(scroll)
        guard let again = anchor.consume(follow, row: rowID), abs(again) > 1 else { return }
        scroll.setContentOffset(
            CGPoint(x: 0, y: scroll.contentOffset.y + again), animated: false)
    }
}

private final class ProbeView: UIView {
    var onSample: (@MainActor () -> Void)?
    private var observation: NSKeyValueObservation?
    private var observed: UIScrollView?

    func attach() {
        guard let scroll = Self.scrollView(from: self), scroll !== observed else { return }
        observation?.invalidate()
        observed = scroll
        let box = SampleBox(view: self)
        observation = scroll.observe(\.contentOffset, options: [.new]) { _, _ in
            box.fire()
        }
    }

    fileprivate static func scrollView(from view: UIView) -> UIScrollView? {
        var current: UIView? = view
        var nearest: UIScrollView?
        while let node = current {
            if let scroll = node as? UIScrollView {
                if scroll.accessibilityIdentifier == "file-diff-scroll" { return scroll }
                if nearest == nil { nearest = scroll }
            }
            current = node.superview
        }
        return nearest
    }
}

private final class SampleBox: @unchecked Sendable {
    weak var view: ProbeView?
    init(view: ProbeView) { self.view = view }

    func fire() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.view?.onSample?()
            }
        }
    }
}

private struct FileDiffLineRow: View {
    let line: DiffLine
    let numberDigits: Int
    @ScaledMetric(relativeTo: .caption) private var digitWidth: CGFloat = 8
    @ScaledMetric(relativeTo: .callout) private var glyphWidth: CGFloat = 12

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.oldNumber.map(String.init) ?? "")
                .frame(width: digitWidth * CGFloat(numberDigits), alignment: .trailing)
            Text(line.newNumber.map(String.init) ?? "")
                .frame(width: digitWidth * CGFloat(numberDigits), alignment: .trailing)
            Text(line.glyph)
                .font(.callout.monospaced().weight(.semibold))
                .frame(width: glyphWidth)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.text.isEmpty ? " " : line.text)
                    .font(.callout.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                if line.missingNewline {
                    Text("No newline at end of file")
                        .font(.caption.italic())
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.monospaced())
        .foregroundStyle(Color(uiColor: DiffPalette.ink(for: line.kind)))
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: DiffPalette.background(for: line.kind)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.accessibilityLabel)
        .accessibilityIdentifier("file-diff-line-\(line.id)")
    }
}

/// One footer is the integration point for the file's line counts. All
/// too-large wording, including its accessibility text, comes from the store.
private struct FileDiffFooter: View {
    let store: FileDiffStore
    let loadMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.truncation == .canLoadMore {
                Text("Showing the first part of this diff.")
                    .foregroundStyle(.secondary)
                Button("Load More", action: loadMore)
                    .disabled(store.isRefreshing)
            } else if store.truncation == .tooLarge {
                Text(store.tooLargeMessage)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(store.tooLargeMessage)
            }
            if store.isRefreshing {
                ProgressView("Refreshing Diff…")
            }
        }
        .font(.callout)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
