import Foundation
import Observation

/// Which untracked directories are expanded, and what their listing returned.
/// A successful Changes read drops every listing still in flight. Collapsing
/// one directory drops only that directory's listing.
@MainActor
@Observable
final class UntrackedDirectoryExpansions {
    enum Expansion: Equatable {
        case loading
        case loaded(UntrackedDirectoryListing)
        case failed(String)
    }

    @ObservationIgnored private let list:
        @Sendable (UntrackedDirectoryRequest) async throws -> UntrackedDirectoryListing
    /// Bumped only by ``collapseAll()``. An individual toggle does not
    /// invalidate a listing of a different directory.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var nextRequestID = 0
    /// The listing each directory is waiting on. Nil after that directory
    /// collapses, so a late result cannot fill a newer open.
    @ObservationIgnored private var requestIDs: [Data: Int] = [:]
    private(set) var expansions: [Data: Expansion] = [:]

    init(
        list: @escaping @Sendable (UntrackedDirectoryRequest) async throws ->
            UntrackedDirectoryListing
    ) {
        self.list = list
    }

    func expansion(for directory: Data) -> Expansion? {
        expansions[directory]
    }

    /// Drops every expansion. A listing that then lands is ignored.
    func collapseAll() {
        expansions = [:]
        requestIDs = [:]
        generation += 1
    }

    /// Expands `directory`, or collapses it when it is already open.
    /// Collapsing this directory leaves every other listing alone.
    func toggle(_ directory: Data, topLevel: Data) async {
        if expansions[directory] != nil {
            expansions.removeValue(forKey: directory)
            requestIDs[directory] = nil
            return
        }
        let started = generation
        nextRequestID += 1
        let requestID = nextRequestID
        requestIDs[directory] = requestID
        expansions[directory] = .loading
        let request = UntrackedDirectoryRequest(topLevel: topLevel, directory: directory)
        do {
            let listing = try await list(request)
            try Task.checkCancellation()
            guard accepts(directory, started: started, requestID: requestID) else { return }
            expansions[directory] = .loaded(listing)
        } catch is CancellationError, TransportError.cancelled {
            guard accepts(directory, started: started, requestID: requestID) else { return }
            expansions.removeValue(forKey: directory)
        } catch {
            guard accepts(directory, started: started, requestID: requestID) else { return }
            expansions[directory] = .failed(Self.message(for: error))
        }
    }

    /// True when this listing is still the one the directory is waiting on.
    private func accepts(_ directory: Data, started: Int, requestID: Int) -> Bool {
        started == generation
            && requestIDs[directory] == requestID
            && expansions[directory] == .loading
    }

    private static func message(for error: any Error) -> String {
        if let error = error as? ChangesReadError { return error.message }
        if let error = error as? TransportError { return error.presentation.explanation }
        return error.localizedDescription
    }
}

extension ChangesStore {
    /// Lists the files inside an untracked directory, or collapses it.
    func toggleDirectory(_ file: ChangedFile) async {
        guard let topLevel = checkout?.topLevel else { return }
        await untrackedDirectories.toggle(file.path, topLevel: topLevel)
    }
}
