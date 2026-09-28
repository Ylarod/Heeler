import Foundation

/// Builds the POSIX shell scripts that read a Checkout on its Host and parses
/// what they print. Pure: no I/O. The only place in the app that knows git's
/// output formats (#382). The evidence behind every flag below is in
/// `docs/research/mobile-git-changes.md`, "Git command set" and "Script shape".
///
/// A script travels on standard input to ``shellInvocation``, so no path ever
/// appears on the SSH command line, where fish and csh login shells would
/// re-parse it. Inside the script every path is single-quoted, and the whole
/// body is one brace group reading from the null device: the shell parses it
/// completely before running anything, and no child can consume the rest.
/// Each command's output sits between markers carrying a per-request nonce
/// and ends with a framed exit status; the script ends with a final marker.
enum GitProbe {
    /// The fixed exec command. Never prepend anything to it: the login shell
    /// parses this line, and only this line.
    static let shellInvocation = "/bin/sh -s"

    /// Host-side output caps, one byte over each so truncation is detectable.
    enum Cap {
        static let version = 4_096
        static let home = 4_096
        static let discover = 65_536
        static let status = 2_097_152
        static let numstat = 1_048_576
        static let head = 65_536
    }

    /// A fresh nonce per request keeps repository content and stale output
    /// from matching a marker. Hex only, so it needs no quoting.
    static func makeNonce() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    static func marker(nonce: String) -> String {
        "__HEELER_GIT_\(nonce)__"
    }

    // MARK: Script

    /// Repository-local variables that would pair another repository's index
    /// or configuration with this working tree (`git rev-parse
    /// --local-env-vars`), plus the ones that change output or pathspecs.
    static let unsetEnvironment = [
        "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_CONFIG",
        "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT", "GIT_PREFIX",
        "GIT_IMPLICIT_WORK_TREE", "GIT_GRAFT_FILE", "GIT_NO_REPLACE_OBJECTS",
        "GIT_REPLACE_REF_BASE", "GIT_SHALLOW_FILE", "GIT_NAMESPACE",
        "GIT_EXTERNAL_DIFF", "GIT_DIFF_OPTS", "GIT_ATTR_SOURCE",
        "GIT_GLOB_PATHSPECS", "GIT_NOGLOB_PATHSPECS", "GIT_ICASE_PATHSPECS",
    ]

    /// The options every git invocation except the version probe carries.
    /// Two must never be simplified: `core.fsmonitor` is the empty value, not
    /// `false`, because git 2.35.1 and older run a program named `false` from
    /// PATH; and index auto-refresh is off, because `git diff` rewrites the
    /// index even with optional locks disabled. Clean filters (git-lfs) are
    /// deliberately left alone.
    static let neutralizingOptions = [
        "--no-pager", "--no-optional-locks", "--literal-pathspecs",
        "-c", "core.fsmonitor=",
        "-c", "core.hooksPath=/dev/null",
        "-c", "core.quotePath=false",
        "-c", "color.ui=false",
        "-c", "diff.autoRefreshIndex=false",
        "-c", "diff.relative=false",
        "-c", "log.showSignature=false",
        "-c", "status.renames=true",
    ]

    /// Assembles a complete script: the shared preamble, `body`, and the
    /// final marker, inside one brace group. `body` may carry raw path
    /// bytes, already single-quoted.
    static func script(nonce: String, body: Data) -> Data {
        var script = Data("{\n".utf8)
        script.append(Data(preamble(nonce: nonce).utf8))
        script.append(body)
        script.append(Data("printf '\\n%s done\\n' \"$N\"\n} </dev/null 3>&1\n".utf8))
        return script
    }

    /// Everything a script runs before its own commands: a clean git
    /// environment, the C locale, the app's extra PATH entries, and the
    /// `g`, `sec`, `base` and `latest` helpers.
    static func preamble(nonce: String) -> String {
        let git = (["git"] + neutralizingOptions.map(shellWord)).joined(separator: " ")
        return """
            N=\(singleQuoted(marker(nonce: nonce)))
            unset \(unsetEnvironment.joined(separator: " "))
            LC_ALL=C GIT_PAGER=cat PAGER=cat GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1
            export LC_ALL GIT_PAGER PAGER GIT_TERMINAL_PROMPT GIT_OPTIONAL_LOCKS GIT_NO_LAZY_FETCH
            \(HerdrHostPath.pathExport)
            g() { \(git) "$@"; }
            sec() {
              cap=$1 name=$2; shift 2
              printf '\\n%s %s begin\\n' "$N" "$name"
              printf '\\n%s %s begin\\n' "$N" "$name" >&2
              rc=$( { { "$@"; echo "$?" >&4; } | head -c "$((cap + 1))" >&3; } 4>&1 )
              printf '\\n%s %s rc=%s\\n' "$N" "$name" "$rc"
              printf '\\n%s %s end\\n' "$N" "$name" >&2
            }
            base() {
              g -C "$1" rev-parse -q --verify HEAD 2>/dev/null ||
                g -C "$1" hash-object -t tree /dev/null
            }
            latest() {
              h=$(g -C "$1" rev-parse -q --verify HEAD 2>/dev/null) || return 0
              g -C "$1" -c i18n.logOutputEncoding=UTF-8 log -1 --no-color '--format=%ct %s' "$h" --
            }

            """
    }

    /// POSIX single quotes around arbitrary bytes: `'` becomes `'\''`, and
    /// every other byte, newline included, is literal.
    static func singleQuoted(_ bytes: Data) -> Data {
        var quoted = Data([0x27])
        for byte in bytes {
            if byte == 0x27 {
                quoted.append(contentsOf: Array("'\\''".utf8))
            } else {
                quoted.append(byte)
            }
        }
        quoted.append(0x27)
        return quoted
    }

    static func singleQuoted(_ text: String) -> String {
        String(decoding: singleQuoted(Data(text.utf8)), as: UTF8.self)
    }

    /// Leaves plain words bare so the generated script stays readable.
    private static func shellWord(_ word: String) -> String {
        let plain = word.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."),
                UInt8(ascii: "/"), UInt8(ascii: "="), UInt8(ascii: "_"):
                true
            default:
                false
            }
        }
        return plain && !word.isEmpty ? word : singleQuoted(word)
    }

    // MARK: Framing

    /// One framed command's output.
    struct Section: Sendable, Equatable {
        /// Standard output between the markers, cut to the section's cap.
        let body: Data
        /// The command's framed exit status.
        let status: Int32
        /// The command printed more than its cap. Length is the only
        /// reliable signal: a small overrun can still end with status 0.
        let isTruncated: Bool
        /// Standard error between the section's framed begin and end lines.
        let messages: Data

        /// Git's first error line, or nil when it printed none.
        var firstMessageLine: String? {
            String(decoding: messages, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .lazy
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
        }
    }

    /// A script's output as seen through one request's nonce. Anything
    /// outside that nonce's markers, such as login-shell noise or another
    /// request's output, is ignored.
    struct Frames: Sendable {
        let stdout: Data
        let stderr: Data
        private let marker: String

        init(stdout: Data, stderr: Data, nonce: String) {
            self.stdout = stdout
            self.stderr = stderr
            marker = GitProbe.marker(nonce: nonce)
        }

        /// The final marker arrived. A remote process killed by a signal
        /// reads as exit status 0 on the channel, so this, not the channel's
        /// status, says the script ran to the end.
        var reachedEnd: Bool {
            stdout.range(of: Data("\n\(marker) done\n".utf8)) != nil
        }

        /// Nil when the section never began. Throws `.incomplete` when it
        /// began but its framed exit status is missing or unreadable.
        func section(_ name: String, cap: Int) throws -> Section? {
            guard let begin = stdout.range(of: Data("\n\(marker) \(name) begin\n".utf8)) else {
                return nil
            }
            let statusMarker = Data("\n\(marker) \(name) rc=".utf8)
            guard
                let end = stdout.range(
                    of: statusMarker, in: begin.upperBound..<stdout.endIndex),
                let lineEnd = stdout[end.upperBound...].firstIndex(of: 0x0A),
                let status = Int32(
                    String(decoding: stdout[end.upperBound..<lineEnd], as: UTF8.self)),
                status >= 0
            else {
                throw ChangesReadError.incomplete
            }
            let output = stdout[begin.upperBound..<end.lowerBound]
            return Section(
                body: Data(output.prefix(cap)),
                status: status,
                isTruncated: output.count > cap,
                messages: messages(name))
        }

        private func messages(_ name: String) -> Data {
            guard let begin = stderr.range(of: Data("\n\(marker) \(name) begin\n".utf8))
            else { return Data() }
            let end = stderr.range(
                of: Data("\n\(marker) \(name) end\n".utf8),
                in: begin.upperBound..<stderr.endIndex)
            return Data(stderr[begin.upperBound..<(end?.lowerBound ?? stderr.endIndex)])
        }

        /// A section the script always runs at this point.
        func requiredSection(_ name: String, cap: Int) throws -> Section {
            guard let section = try section(name, cap: cap) else {
                throw ChangesReadError.incomplete
            }
            return section
        }
    }
}
