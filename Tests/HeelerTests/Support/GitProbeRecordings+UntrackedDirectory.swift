import Foundation

/// Output of the untracked-directory listing, nonce `F00D`, from `/bin/sh -s`
/// and Apple Git 2.54.0. The command is `status --porcelain=v2 -z
/// --untracked-files=all` under GitProbe's neutralizing options, framed by
/// `sec` at the status cap. The environment was `PATH`, `HOME`,
/// `GIT_CONFIG_NOSYSTEM=1` and `GIT_CONFIG_GLOBAL=/dev/null`, so this
/// machine's git configuration is not in the bytes.
extension GitProbeRecordings {
    /// `newdir/` listed with `--untracked-files=all`: hostile names, a nested
    /// repository (`newdir/inner/`), a staged file and a modified tracked file
    /// (both ignored by the parser), and an excluded `skip.log`.
    static let untrackedListing = (
        stdout: Data(
        """
        
        __HEELER_GIT_F00D__ untracked begin
        1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 19d9cc8584ac2c7dcf57d2680375e80f099dc481 newdir/staged.txt\u{0}1 .M N... 100644 100644 100644 93a9e06d23ffb27541048940052c7a076c7a195a 93a9e06d23ffb27541048940052c7a076c7a195a newdir/tracked-inside.txt\u{0}? newdir/$HOME.txt\u{0}? newdir/*.txt\u{0}? newdir/--\u{0}? newdir/-dash.txt\u{0}? newdir/[ab].txt\u{0}? newdir/a.txt\u{0}? newdir/bang!.txt\u{0}? newdir/deep/b.txt\u{0}? newdir/inner/\u{0}? newdir/line
        break.txt\u{0}? newdir/quo"te.txt\u{0}? newdir/sp ace.txt\u{0}? newdir/sq'uote.txt\u{0}? newdir/tab\tname.txt\u{0}? newdir/trail\\\u{0}? newdir/two\\\\bs.txt\u{0}? newdir/ünï.txt\u{0}? newdir/中文.txt\u{0}
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

    /// A staged rename inside `? dir/`, plus an added file and two untracked
    /// files. The type-2 record's original path is the next NUL field
    /// (`? dir/original`), not an untracked record.
    static let untrackedListingRename = (
        stdout: Data(
        """
        
        __HEELER_GIT_F00D__ untracked begin
        1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 78981922613b2afb6025042ff6bd878ac1994e85 ? dir/added.txt\u{0}2 R. N... 100644 100644 100644 dcc27807b20456027b6a152f9756c62360e229d6 dcc27807b20456027b6a152f9756c62360e229d6 R100 ? dir/renamed\u{0}? dir/original\u{0}? ? dir/plain.txt\u{0}? ? dir/untracked\u{0}
        __HEELER_GIT_F00D__ untracked rc=0
        
        __HEELER_GIT_F00D__ done
        
        """.utf8),
        stderr: Data(
        """
        
        __HEELER_GIT_F00D__ untracked begin
        
        __HEELER_GIT_F00D__ untracked end
        
        """.utf8))

}
