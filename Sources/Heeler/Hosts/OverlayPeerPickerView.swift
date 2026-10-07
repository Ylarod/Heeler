import HeelerOverlay
import SwiftUI

/// "Choose from Tailnet…": the peers of the Host's Overlay Network, so a
/// Host (or its Jump Host) can be picked instead of typing its overlay
/// address. Connects the network first when it is not online.
struct OverlayPeerPickerView: View {
    let network: OverlayNetwork
    let target: OverlayPeerTarget
    let onPick: (OverlayPeerCandidate, OverlayPeerCandidate.AddressStyle) -> Void

    @State private var model: OverlayPeerPickerModel
    @State private var query = ""
    @State private var style = OverlayPeerCandidate.AddressStyle.ipAddress
    @Environment(\.dismiss) private var dismiss

    init(
        network: OverlayNetwork,
        target: OverlayPeerTarget,
        model: OverlayPeerPickerModel,
        onPick: @escaping (OverlayPeerCandidate, OverlayPeerCandidate.AddressStyle) -> Void
    ) {
        self.network = network
        self.target = target
        self.onPick = onPick
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(network.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            model.cancel()
                            dismiss()
                        }
                    }
                }
        }
        .task { await model.load() }
        // A Try Again still connecting must not outlive the sheet.
        .onDisappear { model.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Connecting to \(network.displayName)…")
                    .foregroundStyle(.secondary)
                Button("Stop Connecting", role: .cancel) { model.cancel() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Stop connecting to \(network.displayName)")
                    .accessibilityHint("Stops waiting so you can type the address yourself")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
        case .failed(let failure):
            failureView(failure)
        case .cancelled:
            cancelledView
        case .loaded:
            peerList
        }
    }

    private var peerList: some View {
        let candidates = model.candidates(matching: query)
        return List {
            if OverlayPeerList.offersMachineNames(network.kind) {
                Section {
                    Picker("Fill In", selection: $style) {
                        ForEach(OverlayPeerCandidate.AddressStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Address to fill in")
                } footer: {
                    Text(styleFooter)
                }
            }
            Section {
                if candidates.isEmpty {
                    Text(query.isEmpty ? "No peers with an address" : "No matching peers")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates) { candidate in
                        Button {
                            onPick(candidate, style)
                            dismiss()
                        } label: {
                            OverlayPeerChoiceRow(candidate: candidate, style: style)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text(target == .jumpHost ? "Choose the Jump Host" : "Choose the Host")
            }
        }
        .searchable(text: $query, prompt: "Name or address")
        .refreshable { await model.load() }
    }

    private var styleFooter: String {
        switch style {
        case .ipAddress:
            "The peer's Tailscale IP address stays the same while the machine is in the tailnet."
        case .machineName:
            "The machine name is resolved through MagicDNS and follows the machine if its "
                + "address changes."
        }
    }

    private var cancelledView: some View {
        List {
            Section {
                LabeledContent("Status", value: "Cancelled")
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
            } footer: {
                Text(
                    "Heeler stopped waiting for \(network.displayName). Choose again to connect "
                        + "it, or type the address yourself.")
            }
        }
    }

    private func failureView(_ failure: TransportError) -> some View {
        let loginURL = failure.overlayLoginURL.flatMap { network.acceptsLoginURL($0) ? $0 : nil }
        return List {
            Section {
                LabeledContent(
                    "Status", value: OverlayStatusCopy.summary(nil, failure: failure))
                if let explanation = OverlayStatusCopy.explanation(nil, failure: failure) {
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let loginURL {
                    Link(destination: loginURL) {
                        Label("Sign In", systemImage: "person.badge.key")
                    }
                }
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
            } footer: {
                Text(
                    "Connect or fix \(network.displayName) in Settings › Overlay Networks, "
                        + "or type the address yourself.")
            }
        }
    }
}

/// One peer in the picker: name, the address it would fill in, and whether
/// it is online. Offline peers stay choosable but are dimmed.
private struct OverlayPeerChoiceRow: View {
    let candidate: OverlayPeerCandidate
    let style: OverlayPeerCandidate.AddressStyle

    var body: some View {
        let summary = OverlayStatusCopy.peerSummary(candidate.peer)
        HStack(spacing: 10) {
            if let isOnline = candidate.isOnline {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(isOnline ? .green : .secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayName)
                    .foregroundStyle(candidate.isOffline ? .secondary : .primary)
                Text(candidate.addresses.joined(separator: ", "))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                if let network = candidate.network {
                    Text("Network \(network)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !summary.isEmpty {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(candidate.isOffline ? 0.6 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Uses \(candidate.address(style) ?? "this peer") as the address")
    }
}
