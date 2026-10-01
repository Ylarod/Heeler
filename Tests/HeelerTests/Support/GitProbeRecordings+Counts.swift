import Foundation

/// Real changes-script output recorded with nonce F00D,
/// /bin/sh -s and Apple Git 2.54.0. Only the home became /home/dev.
/// The script options match GitProbe.changesScript; these are not hand-built.
/// The original four recordings are from the #387 scout; later provenance is inline.
extension GitProbeRecordings {
    /// A branch two commits ahead of and one behind its upstream, with a
    /// modified text file, a staged binary change and an untracked file.
    static let tracking = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/tracking

        /home/dev/src/tracking/.git
        .git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid 0be88ac75ec0816d97e198cf062acf0517673711\u{0}# branch.head main\u{0}# branch.upstream origin/main\u{0}# branch.ab +2 -1\u{0}1 .M N... 100644 100644 100644 f00c965d8307308469e537302baa73048488f162 f00c965d8307308469e537302baa73048488f162 app.txt\u{0}1 M. N... 100644 100644 100644 bdc955b7b2e610ad5a72302b139a2e6cb325519a 350ed01038bfaa2fda2722ada23a75bdd971bd68 logo.bin\u{0}? notes.txt\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin
        3\t1\tapp.txt\u{0}-\t-\tlogo.bin\u{0}
        __HEELER_GIT_F00D__ numstat rc=0

        __HEELER_GIT_F00D__ head begin
        1790580000 Local two

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

    /// A branch with an existing HEAD whose upstream was deleted:
    /// `# branch.upstream` without `# branch.ab`.
    static let upstreamGone = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/gone

        /home/dev/src/gone/.git
        .git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid 921badb9df524d8989a4f331ef2b89b9e679bd1c\u{0}# branch.head feature\u{0}# branch.upstream origin/feature\u{0}1 .M N... 100644 100644 100644 f00c965d8307308469e537302baa73048488f162 f00c965d8307308469e537302baa73048488f162 app.txt\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin
        1\t0\tapp.txt\u{0}
        __HEELER_GIT_F00D__ numstat rc=0

        __HEELER_GIT_F00D__ head begin
        1790510000 Remote work

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

    /// A SHA-256 repository without commits: a staged text file, a staged
    /// binary file and an untracked file, counted against the empty tree.
    static let unbornSHA256 = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/fresh256

        /home/dev/src/fresh256/.git
        .git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid (initial)\u{0}# branch.head main\u{0}1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000000000000000000000000000 7ad48b8af0afe1dc0aca3f01f95a2efc950704fb19144d4f240260b01d7c73e2 blob.bin\u{0}1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000000000000000000000000000 c5df06a7d3510bf59e7cd9ac36db54a7c0b3eb45141eab0d9da7f66c50f96e77 staged.txt\u{0}? loose.txt\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin
        -\t-\tblob.bin\u{0}3\t0\tstaged.txt\u{0}
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

    /// A staged rename whose new path was then rewritten in the working
    /// tree: status pairs the rename (`2 RM`), while the counts against HEAD
    /// list the new path as added and the old path as deleted.
    static let rewrittenRename = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/rewrite

        /home/dev/src/rewrite/.git
        .git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid ff392be9aeead43fb543d54630cc0a12e52393da\u{0}# branch.head main\u{0}2 RM N... 100644 100644 100644 0ff3bbb9c8bba2291654cd64067fa417ff54c508 0ff3bbb9c8bba2291654cd64067fa417ff54c508 R100 new.txt\u{0}old.txt\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin
        41\t0\tnew.txt\u{0}0\t20\told.txt\u{0}
        __HEELER_GIT_F00D__ numstat rc=0

        __HEELER_GIT_F00D__ head begin
        1790500000 Seed

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

    /// An unborn main tracking an existing origin/main. Recorded in an
    /// isolated environment with Apple Git 2.54.0, the same script/options,
    /// /bin/sh -s and nonce F00D; only the home became /home/dev.
    /// Seed: initialize an upstream with one commit; initialize this empty
    /// Checkout, fetch origin, configure branch.main.remote=origin and
    /// branch.main.merge=refs/heads/main, stage two text lines, leave one
    /// untracked file. rev-parse --verify refs/remotes/origin/main succeeds,
    /// but status emits branch.upstream without branch.ab because HEAD is unborn.
    static let countsUnbornWithLiveUpstream = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ version begin
        git version 2.54.0 (Apple Git-157)

        __HEELER_GIT_F00D__ version rc=0

        __HEELER_GIT_F00D__ home begin
        /home/dev
        __HEELER_GIT_F00D__ home rc=0

        __HEELER_GIT_F00D__ discover begin
        /home/dev/src/unborn-tracking

        /home/dev/src/unborn-tracking/.git
        .git

        __HEELER_GIT_F00D__ discover rc=0

        __HEELER_GIT_F00D__ status begin
        # branch.oid (initial)\u{0}# branch.head main\u{0}# branch.upstream origin/main\u{0}1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 814f4a422927b82f5f8a43f8fab6d3839e3983f2 staged.txt\u{0}? loose.txt\u{0}
        __HEELER_GIT_F00D__ status rc=0

        __HEELER_GIT_F00D__ numstat begin
        2\t0\tstaged.txt\u{0}
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
}
