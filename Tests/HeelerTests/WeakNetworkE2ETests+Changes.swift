import Foundation
import Testing

@testable import Heeler

/// Changes over a cellular-like link (#395): an overrun that must stay a
/// Changes failure rather than become a link failure.
extension WeakNetworkE2ETests {
    /// The overrun comes from the Host, not the link: the Checkout's clean
    /// filter, the path git-lfs takes, outlasts the git deadline. Events and
    /// the attached terminal share the connection and must not notice.
    @MainActor
    @Test("a git overrun shows timed out without redialing the Host or rebuilding its terminal")
    func gitOverrunKeepsTheHostConnectionAndItsTerminal() async throws {
        let fixture = try #require(WeakNetworkFixture.current)
        try await fixture.control.reset()
        let environment = fixture.environment
        let seeder = try await HeelerSSHTransport.connect(settings: environment.directSettings())
        defer { Task { try? await seeder.close() } }
        let root = "\"$HOME\"/changes-overrun-" + UUID().uuidString
        let cleanup = Data("{ rm -rf \(root); } </dev/null\n".utf8)
        let seeded = try await seeder.runGitScript(Self.slowFilterCheckoutScript(root: root))
        guard seeded.exitStatus == 0, let topLevel = Self.markedValue("TOP", in: seeded.stdout) else {
            _ = try? await seeder.runGitScript(cleanup)
            Issue.record("seed failed: \(String(decoding: seeded.stderr, as: UTF8.self))")
            return
        }

        try await fixture.control.apply(.degraded)
        let settings = fixture.settings()
        let dials = DialCounter()
        let session = EventsSession(
            subscriptions: [.global(.paneCreated)],
            connect: {
                await dials.record()
                return try await HeelerSSHTransport.connect(settings: settings)
            })
        let statuses = SessionStatusLog()
        let consumer = Task {
            for await update in session.updates {
                if case .status(let status) = update { await statuses.append(status) }
            }
        }
        defer { consumer.cancel() }
        await session.resume()
        try await Self.waitUntil("the degraded link should connect", timeout: .seconds(30)) {
            await statuses.contains(.connected)
        }
        let acceptedBefore = try await fixture.control.stats().acceptedConnections
        let generationBefore = await session.transportGeneration
        let terminal = try await session.withTransport { transport in
            try await transport.attachTerminal(
                TerminalAttachRequest(target: "fixture:git-overrun", cols: 80, rows: 24))
        }
        var terminalOutput = terminal.output.makeAsyncIterator()

        let store = ChangesStore(
            directory: { topLevel },
            read: { request in
                try await session.withTransport { try await $0.readChanges(request) }
            },
            gate: GitExecGate())
        let deadline = SSHTransportSettings.defaultGitExecTimeout
        let started = ContinuousClock.now
        await store.appear()
        let elapsed = started.duration(to: .now)
        #expect(store.phase == .timedOut)
        #expect(elapsed >= deadline && elapsed < deadline + .seconds(5), "timed out after \(elapsed)")
        print("[changes-field] overrun deadline=\(deadline) timed-out-after=\(ChangesFieldCheckout.milliseconds(elapsed))")

        // Stay idle past the remote watchdog and the package's cleanup window
        // before looking: an early request can mask a late invalidation.
        try await Task.sleep(for: .seconds(3))
        let openExecs = try await session.withTransport { transport in
            await (transport as? HeelerSSHTransport)?.ordinarySessionChannelCountForTesting()
        }
        #expect(openExecs == 0, "the watchdog should have ended the git exec")
        #expect(await dials.count == 1, "the Host was redialed")
        #expect(await session.transportGeneration == generationBefore)
        #expect(try await fixture.control.stats().acceptedConnections == acceptedBefore)
        #expect(await !statuses.hasReconnected)

        // The terminal attached before the overrun still carries bytes both ways.
        terminal.send(Data("after-git-overrun\n".utf8))
        var echoed = ""
        while !echoed.contains("GOT:after-git-overrun") {
            let chunk = try #require(try await terminalOutput.next())
            echoed += String(decoding: chunk, as: UTF8.self)
        }
        #expect(try await session.withTransport { try await $0.ping() }.protocolVersion == 17)
        #expect(await dials.count == 1)

        await terminal.end()
        await session.end()
        try await fixture.control.reset()
        #expect(try await seeder.runGitScript(cleanup).exitStatus == 0)
    }

    // MARK: Slow Checkout

    /// `slow.dat` is stat-dirty but unchanged, so status re-hashes it through
    /// its clean filter, which sleeps far past any git deadline.
    private static func slowFilterCheckoutScript(root: String) -> Data {
        Data(
            """
            {
            set -e
            r=\(root)
            mkdir -p "$r/repo"
            cd "$r/repo"
            git init -q .
            git symbolic-ref HEAD refs/heads/main
            printf 'content behind a clean filter\\n' > slow.dat
            git add slow.dat
            git -c user.name=Heeler -c user.email=fixture@heeler.invalid commit -q -m 'Seed the slow Checkout'
            printf 'slow.dat filter=slow\\n' > .gitattributes
            git config filter.slow.clean 'sleep 600; cat'
            touch -t 203001010000 slow.dat
            printf '__FIELD_TOP__=%s\\n' "$(pwd -P)"
            } </dev/null

            """.utf8)
    }

    // MARK: Helpers

    private static func markedValue(_ key: String, in output: Data) -> String? {
        let prefix = "__FIELD_\(key)__="
        return String(decoding: output, as: UTF8.self)
            .split(separator: "\n")
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    private static func waitUntil(
        _ comment: Comment,
        timeout: Duration = .seconds(15),
        condition: @Sendable () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await condition(), comment)
    }

    private actor DialCounter {
        private(set) var count = 0

        func record() { count += 1 }
    }

    private actor SessionStatusLog {
        private var statuses: [EventsSessionStatus] = []

        func append(_ status: EventsSessionStatus) { statuses.append(status) }

        func contains(_ status: EventsSessionStatus) -> Bool { statuses.contains(status) }

        var hasReconnected: Bool {
            statuses.contains { if case .reconnecting = $0 { true } else { false } }
        }
    }
}
