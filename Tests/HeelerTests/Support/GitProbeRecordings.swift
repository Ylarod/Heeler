import Foundation

/// Output of `GitProbe.changesScript(directory:nonce:)` recorded with the
/// nonce `F00D` from `/bin/sh -s` and Apple Git 2.54.0, the CI fixture's
/// combination, against scratch repositories. The recording home
/// directory was rewritten to `/home/dev`; nothing else was edited.
enum GitProbeRecordings {
    static let nonce = "F00D"

    /// A main checkout with every hostile file name from the research, a staged
    /// rename, a conflict, untracked files, stat-dirty tracked files and a
    /// configuration whose fsmonitor, hooks, external diff and textconv would
    /// each write a marker file.
    static let hostile = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/app

        /home/dev/src/app/.git
        .git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid a7d75683c107bbe72aad2574b0ba0e6c47629e08\u{0}# branch.head main\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 $HOME.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 *.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 --\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 -dash.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 [ab].txt\u{0}1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 3e757656cf36eca53338e520d134963a44f793f8 added.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 bang!.txt\u{0}1 .M N... 100644 100644 100644 0f49c4ae77b43dff338093c78e009676e7e308ba 0f49c4ae77b43dff338093c78e009676e7e308ba bin.dat\u{0}1 .D N... 100644 100644 000000 286c5f5776916d7d7d5849988ca9d83e722cf9c2 286c5f5776916d7d7d5849988ca9d83e722cf9c2 gone.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 line
        break.txt\u{0}2 R. N... 100644 100644 100644 3367afdbbf91e638efe983616377c60477cc6612 3367afdbbf91e638efe983616377c60477cc6612 R100 pkg/renamed.txt\u{0}old/name.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 quo"te.txt\u{0}1 MM N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 814f4a422927b82f5f8a43f8fab6d3839e3983f2 sp ace.txt\u{0}1 M. N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 814f4a422927b82f5f8a43f8fab6d3839e3983f2 sq'uote.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 tab\tname.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 trail\\\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 two\\\\bs.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 ünï.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 中文.txt\u{0}u UU N... 100644 100644 100644 100644 df967b96a579e45a18b8251732d16804b2e56a55 ba2906d0666cf726c7eaadd2cd3db615dedfdf3a 2299c37978265a95cbe835a4b0f0bbf15aad5549 conflict.txt\u{0}? newdir/\u{0}? untracked.txt\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin
        1\t0\t$HOME.txt\u{0}1\t0\t*.txt\u{0}1\t0\t--\u{0}1\t0\t-dash.txt\u{0}1\t0\t[ab].txt\u{0}1\t0\tadded.txt\u{0}1\t0\tbang!.txt\u{0}-\t-\tbin.dat\u{0}4\t0\tconflict.txt\u{0}0\t1\tgone.txt\u{0}1\t0\tline
        break.txt\u{0}0\t0\t\u{0}old/name.txt\u{0}pkg/renamed.txt\u{0}1\t0\tquo"te.txt\u{0}2\t0\tsp ace.txt\u{0}1\t0\tsq'uote.txt\u{0}1\t0\ttab\tname.txt\u{0}1\t0\ttrail\\\u{0}1\t0\ttwo\\\\bs.txt\u{0}1\t0\tünï.txt\u{0}1\t0\t中文.txt\u{0}
        __HEELER_GIT_F00D__ numstat rc=0

        __HEELER_GIT_F00D__ head begin
        1790587800 Main edit to "conflict.txt"

        __HEELER_GIT_F00D__ head rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover end

        __HEELER_GIT_F00D__ status begin

        __HEELER_GIT_F00D__ status end

        __HEELER_GIT_F00D__ numstat begin

        __HEELER_GIT_F00D__ numstat end

        __HEELER_GIT_F00D__ head begin

        __HEELER_GIT_F00D__ head end

        """.utf8))

    /// The same Checkout read from its `pkg` subdirectory.
    static let subdir = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/app
        pkg/
        /home/dev/src/app/.git
        ../.git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid a7d75683c107bbe72aad2574b0ba0e6c47629e08\u{0}# branch.head main\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 $HOME.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 *.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 --\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 -dash.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 [ab].txt\u{0}1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 3e757656cf36eca53338e520d134963a44f793f8 added.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 bang!.txt\u{0}1 .M N... 100644 100644 100644 0f49c4ae77b43dff338093c78e009676e7e308ba 0f49c4ae77b43dff338093c78e009676e7e308ba bin.dat\u{0}1 .D N... 100644 100644 000000 286c5f5776916d7d7d5849988ca9d83e722cf9c2 286c5f5776916d7d7d5849988ca9d83e722cf9c2 gone.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 line
        break.txt\u{0}2 R. N... 100644 100644 100644 3367afdbbf91e638efe983616377c60477cc6612 3367afdbbf91e638efe983616377c60477cc6612 R100 pkg/renamed.txt\u{0}old/name.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 quo"te.txt\u{0}1 MM N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 814f4a422927b82f5f8a43f8fab6d3839e3983f2 sp ace.txt\u{0}1 M. N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 814f4a422927b82f5f8a43f8fab6d3839e3983f2 sq'uote.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 tab\tname.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 trail\\\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 two\\\\bs.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 ünï.txt\u{0}1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 中文.txt\u{0}u UU N... 100644 100644 100644 100644 df967b96a579e45a18b8251732d16804b2e56a55 ba2906d0666cf726c7eaadd2cd3db615dedfdf3a 2299c37978265a95cbe835a4b0f0bbf15aad5549 conflict.txt\u{0}? newdir/\u{0}? untracked.txt\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin
        1\t0\t$HOME.txt\u{0}1\t0\t*.txt\u{0}1\t0\t--\u{0}1\t0\t-dash.txt\u{0}1\t0\t[ab].txt\u{0}1\t0\tadded.txt\u{0}1\t0\tbang!.txt\u{0}-\t-\tbin.dat\u{0}4\t0\tconflict.txt\u{0}0\t1\tgone.txt\u{0}1\t0\tline
        break.txt\u{0}0\t0\t\u{0}old/name.txt\u{0}pkg/renamed.txt\u{0}1\t0\tquo"te.txt\u{0}2\t0\tsp ace.txt\u{0}1\t0\tsq'uote.txt\u{0}1\t0\ttab\tname.txt\u{0}1\t0\ttrail\\\u{0}1\t0\ttwo\\\\bs.txt\u{0}1\t0\tünï.txt\u{0}1\t0\t中文.txt\u{0}
        __HEELER_GIT_F00D__ numstat rc=0

        __HEELER_GIT_F00D__ head begin
        1790587800 Main edit to "conflict.txt"

        __HEELER_GIT_F00D__ head rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover end

        __HEELER_GIT_F00D__ status begin

        __HEELER_GIT_F00D__ status end

        __HEELER_GIT_F00D__ numstat begin

        __HEELER_GIT_F00D__ numstat end

        __HEELER_GIT_F00D__ head begin

        __HEELER_GIT_F00D__ head end

        """.utf8))

    /// A linked Worktree detached at the first commit, read from `src`.
    static let worktree = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/app-wt
        src/
        /home/dev/src/app/.git/worktrees/app-wt
        /home/dev/src/app/.git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid 4f879541e80f832b63d184572f077fb9d5075969\u{0}# branch.head (detached)\u{0}1 .M N... 100644 100644 100644 f7fb5910a6050ac2cd2cc4563a8651c523a2c526 f7fb5910a6050ac2cd2cc4563a8651c523a2c526 src/main.c\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin
        1\t0\tsrc/main.c\u{0}
        __HEELER_GIT_F00D__ numstat rc=0

        __HEELER_GIT_F00D__ head begin
        1790503200 Seed the fixture repository

        __HEELER_GIT_F00D__ head rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover end

        __HEELER_GIT_F00D__ status begin

        __HEELER_GIT_F00D__ status end

        __HEELER_GIT_F00D__ numstat begin

        __HEELER_GIT_F00D__ numstat end

        __HEELER_GIT_F00D__ head begin

        __HEELER_GIT_F00D__ head end

        """.utf8))

    /// A Checkout with no uncommitted changes.
    static let clean = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/clean

        /home/dev/src/clean/.git
        .git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid a82fe1563bfbb15f630764d94d63bc0f6271768c\u{0}# branch.head main\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin

        __HEELER_GIT_F00D__ numstat rc=0

        __HEELER_GIT_F00D__ head begin
        1790503200 Clean tree

        __HEELER_GIT_F00D__ head rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover end

        __HEELER_GIT_F00D__ status begin

        __HEELER_GIT_F00D__ status end

        __HEELER_GIT_F00D__ numstat begin

        __HEELER_GIT_F00D__ numstat end

        __HEELER_GIT_F00D__ head begin

        __HEELER_GIT_F00D__ head end

        """.utf8))

    /// A Checkout without commits: one staged file, one untracked.
    static let unborn = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/fresh

        /home/dev/src/fresh/.git
        .git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid (initial)\u{0}# branch.head main\u{0}1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 b4785957bc986dc39c629de9fac9df46972c00fc staged.txt\u{0}? loose.txt\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin
        1\t0\tstaged.txt\u{0}
        __HEELER_GIT_F00D__ numstat rc=0

        __HEELER_GIT_F00D__ head begin

        __HEELER_GIT_F00D__ head rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover end

        __HEELER_GIT_F00D__ status begin

        __HEELER_GIT_F00D__ status end

        __HEELER_GIT_F00D__ numstat begin

        __HEELER_GIT_F00D__ numstat end

        __HEELER_GIT_F00D__ head begin

        __HEELER_GIT_F00D__ head end

        """.utf8))

    /// A SHA-256 repository with one modified file.
    static let sha256 = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/sha

        /home/dev/src/sha/.git
        .git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid 96cb513b57469caefccadcc0cd6e2ddfcf9697b779213889cb888f601223f79e\u{0}# branch.head main\u{0}1 .M N... 100644 100644 100644 f8625e43f9e04f24291f77cdbe4c71b3c2a3b0003f60419b3ed06a058d766c8b f8625e43f9e04f24291f77cdbe4c71b3c2a3b0003f60419b3ed06a058d766c8b a.txt\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin
        1\t0\ta.txt\u{0}
        __HEELER_GIT_F00D__ numstat rc=0

        __HEELER_GIT_F00D__ head begin
        1790503200 SHA-256 root

        __HEELER_GIT_F00D__ head rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover end

        __HEELER_GIT_F00D__ status begin

        __HEELER_GIT_F00D__ status end

        __HEELER_GIT_F00D__ numstat begin

        __HEELER_GIT_F00D__ numstat end

        __HEELER_GIT_F00D__ head begin

        __HEELER_GIT_F00D__ head end

        """.utf8))

    /// A directory outside any git working tree.
    static let plain = (
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

    /// The hostile Checkout's own `.git` directory.
    static let gitdir = (
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

    /// The clean Checkout behind a login shell that prints to both streams.
    static let noise = (
        stdout: Data(
        """
        Last login: Mon Sep 28 on ttys001

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/clean

        /home/dev/src/clean/.git
        .git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid a82fe1563bfbb15f630764d94d63bc0f6271768c\u{0}# branch.head main\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin

        __HEELER_GIT_F00D__ numstat rc=0

        __HEELER_GIT_F00D__ head begin
        1790503200 Clean tree

        __HEELER_GIT_F00D__ head rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """
        bash: warning: setlocale: LC_ALL: cannot change locale

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover end

        __HEELER_GIT_F00D__ status begin

        __HEELER_GIT_F00D__ status end

        __HEELER_GIT_F00D__ numstat begin

        __HEELER_GIT_F00D__ numstat end

        __HEELER_GIT_F00D__ head begin

        __HEELER_GIT_F00D__ head end

        """.utf8))

    /// An unstaged move whose new path was marked with `git add -N`
    /// (`mv a.txt b.txt; git add -N b.txt`): git pairs the move as a
    /// working-tree rename, `2 .R`.
    static let intentToAddMove = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/moved

        /home/dev/src/moved/.git
        .git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid 73cf7c33a6e24d09ace7b650d2782608861b5ddc\u{0}# branch.head main\u{0}2 .R N... 100644 100644 100644 4cb29ea38f70d7c61b2a3a25b02e3bdf44905402 4cb29ea38f70d7c61b2a3a25b02e3bdf44905402 R100 b.txt\u{0}a.txt\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin
        0\t0\t\u{0}a.txt\u{0}b.txt\u{0}
        __HEELER_GIT_F00D__ numstat rc=0

        __HEELER_GIT_F00D__ head begin
        1790503200 Add a.txt

        __HEELER_GIT_F00D__ head rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover end

        __HEELER_GIT_F00D__ status begin

        __HEELER_GIT_F00D__ status end

        __HEELER_GIT_F00D__ numstat begin

        __HEELER_GIT_F00D__ numstat end

        __HEELER_GIT_F00D__ head begin

        __HEELER_GIT_F00D__ head end

        """.utf8))

    /// A staged rename followed by an unstaged move of its new path marked
    /// with `git add -N` (`git mv a.txt b.txt; mv b.txt c.txt; git add -N
    /// c.txt`): a `2 R.` record for b.txt and a `2 .R` record moving it on.
    static let intentToAddMoveAfterStagedRename = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/restaged

        /home/dev/src/restaged/.git
        .git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid 73cf7c33a6e24d09ace7b650d2782608861b5ddc\u{0}# branch.head main\u{0}2 R. N... 100644 100644 100644 4cb29ea38f70d7c61b2a3a25b02e3bdf44905402 4cb29ea38f70d7c61b2a3a25b02e3bdf44905402 R100 b.txt\u{0}a.txt\u{0}2 .R N... 100644 100644 100644 4cb29ea38f70d7c61b2a3a25b02e3bdf44905402 4cb29ea38f70d7c61b2a3a25b02e3bdf44905402 R100 c.txt\u{0}b.txt\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin
        0\t0\t\u{0}a.txt\u{0}c.txt\u{0}
        __HEELER_GIT_F00D__ numstat rc=0

        __HEELER_GIT_F00D__ head begin
        1790503200 Add a.txt

        __HEELER_GIT_F00D__ head rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ version begin

        __HEELER_GIT_F00D__ version end

        __HEELER_GIT_F00D__ home begin

        __HEELER_GIT_F00D__ home end

        __HEELER_GIT_F00D__ discover begin

        __HEELER_GIT_F00D__ discover end

        __HEELER_GIT_F00D__ status begin

        __HEELER_GIT_F00D__ status end

        __HEELER_GIT_F00D__ numstat begin

        __HEELER_GIT_F00D__ numstat end

        __HEELER_GIT_F00D__ head begin

        __HEELER_GIT_F00D__ head end

        """.utf8))

}
