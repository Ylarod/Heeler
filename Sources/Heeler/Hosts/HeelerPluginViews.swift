import SwiftUI

/// The warning glyph plugin notices share, in the Console's warning tone
/// rather than a failure's red: the Host still works.
struct PluginWarningIcon: View {
    var body: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(HostConnectionTone.warning.tint)
    }
}

/// A feature the Host's plugin is too old for, pointing at the Host's page,
/// which says how to update it.
struct PluginRequirementNote: View {
    let text: String

    var body: some View {
        let message = "\(text) See this Host's page in Hosts."
        Label {
            Text(message)
        } icon: {
            PluginWarningIcon()
        }
        .accessibilityElement(children: .combine)
    }
}
