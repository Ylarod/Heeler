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
    /// Recorded with /bin/sh -s, Apple Git 2.54.0, nonce F00D and the
    /// Changes script's exact neutralizing options in an isolated scratch
    /// home; the home path is rewritten to /home/dev.
    static let failureOutsideRepository = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover rc=128

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin
        fatal: not a git repository (or any of the parent directories): .git

        __HEELER_GIT_F00D__ discover end

        """.utf8))

    /// Recorded with /bin/sh -s, Apple Git 2.54.0, nonce F00D and the
    /// Changes script's exact neutralizing options in an isolated scratch
    /// home; the home path is rewritten to /home/dev.
    static let failureDirectoryMissing = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover rc=128

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin
        fatal: cannot change to '/home/dev/gone': No such file or directory

        __HEELER_GIT_F00D__ discover end

        """.utf8))

    /// Recorded with /bin/sh -s, Apple Git 2.54.0, nonce F00D and the
    /// Changes script's exact neutralizing options in an isolated scratch
    /// home; the home path is rewritten to /home/dev.
    static let failureBare = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover rc=128

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin
        fatal: this operation must be run in a work tree

        __HEELER_GIT_F00D__ discover end

        """.utf8))

    /// Recorded with /bin/sh -s, Apple Git 2.54.0, nonce F00D and the
    /// Changes script's exact neutralizing options in an isolated scratch
    /// home; the home path is rewritten to /home/dev.
    /// Different ownership was simulated with GIT_TEST_ASSUME_DIFFERENT_OWNER=1.
    static let failureOwnership = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover rc=128

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin
        fatal: detected dubious ownership in repository at '/home/dev/repo'
        To add an exception for this directory, call:

        \tgit config --global --add safe.directory /home/dev/repo

        __HEELER_GIT_F00D__ discover end

        """.utf8))

    /// Recorded with /bin/sh -s, Apple Git 2.54.0, nonce F00D and the
    /// Changes script's exact neutralizing options in an isolated scratch
    /// home; the home path is rewritten to /home/dev.
    static let failureBadConfig = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover rc=128

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin
        fatal: bad config line 1 in file .git/config

        __HEELER_GIT_F00D__ discover end

        """.utf8))

    /// Source-derived, not a live old-git capture: git 2.30.3 through 2.37
    /// used "unsafe repository" rather than "detected dubious ownership".
    /// https://github.com/git/git/blob/v2.37.0/setup.c
    static let failureLegacyOwnership = failureReplacingSection(
        "discover", in: plain, status: 128,
        messages: "fatal: unsafe repository ('/home/dev/repo' is owned by someone else)\n")

    /// Source-derived, not captured live: rev-parse before git 2.25 prints
    /// an empty --show-toplevel inside a git directory with a zero status.
    /// The Changes script therefore skips status, numstat and head.
    /// https://github.com/git/git/blob/v2.24.0/builtin/rev-parse.c
    static let failureOldEmptyTopLevel = failureReplacingSection(
        "discover", in: failureReplacingSection(
            "version", in: plain, body: Data("git version 2.24.0\n".utf8)),
        body: Data("\n\n/home/dev/bare\n.\n".utf8))
}
