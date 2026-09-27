import SwiftUI

struct ConsoleCommands: Commands {
    @FocusedValue(\.consoleCommandTarget) private var target

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            buttons(for: [.newAgent])
        }
        CommandGroup(replacing: .appSettings) {
            buttons(for: [.settings])
        }
        CommandMenu("Agents") {
            ForEach(
                ConsoleCommandShortcut.all.filter { shortcut in
                    shortcut.action != .newAgent && shortcut.action != .settings
                }
            ) { shortcut in
                commandButton(shortcut)
            }
        }
    }

    private func buttons(for actions: Set<ConsoleCommandAction>) -> some View {
        ForEach(ConsoleCommandShortcut.all.filter { actions.contains($0.action) }) { shortcut in
            commandButton(shortcut)
        }
    }

    private func commandButton(_ shortcut: ConsoleCommandShortcut) -> some View {
        Button(target?.titles.title(for: shortcut) ?? shortcut.title) {
            target?.perform(shortcut.action)
        }
            .keyboardShortcut(
                shortcut.key == "\r" ? .return : KeyEquivalent(shortcut.key),
                modifiers: shortcut.modifiers
            )
            .disabled(!(target?.allows(shortcut.action) ?? false))
    }
}

extension ConsoleCommandShortcut {
    var modifiers: EventModifiers {
        requiresShift ? [.command, .shift] : [.command]
    }
}

private struct ConsoleCommandTargetKey: FocusedValueKey {
    typealias Value = ConsoleCommandTarget
}

extension FocusedValues {
    var consoleCommandTarget: ConsoleCommandTarget? {
        get { self[ConsoleCommandTargetKey.self] }
        set { self[ConsoleCommandTargetKey.self] = newValue }
    }
}
