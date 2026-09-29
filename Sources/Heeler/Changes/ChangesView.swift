import SwiftUI

/// A Checkout's uncommitted files, shown in place of Agent detail. Thin: the
/// store owns reads and states, and the document model owns every string, so
/// nothing here knows git.
struct ChangesView: View {
    let store: ChangesStore
    let onBack: () -> Void
    /// A pull shows the system's own indicator; the bar's is for the rest.
    @State private var isPulling = false
    /// Try Again's read. Like the first read's `.task`, it ends when Changes
    /// leave the screen rather than running on for a store nobody shows.
    @State private var retry: Task<Void, Never>?

    var body: some View {
        ZStack {
            list
                // A read resolving another Checkout replaces the whole view,
                // scroll position included; a refresh of the same one keeps it.
                .id(store.checkout)
                .opacity(store.fileDiff.current == nil ? 1 : 0)
                .allowsHitTesting(store.fileDiff.current == nil)
                .accessibilityHidden(store.fileDiff.current != nil)
            if let diff = store.fileDiff.current {
                FileDiffView(store: diff)
                    .environment(\.changesReferenceActions, ChangesReferenceActions(store: store))
                    .id(ObjectIdentifier(diff))
            }
        }
        .task { await store.appear() }
        .task { await store.followAgentStatus() }
        .onDisappear {
            retry?.cancel()
            store.fileDiff.current?.cancel()
        }
        .navigationTitle(store.fileDiff.current?.file.displayPath ?? "Changes")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.backward") {
                    if store.fileDiff.current != nil {
                        store.closeDiff()
                    } else {
                        onBack()
                    }
                }
            }
            if let diff = store.fileDiff.current {
                ToolbarItem(placement: .principal) {
                    FileDiffTitle(path: diff.file.displayPath)
                }
            }
            if store.fileDiff.current == nil, store.isRefreshing, !isPulling {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .accessibilityLabel("Refreshing Changes")
                }
            }
        }
        .toolbar(.visible, for: .navigationBar)
    }

    private var list: some View {
        List {
            if case .loaded(let changes) = store.phase {
                if store.timedOutKeepingContent {
                    Section {
                        ChangesTimeoutNotice()
                    }
                }
                Section {
                    ChangesHeader(changes: changes, freshness: store.freshness)
                }
                Section("Files") {
                    if changes.isClean {
                        Text(ChangesStore.cleanMessage)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(changes.listedFiles) { file in
                            if file.isUntrackedDirectory {
                                ChangesUntrackedDirectoryRows(directory: file, store: store)
                            } else {
                                Button { store.openDiff(file) } label: {
                                    ChangesFileRow(file: file)
                                }
                                .buttonStyle(.plain)
                                .changedFileReferenceMenu(file, store: store)
                            }
                        }
                    }
                }
                if changes.listLimitNotice != nil || changes.isMetadataTruncated {
                    Section {
                        ChangesLimitNotice(changes: changes)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        // One ground for every state, so the first read lands without a flash.
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable {
            isPulling = true
            defer { isPulling = false }
            await store.refresh()
        }
        .overlay { stateOverlay }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if store.phase == .loading {
            ProgressView("Reading Changes…")
        } else if let failure = store.phase.failure {
            ChangesFailureState(
                title: failure.title, message: failure.message, symbol: failure.symbol
            ) {
                tryAgain
            }
        }
    }

    private var tryAgain: some View {
        Button("Try Again") {
            retry = Task { await store.refresh() }
        }
        .disabled(store.isRefreshing)
    }
}

/// The Checkout by name and path, its branch with its upstream, the latest
/// commit, and its totals. One VoiceOver element whose summary names the
/// Checkout and never an Agent.
private struct ChangesHeader: View {
    let changes: CheckoutChanges
    let freshness: ChangesFreshness?
    @Environment(\.locale) private var locale

    var body: some View {
        // The latest commit's age is relative, so it moves on by itself.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: changes.checkout.name)
                            .font(.title3.weight(.semibold))
                        if changes.checkout.isLinkedWorktree {
                            Text("Worktree")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.quaternary))
                        }
                    }
                    Text(verbatim: changes.checkout.displayPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                ChangesBranchRow(head: changes.head)
                if let latest = changes.head.latestCommit {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        ChangesHeaderIcon(systemName: "smallcircle.circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(latest.subject)
                                .font(.subheadline)
                                .lineLimit(3)
                            Text(latest.age(relativeTo: context.date, locale: locale))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if changes.head.isUnborn {
                    Text("No commits yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !changes.isClean {
                    Divider()
                    ChangesTotalsRow(changes: changes)
                }
                if let freshness {
                    Text(freshness.text(relativeTo: context.date, locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                changes.accessibilitySummary(relativeTo: context.date, locale: locale)
                    + (freshness.map {
                        " " + $0.accessibilitySummary(relativeTo: context.date, locale: locale)
                    } ?? ""))
        }
    }
}

/// One file, as VS Code lists it: its name, with its directory, rename, and
/// staging beneath, then its line counts and its change letter. VoiceOver
/// reads its path, kind, staging, and counts.
struct ChangesFileRow: View {
    let file: ChangedFile

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: file.fileName)
                    .font(.callout)
                    .strikethrough(file.kind == .deleted, color: .secondary)
                if let subtitle = file.rowSubtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
            Text(verbatim: file.kind.symbol)
                .font(.subheadline.monospaced().weight(.bold))
                .foregroundStyle(Color(uiColor: ChangeKindPalette.color(for: file.kind)))
                .frame(minWidth: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(file.rowAccessibilityLabel)
    }

    @ViewBuilder
    private var trailing: some View {
        if file.kind == .untracked {
            if !file.isUntrackedDirectory {
                Text("New")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if let lineCounts = file.lineCounts {
            ChangesLineCounts(counts: lineCounts, font: .footnote.weight(.medium))
        }
    }
}

/// An open diff's title: the file's name, with its directory beneath.
private struct FileDiffTitle: View {
    let path: String

    var body: some View {
        let slash = path.lastIndex(of: "/")
        let name = slash.map { String(path[path.index(after: $0)...]) } ?? path
        let directory = slash.map { String(path[..<$0]) } ?? ""
        VStack(spacing: 1) {
            Text(verbatim: name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            if !directory.isEmpty {
                Text(verbatim: directory)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(path)
        .accessibilityAddTraits(.isHeader)
    }
}
