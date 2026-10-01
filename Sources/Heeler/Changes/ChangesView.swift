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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            list
                // A read resolving another Checkout replaces the whole view,
                // scroll position included; a refresh of the same one keeps it.
                .id(store.checkout)
                .opacity(store.fileDiff.current == nil ? 1 : 0)
                // Kept built for its scroll position, so it comes back as
                // `backPushUncovered` would bring it: from the leading edge.
                .visualEffect { [isShowingDiff = store.fileDiff.current != nil] content, proxy in
                    content.offset(x: isShowingDiff ? -proxy.size.width : 0)
                }
                .allowsHitTesting(store.fileDiff.current == nil)
                .accessibilityHidden(store.fileDiff.current != nil)
            if let diff = store.fileDiff.current {
                FileDiffView(store: diff)
                    .environment(\.changesReferenceActions, ChangesReferenceActions(store: store))
                    .id(ObjectIdentifier(diff))
                    .transition(.backPush)
            }
        }
        // The bar's back button is custom, so the system's swipe is gone;
        // this one goes back as that button does, a diff to its list first.
        .gesture(ChangesBackSwipe(dismiss: goBack))
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
                Button("Back", systemImage: "chevron.backward", action: goBack)
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

    /// Animated, so a diff and Changes leave as a pushed screen pops.
    private func goBack() {
        withAnimation(reduceMotion ? nil : .default) {
            if store.fileDiff.current != nil {
                store.closeDiff()
            } else {
                onBack()
            }
        }
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
                if changes.isClean {
                    Section {
                        Text(ChangesStore.cleanMessage)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(changes.listedSections) { section in
                        Section {
                            ForEach(section.files) { file in
                                fileRow(file)
                            }
                        } header: {
                            ChangesSectionHeader(section: section)
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
        // The groups read as one list, as Source Control's do.
        .listSectionSpacing(.compact)
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
    private func fileRow(_ file: ChangedFile) -> some View {
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

/// The Checkout by name, with its line totals, its branch and how far it
/// has moved from its upstream, and the latest commit, in three lines; the
/// groups below count the files. One VoiceOver element whose summary names
/// the Checkout, its path included, and never an Agent.
private struct ChangesHeader: View {
    let changes: CheckoutChanges
    let freshness: ChangesFreshness?
    @Environment(\.locale) private var locale

    var body: some View {
        // The latest commit's age is relative, so it moves on by itself.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 6) {
                // The totals move under the name rather than cut it short.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        name
                        Spacer(minLength: 8)
                        if !changes.isClean { totals }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        name
                        if !changes.isClean { totals }
                    }
                }
                ChangesBranchRow(head: changes.head)
                if let latest = changes.head.latestCommit {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        ChangesHeaderIcon(systemName: "smallcircle.circle")
                        Text(latest.subject)
                            .lineLimit(1)
                        Text(verbatim: "· " + latest.age(relativeTo: context.date, locale: locale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .font(.subheadline)
                }
                if changes.head.isUnborn {
                    Text("No commits yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let freshness {
                    Text(freshness.text(relativeTo: context.date, locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                changes.accessibilitySummary(relativeTo: context.date, locale: locale)
                    + (freshness.map {
                        " " + $0.accessibilitySummary(relativeTo: context.date, locale: locale)
                    } ?? ""))
        }
    }

    private var name: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: changes.checkout.name)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)
            if changes.checkout.isLinkedWorktree {
                Text("Worktree")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
                    .fixedSize()
            }
        }
    }

    /// The line totals, a side with no lines left out as in the rows;
    /// "At least" when git could not count every file. Nothing when git
    /// produced no line counts or no line changed. At the rows' size, so
    /// they stay quieter than the name beside them.
    @ViewBuilder
    private var totals: some View {
        let totals = changes.totals
        if totals.linesAreAvailable {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if !totals.linesAreComplete, totals.added + totals.removed > 0 {
                    Text("At least")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ChangesLineCounts(
                    counts: .lines(added: totals.added, removed: totals.removed),
                    font: .footnote.weight(.medium))
            }
            .fixedSize()
        }
    }
}

/// A group's title and how many of the listed files it holds.
private struct ChangesSectionHeader: View {
    let section: ChangesFileSection

    var body: some View {
        HStack {
            Text(section.group.title)
                .textCase(.uppercase)
            Spacer()
            Text(section.files.count.formatted())
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.group.title)
        .accessibilityValue(
            "\(section.files.count.formatted()) \(section.files.count == 1 ? "file" : "files")")
        .accessibilityAddTraits(.isHeader)
    }
}

/// One file, as VS Code lists it: its name with its directory beside it,
/// then its line counts and its change letter, on one line; at
/// accessibility sizes the directory moves beneath. A partly staged file
/// carries a half-filled circle. VoiceOver reads its path, kind, staging,
/// and counts.
struct ChangesFileRow: View {
    let file: ChangedFile
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 1) {
                        name
                        detail
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        name
                            .layoutPriority(1)
                        detail
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if file.kind != .untracked, let lineCounts = file.lineCounts {
                ChangesLineCounts(counts: lineCounts, font: .footnote.weight(.medium))
            }
            Text(verbatim: file.kind.symbol)
                .font(.subheadline.monospaced().weight(.bold))
                .foregroundStyle(Color(uiColor: ChangeKindPalette.color(for: file.kind)))
                .frame(minWidth: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(file.rowAccessibilityLabel)
    }

    private var name: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: file.fileName)
                .font(.callout)
                .strikethrough(file.kind == .deleted, color: .secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.middle)
            if file.isPartlyStaged {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let detail = file.rowDetail {
            // The end of a directory names it best, so it keeps that end;
            // a rename leads with its source and keeps that instead.
            Text(verbatim: detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(file.originalPath == nil ? .head : .tail)
        }
    }
}

extension AnyTransition {
    /// A screen that leaves for the one behind it: in from the trailing edge
    /// as a push, out toward it as a pop.
    static var backPush: AnyTransition {
        .asymmetric(insertion: .push(from: .trailing), removal: .push(from: .leading))
    }

    /// The screen behind, uncovered by `backPush`.
    static var backPushUncovered: AnyTransition {
        .asymmetric(insertion: .push(from: .leading), removal: .push(from: .trailing))
    }
}

/// Back on a rightward swipe that starts anywhere in Changes, as a system
/// navigation stack offers. A strip on the leading edge would not do: beside
/// a shown iPad sidebar that edge is the split view's resize handle, whose
/// touches never reach the detail. A UIKit pan, so the split view's own pans
/// around it, such as bringing the sidebar out, wait until it has failed.
private struct ChangesBackSwipe: UIGestureRecognizerRepresentable {
    let dismiss: @MainActor () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer, context: Context
    ) {
        guard recognizer.state == .ended else { return }
        let translation = recognizer.translation(in: recognizer.view)
        guard translation.x >= 72, abs(translation.y) <= translation.x * 0.75
        else { return }
        dismiss()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Only a mostly sideways drag to the right: scrolls and taps pass.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x > 0 && abs(velocity.y) <= velocity.x
        }

        /// The list scrolls under a swipe that drifts.
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            other.view is UIScrollView
        }

        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            guard other is UIPanGestureRecognizer, !(other.view is UIScrollView),
                let view = recognizer.view, let otherView = other.view, otherView !== view
            else { return false }
            return view.isDescendant(of: otherView)
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
