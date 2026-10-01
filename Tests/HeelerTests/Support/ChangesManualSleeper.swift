import Foundation

/// An injected clock whose deadlines advance only when the test asks.
actor ChangesManualSleeper {
    private(set) var durations: [Duration] = []
    private var sleepers: [Int: CheckedContinuation<Void, any Error>] = [:]

    func sleep(_ duration: Duration) async throws {
        let id = durations.count
        durations.append(duration)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                sleepers[id] = continuation
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func fireAll() {
        let pending = sleepers.values
        sleepers.removeAll()
        for sleeper in pending { sleeper.resume() }
    }

    private func cancel(_ id: Int) {
        sleepers.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}
