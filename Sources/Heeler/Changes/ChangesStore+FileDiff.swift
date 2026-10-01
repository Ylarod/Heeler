import Foundation
import Observation

/// Owns file presentation without making a file read part of list refresh.
@MainActor
@Observable
final class FileDiffPresenter {
    private(set) var current: FileDiffStore?
    @ObservationIgnored private let read:
        @Sendable (FilePatchRequest) async throws -> FilePatch
    @ObservationIgnored private let now: @MainActor () -> Date

    init(
        read: @escaping @Sendable (FilePatchRequest) async throws -> FilePatch,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.read = read
        self.now = now
    }

    func open(_ file: ChangedFile, in checkout: CheckoutLocation) {
        guard FilePatchRequest(file: file, checkout: checkout) != nil else { return }
        if current?.file.id == file.id, current?.checkout.topLevel == checkout.topLevel { return }
        close()
        current = FileDiffStore(file: file, checkout: checkout, read: read, now: now)
    }

    func close() {
        current?.cancel()
        current = nil
    }

    func closeIfCheckoutChanged(to checkout: CheckoutLocation) {
        guard let current, current.checkout.topLevel != checkout.topLevel else { return }
        close()
    }

    func listDidRefresh(_ changes: CheckoutChanges) {
        closeIfCheckoutChanged(to: changes.checkout)
        current?.noteListRefresh(changes)
    }
}

extension ChangesStore {
    /// Expanded untracked-directory children also use this entry point.
    /// A directory itself has no file patch and remains on the list.
    func openDiff(_ file: ChangedFile) {
        guard let checkout else { return }
        fileDiff.open(file, in: checkout)
    }

    func closeDiff() {
        fileDiff.close()
    }
}
