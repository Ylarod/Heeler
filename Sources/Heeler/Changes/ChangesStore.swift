import Foundation
import Observation
import UIKit

/// One Changes view's document: the Checkout containing an Agent's current
/// directory, read over the Transport seam. Owned by the view that shows it
/// and discarded with it, so nothing outlives the Agent detail it belongs
/// to. Status edges refresh the list; lazy file reads stay independent.
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

    /// Reads once per presentation; returning to the view reads nothing
    /// new until a read has completed.
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
        guard activeRead == nil, !Task.isCancelled else { return }
        guard let directory = directory() ?? lastDirectory else {
            phase = .failed("This Agent has no working directory.")
            return
        }
        lastDirectory = directory
        let id = UUID()
        readID = id
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
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Called inside the Host gate, which is released on local completion.
    private func readAndApply(directory: String, id: UUID, automatic: Bool) async {
        guard !Task.isCancelled, readID == id else { return }
        autoRefresh.readSawWorking = autoRefresh.status == .working
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
            if automatic, hadRead {
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
}
