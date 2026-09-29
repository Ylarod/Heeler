import SwiftUI
import UIKit

/// The git item of fish's Tide prompt, drawn from a Changes read: the
/// branch, or `@` and the short commit while detached, then how far it is
/// behind and ahead of its upstream and how many files are conflicted,
/// staged, modified, and untracked, each only when nonzero, as
/// "main ⇣1 ⇡2 ~1 +3 !4 ?2". Changes reads neither Tide's stash count nor
/// an operation in progress, so those never show.
struct TideGitItem: Equatable {
    enum Role: Equatable {
        case upstream
        case conflicted
        case staged
        case dirty
        case untracked
    }

    struct Count: Equatable {
        let role: Role
        let text: String
    }

    /// Tide's default `tide_git_truncation_length`.
    static let truncationLength = 24

    /// The branch, shortened as Tide shortens it, or the short commit.
    let location: String
    let isDetached: Bool
    let counts: [Count]
    let accessibilityValue: String

    /// Nil whenever the Agents list row would show no totals for the same
    /// read, except that a clean Checkout still shows its branch.
    init?(phase: ChangesStore.Phase, timedOutKeepingContent: Bool) {
        guard case .loaded(let changes) = phase, !timedOutKeepingContent else { return nil }
        self.init(changes)
    }

    init(_ changes: CheckoutChanges) {
        var spoken: [String] = []
        switch changes.head.branch {
        case .named(let name):
            location = Self.shortened(name)
            isDetached = false
            spoken.append("Branch \(name)")
        case .detached:
            location = changes.head.commit.map { String($0.prefix(7)) } ?? "HEAD"
            isDetached = true
            spoken.append(changes.head.branchTitle)
        }

        var ahead = 0
        var behind = 0
        if case .tracking(let a, let b) = changes.head.upstream?.state {
            ahead = a
            behind = b
        }
        var conflicted = 0
        var staged = 0
        var dirty = 0
        for file in changes.files {
            if file.kind == .conflicted {
                conflicted += 1
                continue
            }
            switch file.staging {
            case .staged: staged += 1
            case .unstaged: dirty += 1
            case .both:
                staged += 1
                dirty += 1
            case nil: break
            }
        }
        let untracked = changes.totals.untrackedItems

        var counts: [Count] = []
        func add(_ value: Int, _ role: Role, _ symbol: String, _ phrase: String) {
            guard value > 0 else { return }
            counts.append(Count(role: role, text: symbol + value.formatted()))
            spoken.append("\(value.formatted()) \(phrase)")
        }
        add(behind, .upstream, "⇣", behind == 1 ? "commit behind" : "commits behind")
        add(ahead, .upstream, "⇡", ahead == 1 ? "commit ahead" : "commits ahead")
        add(conflicted, .conflicted, "~", "conflicted")
        add(staged, .staged, "+", "staged")
        add(dirty, .dirty, "!", "modified")
        add(untracked, .untracked, "?", "untracked")
        self.counts = counts
        // The Host capped its status output, so the file counts are lower
        // bounds; Tide has no mark for that, so only VoiceOver says so.
        if changes.isStatusTruncated, conflicted + staged + dirty + untracked > 0 {
            spoken.append("file counts incomplete")
        }
        accessibilityValue = spoken.joined(separator: ", ")
    }

    /// What the prompt reads, as "main ⇣1 ⇡2 +3".
    var text: String {
        ([(isDetached ? "@" : "") + location] + counts.map(\.text)).joined(separator: " ")
    }

    /// Tide's `string shorten -m24`: the first 23 characters and an ellipsis.
    static func shortened(_ name: String) -> String {
        name.count > truncationLength
            ? String(name.prefix(truncationLength - 1)) + "…" : name
    }
}

/// Tide's lean git colors on dark themes; on light ones, the same hues dark
/// enough to read.
enum TideGitPalette {
    static let branch = DiffPalette.adaptive(light: 0x1A7F37, dark: 0x5FD700)
    static let conflicted = DiffPalette.adaptive(light: 0xCF222E, dark: 0xFF0000)
    static let changed = DiffPalette.adaptive(light: 0x8A5C00, dark: 0xD7AF00)
    static let untracked = DiffPalette.adaptive(light: 0x0969DA, dark: 0x00AFFF)

    static func color(for role: TideGitItem.Role) -> UIColor {
        switch role {
        case .upstream: branch
        case .conflicted: conflicted
        case .staged, .dirty: changed
        case .untracked: untracked
        }
    }
}

/// The Tide git item in Agent detail's status line, at that line's size.
/// Only the branch gives way when the line is short of room.
struct TideGitPrompt: View {
    let store: ChangesStore
    var font: Font = .caption2.weight(.medium)

    var body: some View {
        if let item = TideGitItem(
            phase: store.phase, timedOutKeepingContent: store.timedOutKeepingContent)
        {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .imageScale(.small)
                        .foregroundStyle(Color(uiColor: TideGitPalette.branch))
                    if item.isDetached {
                        Text(verbatim: "@").foregroundStyle(.primary)
                    }
                    Text(verbatim: item.location)
                        .foregroundStyle(Color(uiColor: TideGitPalette.branch))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                ForEach(Array(item.counts.enumerated()), id: \.offset) { _, count in
                    Text(verbatim: count.text)
                        .foregroundStyle(Color(uiColor: TideGitPalette.color(for: count.role)))
                        .fixedSize()
                }
            }
            .font(font)
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Git")
            .accessibilityValue(item.accessibilityValue)
            .accessibilityIdentifier("agent-status-git")
        }
    }
}
