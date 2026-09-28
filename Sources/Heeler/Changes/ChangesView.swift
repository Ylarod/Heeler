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
        list
            // A read resolving another Checkout replaces the whole view,
            // scroll position included; a refresh of the same one keeps it.
            .id(store.checkout)
            .task { await store.appear() }
            .onDisappear { retry?.cancel() }
            .navigationTitle("Changes")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.backward", action: onBack)
                }
                if store.isRefreshing, !isPulling {
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
                    ChangesHeader(changes: changes)
                }
                Section {
                    if changes.isClean {
                        Text(ChangesStore.cleanMessage)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(changes.files) { file in
                            ChangesFileRow(file: file)
                        }
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

/// The Checkout, its branch or detached commit, and the latest commit. One
/// VoiceOver element whose summary names the Checkout and never an Agent.
private struct ChangesHeader: View {
    let changes: CheckoutChanges
    @Environment(\.locale) private var locale

    var body: some View {
        // The latest commit's age is relative, so it moves on by itself.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(changes.checkout.displayPath)
                        .font(.body.monospaced())
                        .fixedSize(horizontal: false, vertical: true)
                    if changes.checkout.isLinkedWorktree {
                        Text("Worktree")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                    }
                }
                HStack(spacing: 6) {
                    Image(
                        systemName: changes.head.branch == .detached
                            ? "smallcircle.filled.circle" : "arrow.triangle.branch")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Text(changes.head.branchTitle)
                }
                .font(.subheadline)
                if let latest = changes.head.latestCommit {
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                changes.accessibilitySummary(relativeTo: context.date, locale: locale))
        }
    }
}

/// One file: a change-kind badge beside its path, which wraps under itself
/// rather than under the badge, and its kind and staging below.
private struct ChangesFileRow: View {
    let file: ChangedFile

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(file.kind.symbol)
                .font(.caption.monospaced().weight(.bold))
                .frame(minWidth: 20)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.quaternary))
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayPath)
                    .font(.callout.monospaced())
                Text(file.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(file.accessibilityLabel)
    }
}
