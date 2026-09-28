import Foundation
import Testing

@testable import Heeler

@Suite("File patch transport seam")
struct FilePatchTransportSeamTests {
    @Test func aTransportWithoutGitReportsFilePatchesUnavailable() async {
        let transport = FakeTransport(
            pingResult: .success(ServerInfo(version: "0.9.0", protocolVersion: 22)))
        let request = FilePatchRequest(
            topLevel: Data("/home/dev/src/app".utf8),
            path: Data("source.swift".utf8), isUntracked: false)

        await #expect(throws: ChangesReadError.unavailable) {
            _ = try await transport.readFilePatch(request)
        }
    }
}
