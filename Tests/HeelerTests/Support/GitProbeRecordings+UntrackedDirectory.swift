import Foundation

/// Output of the untracked-directory listing, nonce `F00D`, from `/bin/sh -s`
/// and Apple Git 2.54.0. The command is `status --porcelain=v2 -z
/// --untracked-files=all` under GitProbe's neutralizing options, framed by
/// `sec` at the status cap. The environment was empty apart from `PATH` and
/// `HOME`, so this machine's git configuration is not in the bytes.
extension GitProbeRecordings {

    /// `newdir/` listed with `--untracked-files=all`: hostile names, a nested
    /// repository (`newdir/inner/`), a staged file and a modified tracked file
    /// (both ignored by the parser), and an excluded `skip.log`.
    static let untrackedListing = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ untracked begin
        1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 587be6b4c3f93f93c489c0111bba5596147a26cb newdir/staged.txt\u{0}1 .M N... 100644 100644 100644 587be6b4c3f93f93c489c0111bba5596147a26cb 587be6b4c3f93f93c489c0111bba5596147a26cb newdir/tracked-inside.txt\u{0}? newdir/$HOME.txt\u{0}? newdir/*.txt\u{0}? newdir/--\u{0}? newdir/-dash.txt\u{0}? newdir/[ab].txt\u{0}? newdir/a.txt\u{0}? newdir/bang!.txt\u{0}? newdir/deep/b.txt\u{0}? newdir/inner/\u{0}? newdir/line
        break.txt\u{0}? newdir/quo"te.txt\u{0}? newdir/sp ace.txt\u{0}? newdir/sq'uote.txt\u{0}? newdir/tab\tname.txt\u{0}? newdir/trail\\\u{0}? newdir/two\\bs.txt\u{0}? newdir/ünï.txt\u{0}? newdir/中文.txt\u{0}
        __HEELER_GIT_F00D__ untracked rc=0

        __HEELER_GIT_F00D__ done
        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ untracked begin

        __HEELER_GIT_F00D__ untracked end
        """.utf8))


    /// Expanding a directory that is its own git repository. Git prints the
    /// directory itself and does not descend.
    static let untrackedListingSeparateRepository = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ untracked begin
        ? nested/\u{0}
        __HEELER_GIT_F00D__ untracked rc=0

        __HEELER_GIT_F00D__ done
        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ untracked begin

        __HEELER_GIT_F00D__ untracked end
        """.utf8))


    /// A directory that is no longer there: empty status, framed exit 0.
    static let untrackedListingEmpty = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ untracked begin

        __HEELER_GIT_F00D__ untracked rc=0

        __HEELER_GIT_F00D__ done
        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ untracked begin

        __HEELER_GIT_F00D__ untracked end
        """.utf8))


    /// The top level from the latest read has gone. The scratch prefix was
    /// rewritten to `/home/dev`; git's framed exit status is 128.
    static let untrackedListingMissingTopLevel = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ untracked begin

        __HEELER_GIT_F00D__ untracked rc=128

        __HEELER_GIT_F00D__ done
        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ untracked begin
        fatal: cannot change to '/home/dev/app/no-such-top': No such file or directory

        __HEELER_GIT_F00D__ untracked end
        """.utf8))


    /// A directory named `[ab]`. Literal pathspecs keep the listing inside it.
    static let untrackedListingLiteral = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ untracked begin
        ? [ab]/c.txt\u{0}
        __HEELER_GIT_F00D__ untracked rc=0

        __HEELER_GIT_F00D__ done
        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ untracked begin

        __HEELER_GIT_F00D__ untracked end
        """.utf8))

}
