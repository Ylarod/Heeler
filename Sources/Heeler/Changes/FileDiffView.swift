import SwiftUI

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
    @State private var contentInsetTop: CGFloat = 0

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
        // Freeze the remembered line before this pass replaces row heights.
        // The next frame sample would otherwise record whichever line now
        // sits at the old content offset.
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
                .scrollTargetLayout()
            }
            .accessibilityIdentifier("file-diff-scroll")
            .backgroundPreferenceValue(DiffLineFramesKey.self) { anchors in
                GeometryReader { proxy in
                    let line = DiffLineFrames.lineID(
                        in: anchors, chrome: max(contentInsetTop, proxy.safeAreaInsets.top),
                        proxy: proxy)
                    Color.clear
                        .allowsHitTesting(false)
                        .onAppear { anchor.note(line.map(Row.ID.line)) }
                        .onChange(of: line) { _, new in
                            anchor.note(new.map(Row.ID.line))
                        }
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentInsets.top
            } action: { _, inset in
                guard abs(inset - contentInsetTop) >= 0.5 else { return }
                contentInsetTop = inset
            }
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
                .anchorPreference(key: DiffLineFramesKey.self, value: .bounds) { [pair.id: $0] }
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
                .anchorPreference(key: DiffLineFramesKey.self, value: .bounds) { [line.id: $0] }
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
        anchor.restore(anchorTarget(for: top, layout: layout))
    }

}

/// Bounds of the realized diff lines, in the scroll view's coordinates.
/// Only rows on screen publish one, so a long file does not record every line.
private struct DiffLineFramesKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum DiffLineFrames {
    /// The line whose frame contains the point just below the top chrome.
    static func lineID(
        in anchors: [Int: Anchor<CGRect>], chrome: CGFloat, proxy: GeometryProxy
    ) -> Int? {
        let edge = chrome + 4
        var bestID: Int?
        var bestMinY = CGFloat.greatestFiniteMagnitude
        for (id, anchor) in anchors {
            let frame = proxy[anchor]
            guard frame.minY <= edge, frame.maxY > edge, frame.minY < bestMinY else { continue }
            bestMinY = frame.minY
            bestID = id
        }
        return bestID
    }
}

/// Topmost row. Not observable: publishing it would rebuild every line.
///
/// The remembered line is the one crossing the readable edge, below the top
/// chrome. A layout change scrolls that row back. A restore always clears,
/// including when its target never appears.
@MainActor
private final class DiffScrollAnchor<ID: Hashable> {
    var top: ID?
    var needsRestore = false
    private var proxy: ScrollViewProxy?
    private var pending: ID?
    private var generation = 0
    private var frozen = false
    private var seenLayout: String?
    private var seenWidth: CGFloat?
    private var seenColumn: CGFloat?

    func adopt(_ proxy: ScrollViewProxy) {
        self.proxy = proxy
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

    func note(_ id: ID?) {
        guard let id else { return }
        if frozen {
            if let pending, id == pending {
                self.pending = nil
                frozen = false
                top = id
            }
            return
        }
        top = id
    }

    func restore(_ target: ID) {
        top = target
        pending = target
        frozen = true
        needsRestore = false
        generation += 1
        let generation = generation
        Task { [weak self] in
            for _ in 0..<8 {
                await Task.yield()
                guard let self, self.generation == generation, self.pending != nil else { return }
                self.scrollPending()
                try? await Task.sleep(for: .milliseconds(32))
            }
            self?.endRestore(generation)
        }
    }

    private func endRestore(_ generation: Int) {
        guard self.generation == generation else { return }
        pending = nil
        frozen = false
    }

    private func scrollPending() {
        guard let proxy, let pending else { return }
        withTransaction(Transaction(animation: nil)) {
            proxy.scrollTo(pending, anchor: .top)
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
