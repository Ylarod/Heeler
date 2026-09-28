import Foundation
import Observation

/// Which untracked directories are expanded, and what their listing returned.
/// One Changes read collapsing them drops a listing that is still in flight.
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
    @ObservationIgnored private var generation = 0
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
        generation += 1
    }

    /// Expands `directory`, or collapses it when it is already open.
    func toggle(_ directory: Data, topLevel: Data) async {
        if expansions[directory] != nil {
            expansions.removeValue(forKey: directory)
            generation += 1
            return
        }
        let started = generation
        expansions[directory] = .loading
        let request = UntrackedDirectoryRequest(topLevel: topLevel, directory: directory)
        do {
            let listing = try await list(request)
            try Task.checkCancellation()
            guard started == generation, expansions[directory] == .loading else { return }
            expansions[directory] = .loaded(listing)
        } catch is CancellationError, TransportError.cancelled {
            guard started == generation, expansions[directory] == .loading else { return }
            expansions.removeValue(forKey: directory)
        } catch {
            guard started == generation, expansions[directory] == .loading else { return }
            expansions[directory] = .failed(Self.message(for: error))
        }
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
