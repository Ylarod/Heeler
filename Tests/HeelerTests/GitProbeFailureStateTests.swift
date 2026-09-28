import Foundation
import Testing

@testable import Heeler

@Suite("GitProbe failure states")
struct GitProbeFailureStateTests {
    private static func parse(_ recording: (stdout: Data, stderr: Data)) throws -> CheckoutChangesRead {
        try GitProbe.parseChanges(
            stdout: recording.stdout, stderr: recording.stderr, nonce: GitProbeRecordings.nonce)
    }

    private static func failure(_ recording: (stdout: Data, stderr: Data)) -> ChangesReadError? {
        do {
            _ = try parse(recording)
            return nil
        } catch let error as ChangesReadError {
            return error
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }

    @Test(arguments: [
        "2.17.0", "2.17.1", "2.54.0 (Apple Git-157)", "2.45.2.windows.1",
        "2.43.0.vfs.0.0", "2.50.0.rc1", "3.0.0", "vendor-build",
    ])
    func supportedVersionsAndVendorSuffixesLoad(version: String) throws {
        let recording = GitProbeRecordings.failureReplacingSection(
            "version", in: GitProbeRecordings.clean, body: Data("git version \(version)\n".utf8))
        #expect(try Self.parse(recording).changes.isClean)
    }

    @Test(arguments: ["2.16.6", "2.11.0", "1.9.5", "2.16.6 (Apple Git-95)"])
    func oldVersionsWinOverLaterUnknownOptionErrors(version: String) {
        let recording = GitProbeRecordings.failureReplacingSection(
            "version", in: GitProbeRecordings.failureOldOptions,
            body: Data("git version \(version)\n".utf8))
        #expect(Self.failure(recording) == .gitTooOld(version))
    }

    @Test func gitMissingHasItsOwnState() {
        #expect(Self.failure(GitProbeRecordings.failureGitMissing) == .gitMissing)
    }

    @Test func developerToolsStubsAreGitMissing() {
        #expect(Self.failure(GitProbeRecordings.failureDeveloperToolsStub) == .gitMissing)
        #expect(Self.failure(GitProbeRecordings.failureInvalidDeveloperPath) == .gitMissing)
    }
}
