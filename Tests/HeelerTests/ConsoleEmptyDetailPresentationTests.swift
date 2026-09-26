import Testing

@testable import Heeler

@Suite("Console empty detail presentation")
struct ConsoleEmptyDetailPresentationTests {
    @Test func configuredConsoleOffersShowAgentsAndNewAgent() {
        let presentation = ConsoleEmptyDetailPresentation(hasHosts: true)
        #expect(presentation.title == "No Agent Selected")
        #expect(!presentation.message.isEmpty)
        #expect(!presentation.systemImage.isEmpty)
        // The Hosts tab sits right above; the screen does not repeat it.
        #expect(presentation.actions == [.showAgents, .newAgent])
        #expect(presentation.actions.map(\.title) == ["Show Agents", "New Agent"])
        #expect(presentation.actions.compactMap(\.shortcutHint) == ["⌘N"])
        #expect(presentation.actions.allSatisfy { presentation.isEnabled($0) })
    }

    @Test func noHostsExplainsPrerequisiteAndOffersAddHost() {
        let presentation = ConsoleEmptyDetailPresentation(hasHosts: false)
        #expect(presentation.message == "Add a Host to start an Agent and view its live terminal.")
        #expect(presentation.actions == [.showAgents, .newAgent, .hosts])
        #expect(presentation.title(for: .hosts) == "Add Host")
        #expect(presentation.shortcutHint(for: .hosts) == "⌘⇧H")
        #expect(!presentation.isEnabled(.newAgent))
        #expect(presentation.isEnabled(.hosts))
        #expect(presentation.isEnabled(.showAgents))
    }
    @Test func visibleSidebarOmitsShowAgentsWithoutChangingOtherActions() {
        let presentation = ConsoleEmptyDetailPresentation(hasHosts: true, showsAgentsAction: false)
        #expect(presentation.actions == [.newAgent])
        #expect(
            ConsoleEmptyDetailPresentation(hasHosts: false, showsAgentsAction: false).actions
                == [.newAgent, .hosts])
    }

    @Test func showAgentsHasNoInventedKeyboardShortcut() {
        #expect(ConsoleEmptyDetailPresentation.Action.showAgents.title == "Show Agents")
        #expect(ConsoleEmptyDetailPresentation.Action.showAgents.systemImage == "sidebar.left")
        #expect(ConsoleEmptyDetailPresentation.Action.showAgents.shortcutHint == nil)
    }

    @Test func terminalsTabWordsTheSameActionsForShells() {
        let presentation = ConsoleEmptyDetailPresentation(hasHosts: true, listsTerminals: true)
        #expect(presentation.title == "No Terminal Selected")
        #expect(presentation.systemImage == "terminal")
        #expect(presentation.actions.map(presentation.title(for:))
            == ["Show Terminals", "New Terminal"])
        // ⌘N opens New Terminal on this tab.
        #expect(presentation.shortcutHint(for: .newAgent) == "⌘N")
        #expect(ConsoleEmptyDetailPresentation(hasHosts: false, listsTerminals: true).message
            == "Add a Host to open its terminals.")
    }
}
