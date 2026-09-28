import Foundation

/// Real output of the patch script through `/bin/sh -s`, with nonce F00D,
/// Apple Git 2.54.0 (Apple Git-157), and an otherwise empty environment.
/// Scratch repositories cover staged and unstaged changes. Only the recording
/// home directory was rewritten to /home/dev. Non-UTF-8 captures use base64.
extension GitProbeRecordings {
    static let patchModified = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/modified.txt b/modified.txt
        index dad2832..3c6ec42 100644
        --- a/modified.txt
        +++ b/modified.txt
        @@ -1,3 +1,3 @@
         first
        -old
        +new
         last

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchDeleted = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/deleted.txt b/deleted.txt
        deleted file mode 100644
        index 4afd8c6..0000000
        --- a/deleted.txt
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -gone
        -again

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchAdded = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/added.txt b/added.txt
        new file mode 100644
        index 0000000..3669885
        --- /dev/null
        +++ b/added.txt
        @@ -0,0 +1,2 @@
        +added
        +next

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchIntentToAdd = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/intent.txt b/intent.txt
        new file mode 100644
        index 0000000..434930e
        --- /dev/null
        +++ b/intent.txt
        @@ -0,0 +1 @@
        +intent

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchPureRename = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/pure-old.txt b/pure-new.txt
        similarity index 100%
        rename from pure-old.txt
        rename to pure-new.txt

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchEditedRename = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/edited-old.txt b/edited-new.txt
        similarity index 84%
        rename from edited-old.txt
        rename to edited-new.txt
        index c9e9e05..0bde290 100644
        --- a/edited-old.txt
        +++ b/edited-new.txt
        @@ -3,7 +3,7 @@ two
         three
         four
         five
        -six
        +changed
         seven
         eight
         nine

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchRewriteRename = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/move-new.txt b/move-new.txt
        new file mode 100644
        index 0000000..f916107
        --- /dev/null
        +++ b/move-new.txt
        @@ -0,0 +1,3 @@
        +entirely
        +different
        +content
        diff --git a/move-old.txt b/move-old.txt
        deleted file mode 100644
        index 4cb29ea..0000000
        --- a/move-old.txt
        +++ /dev/null
        @@ -1,3 +0,0 @@
        -one
        -two
        -three

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchMode = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/mode.txt b/mode.txt
        old mode 100644
        new mode 100755

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchMissingNewline = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/no-newline.txt b/no-newline.txt
        index 489ce0f..3e5126c 100644
        --- a/no-newline.txt
        +++ b/no-newline.txt
        @@ -1 +1 @@
        -old
        \\ No newline at end of file
        +new
        \\ No newline at end of file

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchCRLF = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/crlf.txt b/crlf.txt
        index 118179e..bdaa0ed 100644
        --- a/crlf.txt
        +++ b/crlf.txt
        @@ -1,3 +1,3 @@
         first\r
        -old\r
        +new\r
         last\r

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchLatin1 = (
        stdout: Data(base64Encoded: "Cl9fSEVFTEVSX0dJVF9GMDBEX18gcGF0Y2ggYmVnaW4KZGlmZiAtLWdpdCBhL2xhdGluLnR4dCBiL2xhdGluLnR4dAppbmRleCA2ZjgzMzk1Li4wMzBlZGU1IDEwMDY0NAotLS0gYS9sYXRpbi50eHQKKysrIGIvbGF0aW4udHh0CkBAIC0xICsxIEBACi1jYWbpCitjYWboCgpfX0hFRUxFUl9HSVRfRjAwRF9fIHBhdGNoIHJjPTAKCl9fSEVFTEVSX0dJVF9GMDBEX18gZG9uZQo=")!,
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchBinary = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/binary.dat b/binary.dat
        index e7be1ea..f9e371f 100644
        Binary files a/binary.dat and b/binary.dat differ

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchConflict = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/conflict.txt b/conflict.txt
        index b19a1e9..5fbd3a4 100644
        --- a/conflict.txt
        +++ b/conflict.txt
        @@ -1 +1,5 @@
        +<<<<<<< HEAD
         ours
        +=======
        +other
        +>>>>>>> other

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchSubmodule = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/submodule b/submodule
        index 8cc8e7a..8b407fc 160000
        --- a/submodule
        +++ b/submodule
        @@ -1 +1 @@
        -Subproject commit 8cc8e7a70f9da5337ad84d540f2cc8ecf0c59601
        +Subproject commit 8b407fc09a24c95f394f9fbf05635831f6e09929

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchSection = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/section.swift b/section.swift
        index 8c1a0ee..a7608a0 100644
        --- a/section.swift
        +++ b/section.swift
        @@ -11,5 +11,5 @@ func example() {
             keep
             keep
             keep
        -    old
        +    new
         }

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchHeaderText = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/header-text.txt b/header-text.txt
        index 2bf4f34..8fba68b 100644
        --- a/header-text.txt
        +++ b/header-text.txt
        @@ -1 +1 @@
        --- old header
        +++ new header

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchMultipleHunks = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/multi.txt b/multi.txt
        index ac9837c..4bfed74 100644
        --- a/multi.txt
        +++ b/multi.txt
        @@ -1,5 +1,5 @@
         line 1
        -line 2
        +changed 2
         line 3
         line 4
         line 5
        @@ -22,7 +22,7 @@ line 21
         line 22
         line 23
         line 24
        -line 25
        +changed 25
         line 26
         line 27
         line 28

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchUntracked = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/untracked space.txt b/untracked space.txt
        new file mode 100644
        index 0000000..0566a03
        --- /dev/null
        +++ b/untracked space.txt\t
        @@ -0,0 +1,2 @@
        +new one
        +new two
        \\ No newline at end of file

        __HEELER_GIT_F00D__ patch rc=1

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchEmptyUntracked = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/empty.txt b/empty.txt
        new file mode 100644
        index 0000000..e69de29

        __HEELER_GIT_F00D__ patch rc=1

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchUntrackedBinary = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        diff --git a/untracked.dat b/untracked.dat
        new file mode 100644
        index 0000000..f9e371f
        Binary files /dev/null and b/untracked.dat differ

        __HEELER_GIT_F00D__ patch rc=1

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchVanished = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch rc=1

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin
        error: Could not access 'missing.txt'

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchUnchanged = (
        stdout: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch rc=0

        __HEELER_GIT_F00D__ done

        """.utf8),
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchRawPath = (
        stdout: Data(base64Encoded: "Cl9fSEVFTEVSX0dJVF9GMDBEX18gcGF0Y2ggYmVnaW4KZGlmZiAtLWdpdCBhL3Jhdy3/LnR4dCBiL3Jhdy3/LnR4dApkZWxldGVkIGZpbGUgbW9kZSAxMDA2NDQKaW5kZXggNmE0OGRlMy4uMDAwMDAwMAotLS0gYS9yYXct/y50eHQKKysrIC9kZXYvbnVsbApAQCAtMSArMCwwIEBACi1yYXcgY29udGVudAoKX19IRUVMRVJfR0lUX0YwMERfXyBwYXRjaCByYz0wCgpfX0hFRUxFUl9HSVRfRjAwRF9fIGRvbmUK")!,
        stderr: Data(
        """

        __HEELER_GIT_F00D__ patch begin

        __HEELER_GIT_F00D__ patch end

        """.utf8))

    static let patchNames: [(path: Data, stdout: Data, stderr: Data)] = [
        (path: Data(
            """
            --
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git a/-- b/--
            index 3367afd..3e75765 100644
            --- a/--
            +++ b/--
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            -dash.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git a/-dash.txt b/-dash.txt
            index 3367afd..3e75765 100644
            --- a/-dash.txt
            +++ b/-dash.txt
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            sp ace.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git a/sp ace.txt b/sp ace.txt
            index 3367afd..3e75765 100644
            --- a/sp ace.txt\t
            +++ b/sp ace.txt\t
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            quo\"te.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git \"a/quo\\\"te.txt\" \"b/quo\\\"te.txt\"
            index 3367afd..3e75765 100644
            --- \"a/quo\\\"te.txt\"
            +++ \"b/quo\\\"te.txt\"
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            sq'uote.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git a/sq'uote.txt b/sq'uote.txt
            index 3367afd..3e75765 100644
            --- a/sq'uote.txt
            +++ b/sq'uote.txt
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            two\\\\bs.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git \"a/two\\\\\\\\bs.txt\" \"b/two\\\\\\\\bs.txt\"
            index 3367afd..3e75765 100644
            --- \"a/two\\\\\\\\bs.txt\"
            +++ \"b/two\\\\\\\\bs.txt\"
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            trail\\
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git \"a/trail\\\\\" \"b/trail\\\\\"
            index 3367afd..3e75765 100644
            --- \"a/trail\\\\\"
            +++ \"b/trail\\\\\"
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            bang!.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git a/bang!.txt b/bang!.txt
            index 3367afd..3e75765 100644
            --- a/bang!.txt
            +++ b/bang!.txt
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            $HOME.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git a/$HOME.txt b/$HOME.txt
            index 3367afd..3e75765 100644
            --- a/$HOME.txt
            +++ b/$HOME.txt
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            *.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git a/*.txt b/*.txt
            index 3367afd..3e75765 100644
            --- a/*.txt
            +++ b/*.txt
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            [ab].txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git a/[ab].txt b/[ab].txt
            index 3367afd..3e75765 100644
            --- a/[ab].txt
            +++ b/[ab].txt
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            ünï.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git a/ünï.txt b/ünï.txt
            index 3367afd..3e75765 100644
            --- a/ünï.txt
            +++ b/ünï.txt
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            中文.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git a/中文.txt b/中文.txt
            index 3367afd..3e75765 100644
            --- a/中文.txt
            +++ b/中文.txt
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            line
            break.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git \"a/line\\nbreak.txt\" \"b/line\\nbreak.txt\"
            index 3367afd..3e75765 100644
            --- \"a/line\\nbreak.txt\"
            +++ \"b/line\\nbreak.txt\"
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            tab\tname.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git \"a/tab\\tname.txt\" \"b/tab\\tname.txt\"
            index 3367afd..3e75765 100644
            --- \"a/tab\\tname.txt\"
            +++ \"b/tab\\tname.txt\"
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            control\u{0001}.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git \"a/control\\001.txt\" \"b/control\\001.txt\"
            index 3367afd..3e75765 100644
            --- \"a/control\\001.txt\"
            +++ \"b/control\\001.txt\"
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
        (path: Data(
            """
            a b/c b/d.txt
            """.utf8),
         stdout: Data(
            """

            __HEELER_GIT_F00D__ patch begin
            diff --git a/a b/c b/d.txt b/a b/c b/d.txt
            index 3367afd..3e75765 100644
            --- a/a b/c b/d.txt\t
            +++ b/a b/c b/d.txt\t
            @@ -1 +1 @@
            -old
            +new

            __HEELER_GIT_F00D__ patch rc=0

            __HEELER_GIT_F00D__ done

            """.utf8),
         stderr: Data(
            """

            __HEELER_GIT_F00D__ patch begin

            __HEELER_GIT_F00D__ patch end

            """.utf8)),
    ]
}
