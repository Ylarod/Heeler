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
    private let numberDigits: Int
    @Namespace private var rotor

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
    }

    var body: some View {
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
                    ForEach(rows) { row in
                        rowView(row)
                            .id(row.id)
                    }
                    footer
                }
            }
            .accessibilityIdentifier("file-diff-scroll")
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
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
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

        var id: ID {
            switch self {
            case .file(let file): .file(file.id)
            case .hunk(let hunk): .hunk(hunk.id)
            case .line(let line): .line(line.id)
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
