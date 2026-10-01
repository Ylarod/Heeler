import Foundation
import Observation

/// The status fan-out follows only the opening Agent. Other Agents in the
/// same Checkout do not drive freshness in v1.
@MainActor
@Observable
final class ChangesAutoRefresh {
    var status: AgentStatus?
    var readWasWhileWorking = false
    @ObservationIgnored var readSawWorking = false
    @ObservationIgnored var hasBaseline = false
    @ObservationIgnored var pending = false
    @ObservationIgnored var statusTask: Task<Void, Never>?
    @ObservationIgnored var statusID = UUID()
    @ObservationIgnored var debounce: Task<Void, Never>?
    @ObservationIgnored var debounceID = UUID()
    @ObservationIgnored let agentStatus: (@MainActor () -> AsyncStream<ConsoleStore.AgentStatusUpdate>)?
    @ObservationIgnored let sleep: @Sendable (Duration) async throws -> Void

    init(
        agentStatus: (@MainActor () -> AsyncStream<ConsoleStore.AgentStatusUpdate>)?,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.agentStatus = agentStatus
        self.sleep = sleep
    }

    deinit {
        statusTask?.cancel()
        debounce?.cancel()
    }
}

extension ChangesStore {
    /// An Agents list row waits this long before its first read, so
    /// scrolling past Agents quickly costs the Host no git exec.
    static let appearanceSettle: Duration = .milliseconds(300)

    /// Worktree Changes' SwiftUI task owns this across both the list and an
    /// open diff. A fresh appearance gets a fresh stream; its first value is
    /// always a baseline.
    func followAgentStatus() async {
        guard !Task.isCancelled else { return }
        startFollowingAgentStatus()
        guard let task = autoRefresh.statusTask else { return }
        let id = autoRefresh.statusID
        defer {
            if autoRefresh.statusID == id { cancel() }
        }
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Also start on appear so a store used without a hosted view consumes
    /// the opening status. The loop never retains the store across an await.
    func startFollowingAgentStatus() {
        guard !Task.isCancelled else { return }
        if let task = autoRefresh.statusTask, !task.isCancelled { return }
        autoRefresh.statusID = UUID()
        autoRefresh.hasBaseline = false
        let stream = autoRefresh.agentStatus?() ?? AsyncStream { _ in }
        autoRefresh.statusTask = Task { [weak self] in
            for await update in stream {
                guard !Task.isCancelled else { return }
                self?.receiveAgentStatus(update.status)
            }
        }
    }

    /// The factory yields the current status before the consumer runs, and
    /// taking that buffered value suspends once. Give the baseline turns to
    /// land before the first read. A stream with nothing buffered stays
    /// unpublished; this does not wait for a later transition.
    func applyBufferedOpeningStatus() async {
        guard autoRefresh.agentStatus != nil, !autoRefresh.hasBaseline else { return }
        for _ in 0..<64 where !autoRefresh.hasBaseline {
            await Task.yield()
        }
    }

    private func receiveAgentStatus(_ status: AgentStatus?) {
        let previous = autoRefresh.status
        autoRefresh.status = status
        if status == .working {
            // Once editing starts, the displayed snapshot stays suspect until
            // a read that never overlaps Working succeeds.
            autoRefresh.readWasWhileWorking = true
            if activeRead != nil { autoRefresh.readSawWorking = true }
        }
        guard autoRefresh.hasBaseline else {
            autoRefresh.hasBaseline = true
            return
        }
        guard previous == .working, let status, status != .working else { return }
        autoRefresh.pending = true
        autoRefresh.debounce?.cancel()
        let id = UUID()
        autoRefresh.debounceID = id
        let sleep = autoRefresh.sleep
        autoRefresh.debounce = Task { [weak self] in
            do {
                try await sleep(.milliseconds(300))
                try Task.checkCancellation()
            } catch { return }
            guard let self, self.autoRefresh.debounceID == id else { return }
            self.autoRefresh.debounce = nil
            self.runPendingAutomaticRefresh()
        }
    }

    func runPendingAutomaticRefresh() {
        guard autoRefresh.pending, autoRefresh.debounce == nil, activeRead == nil,
            defersAutomaticRefresh?() != true
        else { return }
        autoRefresh.pending = false
        // No strong store capture until the bounded read starts.
        autoRefresh.debounce = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            self.autoRefresh.debounce = nil
            await self.refresh(automatic: true)
        }
    }

    /// Back from Changes of this Checkout, which read in this store's
    /// place. When their last read answered every exit from Working, the
    /// Agent is still in their Checkout, and Back adopted it, the waiting
    /// refresh is done; otherwise it runs where the Agent is now, or waits
    /// for a row to show it. Both stores follow the same Agent's status, so
    /// the shown one had every exit this one waited on.
    func resumeAutomaticRefresh(after other: ChangesStore) {
        guard autoRefresh.pending else { return }
        if other.hasAnsweredEveryWorkingExit, readAt != nil, readAt == other.readAt,
            readsSameCheckout(as: other)
        {
            autoRefresh.pending = false
        } else {
            runPendingAutomaticRefresh()
        }
    }

    /// Nothing waits or runs, and the last read succeeded in full.
    private var hasAnsweredEveryWorkingExit: Bool {
        guard case .loaded = phase else { return false }
        return !autoRefresh.pending && autoRefresh.debounce == nil && activeRead == nil
            && !timedOutKeepingContent
    }

    func dropPendingAutomaticRefresh() {
        autoRefresh.pending = false
        autoRefresh.debounceID = UUID()
        autoRefresh.debounce?.cancel()
        autoRefresh.debounce = nil
    }

    /// The Agents list's reads for a row's totals: one once the row has
    /// settled, then one for each exit from Working, until the caller is
    /// cancelled. Each waits while `defersAutomaticRefresh` says so, as when
    /// no row shows the Agent. No timers: nothing else reads.
    func followForRowTotals() async {
        guard !Task.isCancelled else { return }
        let id = UUID()
        rowFollowID = id
        defer {
            // The list's deinit cancels without stopping first.
            if rowFollowID == id { stopFollowingForRowTotals() }
        }
        startFollowingAgentStatus()
        // The baseline lands before the read, as it does for `appear()`.
        await applyBufferedOpeningStatus()
        do {
            try await autoRefresh.sleep(Self.appearanceSettle)
        } catch {
            return
        }
        guard !Task.isCancelled, rowFollowID == id else { return }
        // Closed Changes may have handed over a read in the meantime.
        if readAt == nil {
            autoRefresh.pending = true
            runPendingAutomaticRefresh()
        }
        guard let status = autoRefresh.statusTask else { return }
        await withTaskCancellationHandler {
            await status.value
        } onCancel: {
            status.cancel()
        }
    }

    /// The Agent left the catalog. A read still queued at the Host gate is
    /// dropped, but one that git is already running keeps the gate until it
    /// answers: the remote process cannot be stopped, so the next read
    /// queues behind it instead of stacking git processes on the Host.
    func stopFollowingForRowTotals() {
        rowFollowID = nil
        autoRefresh.statusID = UUID()
        autoRefresh.statusTask?.cancel()
        autoRefresh.statusTask = nil
        dropPendingAutomaticRefresh()
        if activeRead != nil, !isReadDispatched { cancelRead() }
    }

    /// Back invalidates replies immediately, even if a test transport ignores
    /// cancellation. The gate itself waits for that local call to end.
    func cancel() {
        autoRefresh.statusID = UUID()
        autoRefresh.statusTask?.cancel()
        autoRefresh.statusTask = nil
        dropPendingAutomaticRefresh()
        cancelRead()
        fileDiff.close()
        untrackedDirectories.collapseAll()
    }
}
