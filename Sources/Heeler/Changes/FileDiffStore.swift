import Foundation
import Observation

/// One open file's in-memory patch, independent of the Changes list's reads.
@MainActor
@Observable
final class FileDiffStore {
    enum Phase: Equatable {
        case loading
        case loaded(FilePatch)
        case failed(String)
    }

    enum Truncation: Equatable {
        case none
        case canLoadMore
        case tooLarge
    }

    let file: ChangedFile
    let checkout: CheckoutLocation
    private(set) var phase: Phase = .loading
    private(set) var isRefreshing = false
    private(set) var readAt: Date?
    /// A refresh failure accompanies the earlier patch instead of replacing it.
    private(set) var refreshError: String?
    private var loadedLimit: FilePatchRequest.Limit = .initial

    var truncation: Truncation {
        guard case .loaded(let patch) = phase, patch.isTruncated else { return .none }
        return loadedLimit == .initial ? .canLoadMore : .tooLarge
    }

    /// Kept in the model so the file's line counts can be appended here.
    var tooLargeMessage: String { "This file is too large to display in full." }

    @ObservationIgnored private let read:
        @Sendable (FilePatchRequest) async throws -> FilePatch
    @ObservationIgnored private var hasRead = false
    @ObservationIgnored private var activeRead: Task<FilePatch, any Error>?
    @ObservationIgnored private var readID = UUID()

    init(
        file: ChangedFile, checkout: CheckoutLocation,
        read: @escaping @Sendable (FilePatchRequest) async throws -> FilePatch
    ) {
        self.file = file
        self.checkout = checkout
        self.read = read
    }

    deinit {
        activeRead?.cancel()
    }

    func appear() async {
        guard !hasRead else { return }
        await refresh()
    }

    /// A pull reads this file alone, leaving the Checkout list untouched.
    /// It starts at the initial cap again, even after Load More.
    func refresh() async {
        await performRead(limit: .initial)
    }

    func loadMore() async {
        guard truncation == .canLoadMore else { return }
        await performRead(limit: .extended)
    }

    /// Closing or replacing the file cancels its request and invalidates any
    /// reply from a Transport that finishes after cancellation.
    func cancel() {
        readID = UUID()
        activeRead?.cancel()
        activeRead = nil
        isRefreshing = false
    }

    private func performRead(limit: FilePatchRequest.Limit) async {
        guard activeRead == nil, !Task.isCancelled,
            let request = FilePatchRequest(file: file, checkout: checkout, limit: limit)
        else { return }
        let id = UUID()
        readID = id
        let task = Task { [read] in try await read(request) }
        activeRead = task
        refreshError = nil
        if case .loaded = phase { isRefreshing = true }
        defer {
            if readID == id {
                activeRead = nil
                isRefreshing = false
            }
        }
        do {
            let patch = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard readID == id else { return }
            phase = .loaded(patch)
            loadedLimit = limit
            readAt = Date()
            hasRead = true
        } catch is CancellationError, TransportError.cancelled {
            // A cancelled first read remains eligible for the next appearance.
        } catch {
            guard readID == id, !Task.isCancelled else { return }
            hasRead = true
            let message: String
            if let error = error as? ChangesReadError {
                message = error.message
            } else if let error = error as? TransportError {
                message = error.presentation.explanation
            } else {
                message = error.localizedDescription
            }
            if case .loaded = phase { refreshError = message } else { phase = .failed(message) }
        }
    }
}
