import Foundation
import Observation

/// One Changes view's document: the Checkout containing an Agent's current
/// directory, read over the Transport seam. Owned by the view that shows it
/// and discarded with it, so nothing outlives the Agent detail it belongs
/// to. Reads are single-flight; automatic refresh arrives in #388.
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

    /// The Checkout the document describes. Views key their content on it,
    /// so a read resolving another Checkout replaces the document wholesale.
    var checkout: CheckoutLocation? {
        if case .loaded(let changes) = phase { changes.checkout } else { nil }
    }

    @ObservationIgnored private let directory: @MainActor () -> String?
    @ObservationIgnored private let read:
        @Sendable (ChangesReadRequest) async throws -> CheckoutChangesRead
    @ObservationIgnored private var lastDirectory: String?
    @ObservationIgnored private var isReading = false
    @ObservationIgnored private var hasRead = false

    let fileDiff: FileDiffPresenter

    /// `directory` is asked on every read, so an Agent that moved to another
    /// Checkout is read where it is now.
    init(
        directory: @escaping @MainActor () -> String?,
        read: @escaping @Sendable (ChangesReadRequest) async throws -> CheckoutChangesRead,
        readPatch: @escaping @Sendable (FilePatchRequest) async throws -> FilePatch = { _ in
            throw ChangesReadError.unavailable
        }
    ) {
        self.directory = directory
        self.read = read
        self.fileDiff = FileDiffPresenter(read: readPatch)
    }

    /// Reads once per presentation; returning to the view reads nothing
    /// new until a read has completed.
    func appear() async {
        guard !hasRead else { return }
        await refresh()
    }

    /// Reads the Checkout again, keeping what is shown until the read
    /// lands. A request while one is running starts nothing.
    func refresh() async {
        guard !isReading else { return }
        guard let directory = directory() ?? lastDirectory else {
            phase = .failed("This Agent has no working directory.")
            return
        }
        lastDirectory = directory
        isReading = true
        isRefreshing = phase != .loading
        defer {
            isReading = false
            isRefreshing = false
        }
        do {
            let result = try await read(ChangesReadRequest(directory: directory))
            phase = .loaded(result.changes)
            directoryPrefix = result.directoryPrefix
            timedOutKeepingContent = false
            hasRead = true
            fileDiff.closeIfCheckoutChanged(to: result.changes.checkout)
        } catch is CancellationError, TransportError.cancelled {
            // Left mid-read: nothing from it is shown, and the next
            // appearance reads again.
        } catch let error as ChangesReadError {
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
            hasRead = true
            if error == .gitTimedOut, case .loaded = phase {
                timedOutKeepingContent = true
            } else {
                timedOutKeepingContent = false
                directoryPrefix = Data()
                phase = error == .gitTimedOut ? .timedOut : .failed(error.presentation.explanation)
            }
        } catch {
            hasRead = true
            timedOutKeepingContent = false
            directoryPrefix = Data()
            phase = .failed(error.localizedDescription)
        }
    }
}
