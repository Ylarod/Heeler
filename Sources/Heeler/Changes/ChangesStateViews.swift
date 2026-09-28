import SwiftUI

/// A list-local state, so keeping the list mounted under a file diff never
/// paints its failures over the reader.
struct ChangesFailureState<Actions: View>: View {
    let title: String
    let message: String
    let symbol: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            actions()
        }
    }
}

struct ChangesTimeoutNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Reading Changes timed out", systemImage: "clock")
                .font(.subheadline.weight(.semibold))
            Text("Showing the earlier read. Pull to try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
