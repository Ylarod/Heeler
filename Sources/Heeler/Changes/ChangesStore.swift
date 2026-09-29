import Foundation
import Observation
import UIKit

/// One Checkout's Changes document: the Checkout containing an Agent's
/// current directory, read over the Transport seam. Agent detail keeps its
/// Agent's store for its whole lifetime, shared by the switcher badge and
/// Changes; a Worktree's store lives only while its Changes are shown. So
/// nothing outlives the Agent detail it belongs to. Status edges refresh the
/// list; lazy file reads stay independent.
@MainActor
@Observable
final class ChangesStore {
    enum Phase: Equatable {
        /// No read has completed yet.
        case loading
        case loaded(CheckoutChanges)
        /// The Agent's directory is not inside a git working tree.
        case notAGitWorkingTree
        /// An unclassified failure; carries git's first error line.
        case failed(String)
        case gitMissing
        case gitTooOld(String)
        case notOwnedByAccount
        case directoryMissing
        case incomplete
        case timedOut

        /// A display-ready explanation keeps git knowledge out of views.
        var failure: (title: String, message: String, symbol: String)? {
            switch self {
            case .loading, .loaded:
                nil
            case .notAGitWorkingTree:
                ("Not a Git Working Tree", ChangesReadError.notAGitWorkingTree.message, "folder.badge.questionmark")
            case .failed(let message):
                ("Couldn't Read Changes", message, "exclamationmark.triangle")
            case .gitMissing:
                ("Git Not Found", ChangesReadError.gitMissing.message, "folder.badge.questionmark")
            case .gitTooOld(let version):
                ("Git Version Too Old", ChangesReadError.gitTooOld(version).message, "arrow.up.circle")
            case .notOwnedByAccount:
                ("Checkout Ownership Protected", ChangesReadError.notOwnedByAccount.message, "lock.shield")
            case .directoryMissing:
                ("Directory No Longer Exists", ChangesReadError.directoryMissing.message, "folder.badge.questionmark")
            case .incomplete:
                ("Incomplete Changes", ChangesReadError.incomplete.message, "exclamationmark.triangle")
            case .timedOut:
                ("Reading Changes Timed Out", "The Host took too long to read Changes. Pull to try again.", "clock")
            }
        }
    }

    static let cleanMessage = "No uncommitted changes"

    private(set) var phase: Phase = .loading
    /// A read is running while content from an earlier read stays on screen.
    private(set) var isRefreshing = false
    /// Where the Agent's directory sits inside the Checkout, raw bytes,
    /// from the latest successful read; empty at the top level.
    private(set) var directoryPrefix = Data()
    /// A timed-out refresh keeps the last document, identity and scroll position.
    private(set) var timedOutKeepingContent = false
    private(set) var readAt: Date?
    @ObservationIgnored let autoRefresh: ChangesAutoRefresh
    @ObservationIgnored private let gate: GitExecGate?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored var activeRead: Task<Void, Never>?
    @ObservationIgnored var readID = UUID()
    /// The read that has entered the Transport, which a departing Agent
    /// detail lets finish rather than stacking another git process.
    @ObservationIgnored var dispatchedReadID: UUID?
    /// Counts reads begun, so Agent detail's settled read can tell that
    /// Changes already read in the meantime.
    @ObservationIgnored var readsStarted = 0
    /// Agent detail's current following, so a stale one never stops it.
    @ObservationIgnored var agentDetailFollowID: UUID?
    /// Gates "Checkout Changes updated."; false while Agent detail reads its
    /// store for the badge with Changes closed, since nothing on screen
    /// changed for VoiceOver to hear about.
    @ObservationIgnored var announcesAutomaticUpdates = true
    /// True while another shown store reads this Checkout for each exit from
    /// Working, as Worktree Changes of the Checkout the Agent is in now do:
    /// this store's automatic refresh then waits for Back instead of reading
    /// the same Checkout again.
    @ObservationIgnored var automaticRefreshIsCoveredElsewhere: (@MainActor () -> Bool)?

    var freshness: ChangesFreshness? {
        guard case .loaded = phase, let readAt,
            autoRefresh.status == .working || autoRefresh.readWasWhileWorking
        else { return nil }
        return ChangesFreshness(readAt: readAt)
    }

    /// The Checkout the document describes. Views key their content on it,
    /// so a read resolving another Checkout replaces the document wholesale.
    var checkout: CheckoutLocation? {
        if case .loaded(let changes) = phase { changes.checkout } else { nil }
    }

    /// Expanded untracked directories. A successful read collapses them; a
    /// failed read keeps them until the next success.
    let untrackedDirectories: UntrackedDirectoryExpansions

    @ObservationIgnored private let directory: @MainActor () -> String?
    @ObservationIgnored private let read:
        @Sendable (ChangesReadRequest) async throws -> CheckoutChangesRead
    @ObservationIgnored private var lastDirectory: String?
    @ObservationIgnored private var hasRead = false

    let fileDiff: FileDiffPresenter

    @ObservationIgnored var insertReference: (@MainActor (String) -> Void)?
    @ObservationIgnored var copyToPasteboard: (@MainActor (String) -> Void)?
    @ObservationIgnored var referencesFollowAgentDirectory = true

    /// `directory` is asked on every read, so an Agent that moved to another
    /// Checkout is read where it is now.
    init(
        directory: @escaping @MainActor () -> String?,
        read: @escaping @Sendable (ChangesReadRequest) async throws -> CheckoutChangesRead,
        readPatch: @escaping @Sendable (FilePatchRequest) async throws -> FilePatch = { _ in
            throw ChangesReadError.unavailable
        },
        listUntrackedDirectory: @escaping @Sendable (UntrackedDirectoryRequest) async throws
            -> UntrackedDirectoryListing = { _ in throw ChangesReadError.unavailable },
        gate: GitExecGate? = nil,
        agentStatus: (@MainActor () -> AsyncStream<ConsoleStore.AgentStatusUpdate>)? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @MainActor () -> Date = { Date() },
        announce: @escaping @MainActor (String) -> Void = {
            UIAccessibility.post(notification: .announcement, argument: $0)
        }
    ) {
        self.directory = directory
        self.read = read
        self.gate = gate
        self.now = now
        self.announce = announce
        self.autoRefresh = ChangesAutoRefresh(agentStatus: agentStatus, sleep: sleep)
        self.fileDiff = FileDiffPresenter(
            read: GitExecGate.wrapping(gate, operation: readPatch), now: now)
        self.untrackedDirectories = UntrackedDirectoryExpansions(
            list: GitExecGate.wrapping(gate, operation: listUntrackedDirectory))
    }

    /// Reads once per store; returning to the view reads nothing new once a
    /// read has completed. Agent detail's store is read by its own following
    /// and by `startRefresh()` instead.
    func appear() async {
        startFollowingAgentStatus()
        await applyBufferedOpeningStatus()
        guard !hasRead else { return }
        await refresh()
    }

    /// Reads the Checkout again, keeping the current document on screen.
    func refresh() async {
        await refresh(automatic: false)
    }

    func refresh(automatic: Bool) async {
        guard let task = startRead(automatic: automatic) else { return }
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Reads the Checkout again without tying the read to the caller: it
    /// belongs to the store, so leaving the view that asked does not cancel
    /// it. A read already running is adopted instead of starting another.
    func startRefresh() {
        startRead()
    }

    /// A read the user asked for on Agent detail's store: owned by the store,
    /// as `startRefresh()`'s is, so leaving Changes neither cancels it nor
    /// loses an automatic refresh queued behind it. A read already running
    /// is awaited instead. Cancelling the caller does not end the wait
    /// either: it lasts until the read finishes, which the git read's
    /// deadline bounds.
    func refreshOwnedByStore() async {
        guard let task = startRead() ?? activeRead else { return }
        await task.value
    }

    /// Starts a read owned by the store; nil while one is running.
    @discardableResult
    func startRead(automatic: Bool = false) -> Task<Void, Never>? {
        guard activeRead == nil, !Task.isCancelled else { return nil }
        guard let directory = directory() ?? lastDirectory else {
            phase = .failed("This Agent has no working directory.")
            return nil
        }
        lastDirectory = directory
        let id = UUID()
        readID = id
        readsStarted += 1
        isRefreshing = phase != .loading
        let task = Task { [weak self, gate] in
            guard let self else { return }
            do {
                if let gate {
                    // Publish the list and invalidate obsolete lazy requests
                    // before handing the Host slot to the next queued read.
                    try await gate.run {
                        await self.readAndApply(directory: directory, id: id, automatic: automatic)
                    }
                } else {
                    await self.readAndApply(directory: directory, id: id, automatic: automatic)
                }
            } catch {
                // Cancellation while waiting never enters the Transport.
            }
            guard self.readID == id else { return }
            self.activeRead = nil
            self.isRefreshing = false
            if !Task.isCancelled { self.runPendingAutomaticRefresh() }
        }
        activeRead = task
        return task
    }

    /// Called inside the Host gate, which is released on local completion.
    private func readAndApply(directory: String, id: UUID, automatic: Bool) async {
        guard !Task.isCancelled, readID == id else { return }
        autoRefresh.readSawWorking = autoRefresh.status == .working
        dispatchedReadID = id
        do {
            let result = try await read(ChangesReadRequest(directory: directory))
            try Task.checkCancellation()
            guard readID == id else { return }
            let previous = phase
            let hadRead = hasRead
            untrackedDirectories.collapseAll()
            phase = .loaded(result.changes)
            directoryPrefix = result.directoryPrefix
            timedOutKeepingContent = false
            hasRead = true
            readAt = now()
            autoRefresh.readWasWhileWorking = autoRefresh.readSawWorking || autoRefresh.status == .working
            fileDiff.listDidRefresh(result.changes)
            if automatic, hadRead, announcesAutomaticUpdates {
                let previousFiles: [ChangedFile]?
                if case .loaded(let old) = previous { previousFiles = old.files } else { previousFiles = nil }
                if previousFiles != result.changes.files { announce("Checkout Changes updated.") }
            }
        } catch is CancellationError, TransportError.cancelled {
            // Left mid-read: nothing from it is shown, and the next
            // appearance reads again.
        } catch let error as ChangesReadError {
            guard readID == id, !Task.isCancelled else { return }
            dropPendingAutomaticRefresh()
            hasRead = true
            directoryPrefix = Data()
            timedOutKeepingContent = false
            if error == .notAGitWorkingTree {
                phase = .notAGitWorkingTree
            } else if error == .gitMissing {
                phase = .gitMissing
            } else if case .gitTooOld(let version) = error {
                phase = .gitTooOld(version)
            } else if error == .notOwnedByAccount {
                phase = .notOwnedByAccount
            } else if error == .directoryMissing {
                phase = .directoryMissing
            } else if error == .incomplete {
                phase = .incomplete
            } else {
                phase = .failed(error.message)
            }
        } catch let error as TransportError {
            guard readID == id, !Task.isCancelled else { return }
            dropPendingAutomaticRefresh()
            hasRead = true
            if error == .gitTimedOut, case .loaded = phase {
                timedOutKeepingContent = true
            } else {
                timedOutKeepingContent = false
                directoryPrefix = Data()
                phase = error == .gitTimedOut ? .timedOut : .failed(error.presentation.explanation)
            }
        } catch {
            guard readID == id, !Task.isCancelled else { return }
            dropPendingAutomaticRefresh()
            hasRead = true
            timedOutKeepingContent = false
            directoryPrefix = Data()
            phase = .failed(error.localizedDescription)
        }
    }

    func cancelRead() {
        readID = UUID()
        activeRead?.cancel()
        activeRead = nil
        isRefreshing = false
    }

    /// Whether the running read has already entered the Transport.
    var isReadDispatched: Bool {
        activeRead != nil && dispatchedReadID == readID
    }

    /// Back from Changes on Agent detail's store: the document and any read
    /// stay for the badge; the diff, expansions, and announcements go.
    func leavePresentation() {
        announcesAutomaticUpdates = false
        fileDiff.close()
        untrackedDirectories.collapseAll()
    }

    /// Whether this store's next read lands inside `checkout`: for the
    /// Agent's own store, whether the Agent is in that Checkout now rather
    /// than when this store last read.
    func readsInside(_ checkout: CheckoutLocation) -> Bool {
        guard let directory = directory() ?? lastDirectory else { return false }
        return checkout.contains(directory: directory)
    }

    /// Worktree Changes can show the Agent's own Checkout. When that store
    /// closes with a newer successful read of the same Checkout, and the
    /// Agent is still in it, this store takes its document, keeping its own
    /// directory prefix: the totals are the whole Checkout's either way.
    func adoptNewerRead(of other: ChangesStore) {
        guard case .loaded(let changes) = other.phase, let otherReadAt = other.readAt,
            case .loaded(let own) = phase, own.checkout.topLevel == changes.checkout.topLevel,
            otherReadAt > readAt ?? .distantPast, readsInside(changes.checkout)
        else { return }
        untrackedDirectories.collapseAll()
        phase = .loaded(changes)
        readAt = otherReadAt
        timedOutKeepingContent = false
        autoRefresh.readWasWhileWorking = other.autoRefresh.readWasWhileWorking
        fileDiff.listDidRefresh(changes)
    }
}
