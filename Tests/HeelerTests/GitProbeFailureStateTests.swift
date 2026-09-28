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

    @Test func discoveryFailuresKeepTheirDistinctMeanings() {
        #expect(Self.failure(GitProbeRecordings.failureOutsideRepository) == .notAGitWorkingTree)
        #expect(Self.failure(GitProbeRecordings.failureBare) == .notAGitWorkingTree)
        #expect(Self.failure(GitProbeRecordings.gitdir) == .notAGitWorkingTree)
        #expect(Self.failure(GitProbeRecordings.failureOldEmptyTopLevel) == .notAGitWorkingTree)
        #expect(Self.failure(GitProbeRecordings.failureDirectoryMissing) == .directoryMissing)
        #expect(Self.failure(GitProbeRecordings.failureOwnership) == .notOwnedByAccount)
        #expect(Self.failure(GitProbeRecordings.failureLegacyOwnership) == .notOwnedByAccount)
        #expect(Self.failure(GitProbeRecordings.failureBadConfig)
            == .gitFailed("fatal: bad config line 1 in file .git/config"))
    }

    @Test func permissionDeniedDoesNotClaimTheDirectoryIsMissing() {
        let message = "fatal: cannot change to '/home/dev/private': Permission denied"
        let recording = GitProbeRecordings.failureReplacingSection(
            "discover", in: GitProbeRecordings.plain, status: 128,
            messages: "\n\(message)\nhint: more detail\n")
        #expect(Self.failure(recording) == .gitFailed(message))
    }

    @Test(arguments: ["discover", "status", "numstat", "head"])
    func laterCommandFailuresAreAlsoClassified(section: String) {
        let missing = GitProbeRecordings.failureReplacingSection(
            section, in: GitProbeRecordings.clean, status: 127,
            messages: "sh: git: not found\n")
        #expect(Self.failure(missing) == .gitMissing)
        let denied = GitProbeRecordings.failureReplacingSection(
            section, in: GitProbeRecordings.clean, status: 128,
            messages: "fatal: unable to read tree object\nhint: ignored second line\n")
        #expect(Self.failure(denied) == .gitFailed("fatal: unable to read tree object"))
    }

    @Test func missingStatusAfterSuccessfulDiscoveryIsIncomplete() {
        let marker = "__HEELER_GIT_F00D__"
        var recording = GitProbeRecordings.clean
        let begin = recording.stdout.range(of: Data("\n\(marker) status begin\n".utf8))!
        let end = recording.stdout.range(of: Data("\n\(marker) status rc=0\n".utf8))!
        recording.stdout.removeSubrange(begin.lowerBound..<end.upperBound)
        #expect(Self.failure(recording) == .incomplete)
    }

    @Test(arguments: ["version", "home", "discover", "status", "numstat", "head"])
    func everyFramedStatusIsRequired(section: String) {
        let stdout = String(decoding: GitProbeRecordings.clean.stdout, as: UTF8.self)
            .replacingOccurrences(of: "\n__HEELER_GIT_F00D__ \(section) rc=0\n", with: "\n")
        #expect(Self.failure((Data(stdout.utf8), GitProbeRecordings.clean.stderr)) == .incomplete)
    }

    @Test func theFinalMarkerIsRequiredEvenAfterSuccessfulCommands() {
        let stdout = String(decoding: GitProbeRecordings.clean.stdout, as: UTF8.self)
            .replacingOccurrences(of: "\n__HEELER_GIT_F00D__ done\n", with: "\n")
        #expect(Self.failure((Data(stdout.utf8), GitProbeRecordings.clean.stderr)) == .incomplete)
    }
}
