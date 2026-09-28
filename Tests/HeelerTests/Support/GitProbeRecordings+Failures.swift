import Foundation

extension GitProbeRecordings {
    /// Synthetic edits of a recorded frame, for version variants, truncation
    /// and signal-loss cases that the current Host cannot produce directly.
    static func failureReplacingSection(
        _ name: String, in recording: (stdout: Data, stderr: Data),
        body: Data = Data(), status: Int32 = 0, messages: String = ""
    ) -> (stdout: Data, stderr: Data) {
        let marker = "__HEELER_GIT_F00D__"
        let begin = Data("\n\(marker) \(name) begin\n".utf8)
        let statusPrefix = Data("\n\(marker) \(name) rc=".utf8)
        var stdout = recording.stdout
        if let start = stdout.range(of: begin),
            let end = stdout.range(of: statusPrefix, in: start.upperBound..<stdout.endIndex),
            let newline = stdout[end.upperBound...].firstIndex(of: 0x0A)
        {
            stdout.replaceSubrange(
                start.upperBound...newline,
                with: body + Data("\n\(marker) \(name) rc=\(status)\n".utf8))
        }
        var stderr = recording.stderr
        if let start = stderr.range(of: begin),
            let end = stderr.range(
                of: Data("\n\(marker) \(name) end\n".utf8),
                in: start.upperBound..<stderr.endIndex)
        {
            stderr.replaceSubrange(start.upperBound..<end.lowerBound, with: Data(messages.utf8))
        }
        return (stdout, stderr)
    }

    /// Source-derived, not a live old-git capture: git before 2.15 rejects
    /// --no-optional-locks. The plain version probe must decide the state.
    static let failureOldOptions = failureReplacingSection(
        "discover", in: plain, status: 129,
        messages: "unknown option: --no-optional-locks\nusage: git [--version] ...\n")

    /// Hand-built shell recording: a missing command returns 127; framing
    /// supplies the status even if the shell's wording varies.
    static let failureGitMissing = failureReplacingSection(
        "version", in: plain, status: 127, messages: "sh: git: command not found\n")

    /// Documentation-derived, not captured live: Apple's developer-tools
    /// installer stub asks for installation when no developer tools exist.
    /// https://it-training.apple.com/compliance/tutorials/course/sec015/
    static let failureDeveloperToolsStub = failureReplacingSection(
        "version", in: plain, status: 1,
        messages: "xcode-select: note: No developer tools were found, requesting install.\n")

    /// Documentation-derived, not captured live: the active developer path
    /// can remain after its Command Line Tools installation was removed.
    /// https://developer.apple.com/forums/thread/673827
    static let failureInvalidDeveloperPath = failureReplacingSection(
        "version", in: plain, status: 1,
        messages: "xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools), missing xcrun at: /Library/Developer/CommandLineTools/usr/bin/xcrun\n")
}
