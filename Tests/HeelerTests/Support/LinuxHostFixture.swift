import CryptoKit
import Foundation

@testable import Heeler

/// The opt-in Linux Host that `scripts/verify-changes-linux-host.sh` runs in a
/// local container (#395): Debian git behind OpenSSH, with one account whose
/// login shell is fish and one whose login shell is POSIX sh.
///
/// The script hands its coordinates to the Simulator's launchd environment as
/// `HEELER_LINUX_HOST_E2E_CONFIG`, the way the merge gate hands over its own
/// fixtures. Nothing in CI sets it, so on a machine without Docker the field
/// suite simply has no Linux Hosts to visit.
struct LinuxHostFixture: Sendable {
    struct Account: Sendable, Decodable {
        let username: String
        /// The account's login shell, named for the test's own labels.
        let loginShell: String
    }

    let host: String
    let port: UInt16
    let accounts: [Account]
    let deviceKey: Curve25519.Signing.PrivateKey

    static let current: LinuxHostFixture? = {
        guard
            let encoded = ProcessInfo.processInfo.environment["HEELER_LINUX_HOST_E2E_CONFIG"],
            let data = Data(base64Encoded: encoded),
            let configuration = try? JSONDecoder().decode(Configuration.self, from: data),
            let deviceKey = try? RealSSHFixture.deviceKey(seed: configuration.deviceKeySeed)
        else { return nil }
        return LinuxHostFixture(
            host: configuration.host,
            port: configuration.port,
            accounts: configuration.accounts,
            deviceKey: deviceKey)
    }()

    /// Changes reads need no herdr, so the socket is never dialled.
    func settings(for account: Account) -> SSHTransportSettings {
        SSHTransportSettings(
            host: host,
            port: Int(port),
            username: account.username,
            credentials: .ed25519(deviceKey),
            hostKeyPolicy: HostKeyPolicy(knownHosts: InMemoryKnownHostsStore()) { _ in true },
            socket: .absolutePath("/nonexistent/heeler-linux-host.sock"))
    }

    private struct Configuration: Decodable {
        let host: String
        let port: UInt16
        let accounts: [Account]
        let deviceKeySeed: String
    }
}
