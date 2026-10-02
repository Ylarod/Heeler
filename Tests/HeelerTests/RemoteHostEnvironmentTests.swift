import Foundation
import Testing

@testable import Heeler

@Suite struct RemoteHostEnvironmentTests {
    @Test func noisyWindowsProbeUsesUserProfileAndConfig() throws {
        let output = Data("banner\r\n__HEELER_WINDOWS__={\"home\":\"C:\\\\Users\\\\Test User\",\"config\":\"D:\\\\Config\\\\herdr\"}\r\n".utf8)
        let environment = try #require(RemoteHostEnvironment.windows(from: output))
        #expect(environment.home == "C:\\Users\\Test User")
        #expect(try environment.socketPath(for: .namedSession("work")) == "D:\\Config\\herdr\\sessions\\work\\herdr.sock")
        #expect(try environment.socketPath(for: .defaultSession) == "D:\\Config\\herdr\\herdr.sock")
        #expect(try environment.socketPath(for: .absolutePath("E:\\Custom\\herdr.sock")) == "E:\\Custom\\herdr.sock")
    }

    @Test func invalidWindowsHomeOrEndpointIsRefused() {
        #expect(RemoteHostEnvironment.windows(from: Data("__HEELER_WINDOWS__={\"home\":\"relative\",\"config\":\"C:\\\\config\"}".utf8)) == nil)
        let environment = RemoteHostEnvironment.windows(home: "C:\\Users\\user", configDirectory: "C:\\Config\\herdr")
        #expect(throws: TransportError.self) { try environment.socketPath(for: .absolutePath("/tmp/herdr.sock")) }
        #expect(throws: TransportError.self) { try environment.socketPath(for: .namedSession("../work")) }
    }

    @Test func posixEndpointBehaviorIsPreserved() throws {
        let environment = RemoteHostEnvironment.posix(home: "/home/u")
        #expect(try environment.socketPath(for: .namedSession("work")) == "/home/u/.config/herdr/sessions/work/herdr.sock")
        #expect(try environment.socketPath(for: .absolutePath("/tmp/custom.sock")) == "/tmp/custom.sock")
        #expect(!environment.isWindows)
    }

    @Test func encodedCommandPreservesUnicodeAndShellMetacharacters() throws {
        let script = "[Console]::WriteLine('测试 $HOME ` whoami & café')"
        #expect(try decode(PowerShellCommand.encoded(script)) == script)
        let command = PowerShellCommand.herdr(
            arguments: ["terminal", "session", "control", "opaque'$(whoami)"],
            socketPath: "C:\\Users\\Test User\\herdr.sock", location: .namedSession("work"))
        let decoded = try decode(command)
        #expect(decoded.contains("$env:HERDR_SESSION = 'work'"))
        #expect(decoded.contains("Remove-Item Env:HERDR_SOCKET_PATH"))
        #expect(!decoded.contains("$env:HERDR_SOCKET_PATH ="))
        #expect(decoded.contains("'opaque''$(whoami)'"))
        #expect(!command.contains("$(whoami)"))
        let defaultCommand = try decode(PowerShellCommand.herdr(
            arguments: ["remote-api-bridge"], socketPath: "C:\\herdr.sock"))
        #expect(defaultCommand.contains("Remove-Item Env:HERDR_SESSION"))
        #expect(defaultCommand.contains("Remove-Item Env:HERDR_SOCKET_PATH"))
        let customCommand = try decode(PowerShellCommand.herdr(
            arguments: ["remote-api-bridge"], socketPath: "C:/Custom/herdr.sock",
            location: .absolutePath("C:/Custom/herdr.sock")))
        #expect(customCommand.contains("$env:HERDR_SOCKET_PATH = 'C:/Custom/herdr.sock'"))
    }

    @Test func platformFeatureFailuresDoNotReconnect() {
        let error = TransportError.hostFeatureUnavailable(feature: "Changes")
        #expect(!error.isRetryable)
        #expect(error.presentation.detail == "Changes")
    }

    private func decode(_ command: String) throws -> String {
        let encoded = try #require(command.split(separator: " ").last)
        let data = try #require(Data(base64Encoded: String(encoded)))
        return try #require(String(data: data, encoding: .utf16LittleEndian))
    }
}
