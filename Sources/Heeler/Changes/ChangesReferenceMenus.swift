import SwiftUI

/// Shared by unified rows and side-by-side cells. The store resolves line IDs
/// against its open patch and keeps path and hunk rules out of the views.
@MainActor
struct ChangesReferenceActions {
    let store: ChangesStore
}

extension EnvironmentValues {
    @Entry var changesReferenceActions: ChangesReferenceActions? = nil
}

extension View {
    func changedFileReferenceMenu(_ file: ChangedFile, store: ChangesStore) -> some View {
        modifier(ChangedFileReferenceMenu(file: file, store: store))
    }

    /// Every section of an edited rename references the opened status path.
    func diffFileReferenceMenu(_ file: DiffFile) -> some View {
        modifier(DiffFileReferenceMenu())
    }

    func diffHunkReferenceMenu(_ hunk: DiffHunk) -> some View {
        modifier(DiffHunkReferenceMenu(hunk: hunk))
    }

    func diffLineContextMenu(_ line: DiffLine) -> some View {
        modifier(DiffLineContextMenu(line: line))
    }

    func diffLineAccessibilityActions(_ line: DiffLine, qualifier: String? = nil) -> some View {
        modifier(DiffLineAccessibilityActions(line: line, qualifier: qualifier))
    }
}

private struct ChangedFileReferenceMenu: ViewModifier {
    let file: ChangedFile
    let store: ChangesStore

    func body(content: Content) -> some View {
        content
            .contextMenu { commands }
            .accessibilityActions { commands }
    }

    @ViewBuilder private var commands: some View {
        if store.pathReference(for: file) != nil {
            Button("Copy Path", systemImage: "doc.on.doc") { store.copyPath(file) }
        }
        if store.insertReference != nil, store.insertionText(for: file) != nil {
            Button("Insert Path", systemImage: "text.insert") { store.insert(file: file) }
        }
    }
}

private struct DiffFileReferenceMenu: ViewModifier {
    @Environment(\.changesReferenceActions) private var actions

    func body(content: Content) -> some View {
        content
            .contextMenu { commands }
            .accessibilityActions { commands }
    }

    @ViewBuilder private var commands: some View {
        if let store = actions?.store {
            if store.diffPathReference != nil {
                Button("Copy Path", systemImage: "doc.on.doc") { store.copyDiffPath() }
            }
            if store.insertReference != nil, store.diffPathInsertionText != nil {
                Button("Insert Path", systemImage: "text.insert") { store.insertDiffPath() }
            }
        }
    }
}

private struct DiffHunkReferenceMenu: ViewModifier {
    let hunk: DiffHunk
    @Environment(\.changesReferenceActions) private var actions

    @ViewBuilder func body(content: Content) -> some View {
        if let store = actions?.store {
            content
                .contextMenu {
                    Button("Copy Hunk", systemImage: "doc.on.doc") { store.copyHunk(hunk.id) }
                }
                .accessibilityAction(named: "Copy Hunk") { store.copyHunk(hunk.id) }
        } else {
            content
        }
    }
}

private struct DiffLineContextMenu: ViewModifier {
    let line: DiffLine
    @Environment(\.changesReferenceActions) private var actions

    func body(content: Content) -> some View {
        content.contextMenu {
            if let store = actions?.store {
                Button("Copy Line", systemImage: "doc.on.doc") { store.copyLine(line.id) }
                Button("Copy Hunk", systemImage: "doc.on.doc") { store.copyHunk(containingLine: line.id) }
                if store.diffPathReference != nil {
                    Button("Copy Path", systemImage: "doc.on.doc") { store.copyDiffPath() }
                }
                if store.insertReference != nil, store.insertionText(forLine: line.id) != nil {
                    Button("Insert Line Reference", systemImage: "text.insert") { store.insert(line: line.id) }
                }
            }
        }
    }
}

private struct DiffLineAccessibilityActions: ViewModifier {
    let line: DiffLine
    let qualifier: String?
    @Environment(\.changesReferenceActions) private var actions

    @ViewBuilder func body(content: Content) -> some View {
        if let store = actions?.store {
            content
                .accessibilityAction(named: Text(name("Copy", "Line"))) { store.copyLine(line.id) }
                .accessibilityAction(named: Text(name("Copy", "Hunk"))) { store.copyHunk(containingLine: line.id) }
                .modifier(ReferenceAccessibilityAction(
                    name: name("Copy", "Path"), available: store.diffPathReference != nil,
                    action: { store.copyDiffPath() }))
                .modifier(ReferenceAccessibilityAction(
                    name: name("Insert", "Line Reference"),
                    available: store.insertReference != nil && store.insertionText(forLine: line.id) != nil,
                    action: { store.insert(line: line.id) }))
        } else {
            content
        }
    }

    private func name(_ verb: String, _ noun: String) -> String {
        [verb, qualifier, noun].compactMap { $0 }.joined(separator: " ")
    }
}

private struct ReferenceAccessibilityAction: ViewModifier {
    let name: String
    let available: Bool
    let action: @MainActor () -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if available {
            content.accessibilityAction(named: Text(name)) { action() }
        } else {
            content
        }
    }
}
