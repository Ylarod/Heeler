import HeelerOverlay
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Settings › Overlay Networks: the in-app Tailscale, ZeroTier, and EasyTier
/// networks a Host can be reached through (ADR 0021). Lists each network
/// with its node's status; adding, editing, connecting, and deleting happen
/// on the network's own screen and form.
struct OverlayNetworksSettingsView: View {
    let store: OverlayNetworkStore
    let onHostAdded: (Host.ID) -> Void
    @State private var isAdding = false
    @State private var deleteError: String?
    /// A network just added, opened once its form has closed.
    @State private var addedNetworkID: OverlayNetwork.ID?
    @State private var openedNetworkID: OverlayNetwork.ID?

    var body: some View {
        List {
            if let loadError = store.catalogLoadError {
                Section {
                    Label(loadError.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            Section {
                ForEach(store.networks) { network in
                    NavigationLink {
                        OverlayNetworkDetailView(
                            store: store, networkID: network.id, onHostAdded: onHostAdded)
                    } label: {
                        OverlayNetworkRow(
                            network: network,
                            status: store.statuses[network.id],
                            failure: store.connectFailures[network.id],
                            signedOut: store.signedOut.contains(network.id),
                            needsSignIn: store.needsSignIn(network))
                    }
                }
                .onDelete { offsets in
                    // Resolve ids first: each removal shifts the indices.
                    let ids = offsets.map { store.networks[$0].id }
                    for id in ids {
                        do {
                            try store.remove(id)
                        } catch {
                            deleteError = (error as? OverlayNetworkStoreError)?.message
                                ?? "The network could not be deleted."
                            return
                        }
                    }
                }
                Button {
                    isAdding = true
                } label: {
                    Label("Add Network", systemImage: "plus")
                }
                .disabled(store.catalogLoadError != nil)
            } footer: {
                Text(
                    "Heeler joins these networks itself, without turning on a VPN, and uses "
                        + "them only for Hosts you assign in Edit Host › Network. A network "
                        + "stays connected only while Heeler is open.")
            }
            ZeroTierUnusedIdentitySection(store: store)
        }
        .navigationTitle("Overlay Networks")
        .alert(
            "Could not delete the network",
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .sheet(isPresented: $isAdding, onDismiss: {
            // Push only after the sheet has gone, or the push is dropped.
            guard let id = addedNetworkID else { return }
            addedNetworkID = nil
            openedNetworkID = id
        }) {
            OverlayNetworkFormView(store: store) { addedNetworkID = $0 }
        }
        .navigationDestination(item: $openedNetworkID) { id in
            // A network just added starts at once: Tailscale goes straight
            // to sign-in instead of waiting for another tap here.
            OverlayNetworkDetailView(
                store: store, networkID: id, onHostAdded: onHostAdded, startsOnAppear: true)
        }
        .task {
            // Node status changes on its own (sign-in completes, peers come
            // and go); poll only while this screen is visible.
            while !Task.isCancelled {
                await store.refreshStatuses()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private struct OverlayNetworkRow: View {
    let network: OverlayNetwork
    let status: OverlayNodeStatus?
    let failure: TransportError?
    let signedOut: Bool
    let needsSignIn: Bool

    var body: some View {
        let summary = OverlayStatusCopy.summary(
            status, failure: failure, signedOut: signedOut, needsSignIn: needsSignIn)
        HStack(spacing: 10) {
            OverlayStatusDot(
                tone: OverlayStatusCopy.tone(
                    status, failure: failure, signedOut: signedOut, needsSignIn: needsSignIn))
            VStack(alignment: .leading, spacing: 2) {
                Text(network.displayName)
                Text("\(network.kind.displayName) · \(summary)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Settings › Overlay Networks › ZeroTier: a node ID generated for a
/// network that was never added (or whose networks were deleted). It may
/// already be authorized somewhere, so it stays until the user forgets it.
/// Custom planets are per network, in each ZeroTier network's form.
private struct ZeroTierUnusedIdentitySection: View {
    let store: OverlayNetworkStore
    @State private var errorMessage: String?

    var body: some View {
        if store.hasUnusedZeroTierIdentity, let nodeID = store.zeroTierNodeID {
            Section {
                OverlayCopyableRow(title: "Node ID", value: nodeID)
                Button(role: .destructive) {
                    do {
                        try store.removeUnusedZeroTierIdentity()
                    } catch {
                        errorMessage = "The node ID could not be removed from the Keychain."
                    }
                } label: {
                    Label("Forget Unused Node ID", systemImage: "trash")
                }
            } header: {
                Text("ZeroTier")
            } footer: {
                Text(
                    "The node ID was created for a network not added yet; it is kept in case "
                        + "it was already authorized.")
            }
            .alert(
                "Could not change ZeroTier settings",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

extension OverlayNodeStatus {
    var isOnline: Bool {
        if case .online = self { true } else { false }
    }
}

/// How a network's status reads at a glance: the dot beside it.
enum OverlayStatusTone: Equatable {
    case idle, busy, ok, attention, failed

    var color: Color {
        switch self {
        case .ok: .green
        case .attention: .orange
        case .failed: .red
        case .idle, .busy: .secondary
        }
    }
}

/// The colored dot for an `OverlayStatusTone`; the text beside it says
/// the same, so it is hidden from VoiceOver.
struct OverlayStatusDot: View {
    let tone: OverlayStatusTone

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 9))
            .foregroundStyle(tone.color)
            .accessibilityHidden(true)
    }
}

/// One status vocabulary for the list row and the detail screen.
enum OverlayStatusCopy {
    /// The tone of `summary`: whether the network is up, needs the user
    /// (sign-in, approval), or failed.
    static func tone(
        _ status: OverlayNodeStatus?, failure: TransportError?, signedOut: Bool = false,
        needsSignIn: Bool = false
    ) -> OverlayStatusTone {
        if let failure {
            guard case .overlayFailed(_, let reason) = failure else { return .failed }
            switch reason {
            case .loginRequired, .signedOut, .notReady: return .attention
            default: return .failed
            }
        }
        switch status ?? .stopped {
        case .stopped: return signedOut || needsSignIn ? .attention : .idle
        case .starting: return .busy
        case .needsLogin, .waiting: return .attention
        case .online: return .ok
        case .failed: return .failed
        }
    }

    /// The status badge's symbol: what kind of state, where the tone
    /// only says how urgent.
    static func symbol(
        _ status: OverlayNodeStatus?, failure: TransportError?, signedOut: Bool = false,
        needsSignIn: Bool = false
    ) -> String {
        let signIn = "person.fill", waiting = "hourglass", failed = "exclamationmark"
        if let failure {
            guard case .overlayFailed(_, let reason) = failure else { return failed }
            switch reason {
            case .loginRequired, .signedOut: return signIn
            case .notReady: return waiting
            default: return failed
            }
        }
        switch status ?? .stopped {
        case .stopped: return signedOut || needsSignIn ? signIn : "pause.fill"
        case .starting: return "ellipsis"
        case .needsLogin: return signIn
        case .waiting: return waiting
        case .online: return "checkmark"
        case .failed: return failed
        }
    }

    /// The line under the network screen's status when no failure explains
    /// it: what the one action does, or how the network is doing.
    static func statusDetail(
        _ action: OverlayNetworkPrimaryAction, kind: OverlayKind, isStartingSignIn: Bool,
        peers: [OverlayPeer]?
    ) -> String? {
        switch action {
        case .signIn:
            return "Opens your browser to sign in."
        case .connect:
            return "Connects when a Host needs it."
        case .connecting:
            return isStartingSignIn ? "Your browser opens when it is ready." : nil
        case .disconnect:
            return peers.flatMap { peerCount($0, kind: kind) }
        }
    }

    /// "2 of 9 peers online", or "9 peers" where the overlay does not say
    /// who is online. ZeroTier roots are infrastructure, not peers.
    static func peerCount(_ peers: [OverlayPeer], kind: OverlayKind) -> String? {
        let members = kind == .zerotier
            ? peers.filter { $0.role != "planet" && $0.role != "moon" } : peers
        guard !members.isEmpty else { return "No peers yet" }
        let noun = members.count == 1 ? "peer" : "peers"
        guard members.allSatisfy({ $0.isOnline != nil }) else {
            return "\(members.count) \(noun)"
        }
        let online = members.filter { $0.isOnline == true }.count
        return "\(online) of \(members.count) \(noun) online"
    }

    /// A few words for the list row and the Status row; the network's name
    /// is already beside it. `explanation` carries the reason.
    /// `needsSignIn`: a stopped Tailscale network has no login to start
    /// with (`OverlayNetworkStore.primaryAction` is Sign In).
    static func summary(
        _ status: OverlayNodeStatus?, failure: TransportError?, signedOut: Bool = false,
        needsSignIn: Bool = false
    ) -> String {
        if let failure {
            guard case .overlayFailed(_, let reason) = failure else { return "Failed" }
            switch reason {
            case .notConfigured: return "Removed"
            case .catalogUnreadable: return "Unreadable"
            case .misconfigured: return "Misconfigured"
            case .loginRequired: return "Needs sign-in"
            case .signedOut: return "Signed out"
            case .notReady: return "Not ready"
            case .startFailed: return "Failed"
            case .unreachable: return "Unreachable"
            case .timedOut: return "Timed out"
            }
        }
        switch status ?? .stopped {
        case .stopped:
            if signedOut { return "Signed out" }
            return needsSignIn ? "Not signed in" : "Not connected"
        case .starting: return "Connecting…"
        case .needsLogin: return "Needs sign-in"
        case .waiting: return "Waiting"
        case .online: return "Connected"
        case .failed: return "Failed"
        }
    }

    /// The reason behind `summary`, for a line of its own under Status.
    /// Worded for the network's own screen, so it never points back at
    /// Settings › Overlay Networks the way a Host's error does.
    static func explanation(_ status: OverlayNodeStatus?, failure: TransportError?) -> String? {
        if let failure {
            guard case .overlayFailed(_, let reason) = failure else {
                return failure.presentation.detail ?? failure.presentation.summary
            }
            switch reason {
            case .notConfigured, .catalogUnreadable:
                return failure.presentation.summary
            case .loginRequired:
                return "Sign in to add this device to the tailnet."
            case .signedOut:
                return "Sign in to add this device to the tailnet again."
            case .notReady(let detail):
                return sentence(detail) + " If an admin must approve this device, authorize it "
                    + "in the network's admin console."
            case .misconfigured(let detail):
                return sentence(detail) + " Edit the network to fix it."
            case .startFailed(let detail):
                return sentence(detail) + " Check the network's settings."
            case .unreachable(let detail):
                return detail
            case .timedOut:
                return "The network did not answer in time."
            }
        }
        switch status ?? .stopped {
        case .failed(let detail) where !detail.isEmpty, .waiting(let detail) where !detail.isEmpty:
            return sentence(detail)
        default:
            return nil
        }
    }

    private static func sentence(_ text: String) -> String {
        text.hasSuffix(".") ? text : text + "."
    }

    /// "Online · Direct · 12 ms": whatever the overlay reports, in order.
    static func peerSummary(_ peer: OverlayPeer) -> String {
        var parts: [String] = []
        if let isOnline = peer.isOnline {
            parts.append(isOnline ? "Online" : "Offline")
        }
        if let isDirect = peer.isDirect {
            parts.append(isDirect ? "Direct" : "Relayed")
        }
        if let latency = peer.latency {
            parts.append(latencyText(latency))
        }
        return parts.joined(separator: " · ")
    }

    /// "Connected · 10.144.144.9/24 · 2 peers", or why the network does
    /// not run.
    static func assignedNetworkSummary(_ network: OverlayAssignedNetwork) -> String {
        if let error = network.error {
            return "Not running: " + error
        }
        guard network.isRunning else { return "Connecting…" }
        var parts = ["Connected"]
        if let address = network.address {
            parts.append(address)
        }
        parts.append(network.peerCount == 1 ? "1 peer" : "\(network.peerCount) peers")
        return parts.joined(separator: " · ")
    }

    static func latencyText(_ latency: Duration) -> String {
        let milliseconds = latency / .milliseconds(1)
        return milliseconds < 1 ? "<1 ms" : "\(Int(milliseconds.rounded())) ms"
    }
}

/// A value the user may need elsewhere (an address, a node ID): tap to
/// copy, with a checkmark and a VoiceOver announcement as confirmation.
struct OverlayCopyableRow: View {
    let title: String
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            copied = true
            AccessibilityNotification.Announcement("Copied").post()
        } label: {
            LabeledContent {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.footnote)
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(copied ? Color.green : Color.accentColor)
                }
            } label: {
                Text(title)
                    .foregroundStyle(.primary)
            }
            .contentShape(.rect)
        }
        // A list row, not a tinted button: only the copy symbol is accented.
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint(copied ? "Copied" : "Copies to the clipboard")
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// The first row of a network's screen: a tinted badge for the state, the
/// few-word summary with one line under it, and the network's one action
/// at the trailing edge (which also shows when it is busy).
private struct OverlayStatusHeader<Action: View>: View {
    let summary: String
    let detail: String?
    let symbol: String
    let tone: OverlayStatusTone
    @ViewBuilder let action: Action
    @ScaledMetric(relativeTo: .body) private var badgeSize = 36.0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: badgeSize * 0.4, weight: .semibold))
                .foregroundStyle(tone.color)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: badgeSize, height: badgeSize)
                .background(tone.color.opacity(0.15), in: .circle)
                .accessibilityHidden(true)
            // The detail runs under the button too, so the button's width
            // never squeezes it into a narrow column. The button already
            // pads the title's line, so no extra spacing.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(summary)
                        .font(.body.weight(.semibold))
                        .contentTransition(.opacity)
                        .accessibilityLabel("Status: \(summary)")
                    Spacer(minLength: 0)
                    action
                }
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The status row's button shape, shared by every state so it keeps its
/// place as it changes.
private struct OverlayStatusActionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .fixedSize()
    }
}

/// The status button's label, wide enough for every state's title so the
/// button keeps its size as Connect turns into Cancel and Disconnect.
private struct OverlayStatusActionLabel: View {
    let title: String
    var isBusy = false
    @ScaledMetric(relativeTo: .subheadline) private var minWidth = 84.0

    var body: some View {
        HStack(spacing: 6) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .frame(minWidth: minWidth)
    }
}

/// One peer of a network's node: name, addresses, reachability.
private struct OverlayPeerRow: View {
    let peer: OverlayPeer
    /// The addresses are physical paths (ZeroTier), not overlay addresses.
    var showsPaths = false
    /// Offers Add Host… for this peer; nil where it cannot be a Host.
    var onAddHost: (() -> Void)?

    var body: some View {
        Group {
            if let onAddHost {
                // Adding a Host is what a peer is for here, so the whole row
                // does it; copying stays in the context menu.
                Button(action: onAddHost) {
                    HStack {
                        details
                        Spacer(minLength: 8)
                        Image(systemName: "plus.circle")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Adds this peer as a Host")
            } else {
                details
            }
        }
        .contextMenu {
            if let onAddHost {
                Button(action: onAddHost) {
                    Label("Add Host…", systemImage: "plus")
                }
            }
            ForEach(showsPaths ? [] : peer.addresses, id: \.self) { address in
                Button {
                    UIPasteboard.general.string = address
                } label: {
                    Label("Copy \(address)", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private var details: some View {
        let summary = OverlayStatusCopy.peerSummary(peer)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let isOnline = peer.isOnline {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(isOnline ? .green : .secondary)
                        .accessibilityHidden(true)
                }
                Text(peer.name ?? peer.id)
            }
            if !peer.addresses.isEmpty {
                Text(
                    (showsPaths ? "Path: " : "")
                        + peer.addresses.joined(separator: ", "))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
            if !summary.isEmpty {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One network: its status with the one action it needs next (Sign In,
/// Connect, Cancel, or Disconnect), this device, its peers, its settings,
/// and Edit, Sign Out, and Delete.
struct OverlayNetworkDetailView: View {
    let store: OverlayNetworkStore
    let networkID: OverlayNetwork.ID
    let onHostAdded: (Host.ID) -> Void
    /// Set for a network just added: a Tailscale network starts its
    /// sign-in (or Connect, with an auth key) when the screen opens.
    var startsOnAppear = false
    @State private var didStartOnAppear = false
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingMachineIDReset = false
    @State private var deleteFailed = false
    @State private var addHostRequest: OverlayPeerHostRequest?
    @State private var pendingOnboardingHostID: Host.ID?
    /// The Sign In in progress: owned here rather than by `.task(id:)`,
    /// which a navigation push can start twice for one request.
    @State private var signInTask: Task<Void, Never>?
    @State private var signInToken: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Injected app-wide by `ContentView`; absent in previews, where peers
    /// offer no Add Host….
    @Environment(HostStore.self) private var hostStore: HostStore?

    var body: some View {
        Group {
            if let network = store.network(id: networkID) {
                content(network)
            } else {
                ContentUnavailableView("Network Removed", systemImage: "network.slash")
            }
        }
        .task {
            if store.network(id: networkID)?.kind == .zerotier {
                await store.prepareZeroTierIdentity()
            }
        }
        .task {
            // Once: coming back from Diagnostics runs this task again.
            guard startsOnAppear, !didStartOnAppear else { return }
            didStartOnAppear = true
            guard let network = store.network(id: networkID), network.kind == .tailscale else {
                return
            }
            switch store.primaryAction(for: network) {
            case .signIn: startSignIn()
            case .connect: await store.connect(networkID)
            case .connecting, .disconnect: break
            }
        }
        .task {
            // Sign-in, approval, and address assignment complete on their
            // own; follow them while this screen is visible.
            while !Task.isCancelled {
                await store.refreshStatus(networkID)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        // Leaving the screen abandons a sign-in it started.
        .onDisappear { cancelSignIn() }
        .sheet(item: $addHostRequest, onDismiss: {
            // As in Hosts, wait for the form to close before onboarding can
            // present its first-connection trust alert (#359, #426).
            guard let id = pendingOnboardingHostID else { return }
            pendingOnboardingHostID = nil
            onHostAdded(id)
        }) { request in
            if let hostStore {
                HostFormView(store: hostStore, prefill: request.draft) { saved in
                    pendingOnboardingHostID = saved.id
                }
            }
        }
    }

    private func content(_ network: OverlayNetwork) -> some View {
        let status = store.statuses[networkID] ?? .stopped
        let failure = store.connectFailures[networkID]
        let isStartingSignIn = signInTask != nil
        let action: OverlayNetworkPrimaryAction =
            isStartingSignIn ? .connecting : store.primaryAction(for: network)
        let isConnecting = action == .connecting
        let details = store.details[networkID] ?? OverlayNodeDetails()
        let signedOut = store.signedOut.contains(networkID)
        let isSigningOut = store.signingOut.contains(networkID)
        let needsSignIn = store.needsSignIn(network)
        // Sign Out only once there may be a login to forget, and while it
        // runs even though the network already needs a new sign-in.
        let offersSignOut = network.kind == .tailscale && (!needsSignIn || isSigningOut)
        return List {
            Section {
                OverlayStatusHeader(
                    summary: isConnecting
                        ? (isStartingSignIn ? "Preparing sign-in…" : "Connecting…")
                        : OverlayStatusCopy.summary(
                            status, failure: failure, signedOut: signedOut,
                            needsSignIn: needsSignIn),
                    detail: (isConnecting
                        ? nil : OverlayStatusCopy.explanation(status, failure: failure))
                        ?? OverlayStatusCopy.statusDetail(
                            action, kind: network.kind, isStartingSignIn: isStartingSignIn,
                            peers: details.peers),
                    symbol: isConnecting
                        ? "ellipsis"
                        : OverlayStatusCopy.symbol(
                            status, failure: failure, signedOut: signedOut,
                            needsSignIn: needsSignIn),
                    tone: isConnecting
                        ? .busy
                        : OverlayStatusCopy.tone(
                            status, failure: failure, signedOut: signedOut,
                            needsSignIn: needsSignIn)
                ) {
                    statusAction(
                        action, isStartingSignIn: isStartingSignIn, isSigningOut: isSigningOut)
                }
                if case .waiting = status,
                    case .easytierConfigServer(_, let machineID, _, _) = network.settings
                {
                    Text(
                        "In the EasyTier console, assign a network to the device with machine ID "
                            + "\(machineID.uuidString.lowercased()).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let signOutFailure = store.signOutFailures[networkID] {
                    Text(
                        "Heeler signed this device out and forgot its login, but could not reach "
                            + "the coordination server (\(signOutFailure.presentation.summary)). "
                            + "Remove the device in the tailnet's admin console if it is still "
                            + "listed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.snappy, value: action)

            deviceSection(network, details: details, isOnline: status.isOnline)

            if !details.assignedNetworks.isEmpty {
                assignedNetworksSection(details.assignedNetworks)
            }

            // Before the node is online its peer list says nothing useful.
            if status.isOnline, let peers = details.peers {
                peersSection(peers, kind: network.kind)
            }

            if network.kind == .zerotier {
                Section {
                    NavigationLink {
                        OverlayDiagnosticsView(store: store, networkID: networkID)
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                }
            }

            Section("Settings") {
                LabeledContent("Type", value: network.kind.displayName)
                settingsRows(network)
            }

            Section {
                if offersSignOut {
                    Button(role: .destructive) {
                        isConfirmingSignOut = true
                    } label: {
                        if isSigningOut {
                            HStack {
                                ProgressView()
                                Text("Signing Out…")
                            }
                        } else {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                        }
                    }
                    .disabled(isSigningOut || isConnecting)
                }
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete Network", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } footer: {
                if offersSignOut {
                    Text(
                        "Sign Out logs this device out of the tailnet and forgets its login; "
                            + "Hosts stay disconnected until you sign in again.")
                }
            }
        }
        .navigationTitle(network.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            OverlayNetworkFormView(store: store, editing: network)
        }
        .confirmationDialog(
            "Delete \(network.displayName)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Network", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Hosts that use this network stop connecting until you choose another network for them.")
        }
        .confirmationDialog(
            "Sign out of \(network.displayName)?",
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await store.signOut(networkID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This device is logged out of the tailnet and its login is deleted. Hosts "
                    + "using this network disconnect and stay disconnected until you tap Sign In "
                    + "here, which signs in automatically if an auth key is saved.")
        }
        .confirmationDialog(
            "Reset the machine ID?",
            isPresented: $isConfirmingMachineIDReset,
            titleVisibility: .visible
        ) {
            Button("Reset Machine ID", role: .destructive) {
                try? store.resetMachineID(networkID)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The EasyTier console then lists this device as a new one, which needs a "
                    + "network assigned again. Hosts on this network reconnect afterwards.")
        }
        .alert("Could not delete the network", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    /// The status row's trailing button. While busy it spins and cancels;
    /// Sign In, the step a new network waits on, is the prominent one.
    @ViewBuilder
    private func statusAction(
        _ action: OverlayNetworkPrimaryAction, isStartingSignIn: Bool, isSigningOut: Bool
    ) -> some View {
        switch action {
        case .disconnect:
            Button {
                Task { await store.disconnect(networkID) }
            } label: {
                OverlayStatusActionLabel(title: "Disconnect")
            }
            .buttonStyle(.bordered)
            .modifier(OverlayStatusActionStyle())
        case .connecting:
            Button {
                store.cancelConnect(networkID)
                cancelSignIn()
            } label: {
                OverlayStatusActionLabel(title: "Cancel", isBusy: true)
            }
            .buttonStyle(.bordered)
            .modifier(OverlayStatusActionStyle())
            .accessibilityLabel(isStartingSignIn ? "Cancel sign-in" : "Cancel connecting")
        case .signIn:
            Button(action: startSignIn) {
                OverlayStatusActionLabel(title: "Sign In")
            }
            .buttonStyle(.borderedProminent)
            .modifier(OverlayStatusActionStyle())
            .disabled(isSigningOut)
        case .connect:
            Button {
                Task { await store.connect(networkID) }
            } label: {
                OverlayStatusActionLabel(title: "Connect")
            }
            .buttonStyle(.bordered)
            .modifier(OverlayStatusActionStyle())
            .disabled(isSigningOut)
        }
    }

    /// Starts the node and opens its login page once it has one. A newer
    /// Sign In or Cancel supersedes this one, which then opens nothing.
    private func startSignIn() {
        signInTask?.cancel()
        let token = UUID()
        signInToken = token
        signInTask = Task {
            let url = await store.signIn(networkID)
            guard !Task.isCancelled, signInToken == token else { return }
            signInTask = nil
            signInToken = nil
            if let url { openURL(url) }
        }
    }

    private func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        signInToken = nil
    }

    /// Add Host… for a peer that has an overlay address, prefilled with it.
    private func addHostAction(for peer: OverlayPeer, kind: OverlayKind) -> (() -> Void)? {
        let candidate = OverlayPeerCandidate(peer: peer)
        guard hostStore != nil, OverlayPeerList.offersPeers(kind), !candidate.addresses.isEmpty else {
            return nil
        }
        return {
            addHostRequest = OverlayPeerHostRequest(
                draft: HostDraft(overlayPeer: candidate, networkID: networkID))
        }
    }

    /// ZeroTier reports the node's peers across every network it joined,
    /// with physical paths (public IP/port) rather than overlay addresses,
    /// so they are labelled as such and not offered for copying. Its roots
    /// (planet and moons) are listed apart from the ordinary nodes.
    @ViewBuilder
    private func peersSection(_ peers: [OverlayPeer], kind: OverlayKind) -> some View {
        if kind == .zerotier {
            zeroTierPeerSections(peers)
        } else {
            let groups = OverlayPeerList.groupedByNetwork(peers)
            if groups.count > 1 || groups.first?.network != nil {
                // A config server's networks, one section each.
                ForEach(groups, id: \.network) { group in
                    plainPeersSection(group.peers, kind: kind, title: "Peers · \(group.network ?? "")")
                }
            } else {
                plainPeersSection(peers, kind: kind)
            }
        }
    }

    /// The networks an EasyTier config server assigned this device.
    private func assignedNetworksSection(_ networks: [OverlayAssignedNetwork]) -> some View {
        Section {
            ForEach(networks) { assigned in
                VStack(alignment: .leading, spacing: 2) {
                    Text(assigned.name.isEmpty ? assigned.id : assigned.name)
                    Text(OverlayStatusCopy.assignedNetworkSummary(assigned))
                        .font(.footnote)
                        .foregroundStyle(assigned.error == nil ? Color.secondary : Color.red)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Assigned Networks")
        } footer: {
            Text(
                "Each network the config server assigned runs on its own. A Host reaches the "
                    + "one its address or name is on; an address on more than one of them is "
                    + "refused, so give the networks different subnets.")
        }
    }

    private func plainPeersSection(
        _ peers: [OverlayPeer], kind: OverlayKind, title: String? = nil
    ) -> some View {
        let showsPaths = kind == .zerotier
        let offersAddHost = hostStore != nil && OverlayPeerList.offersPeers(kind)
        return Section {
            if peers.isEmpty {
                Text("No peers")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Self.onlineFirst(peers)) { peer in
                    OverlayPeerRow(
                        peer: peer, showsPaths: showsPaths,
                        onAddHost: addHostAction(for: peer, kind: kind))
                }
            }
        } header: {
            Text(title ?? (showsPaths ? "ZeroTier Peers" : "Peers"))
        } footer: {
            if showsPaths {
                Text(
                    "Every node this device's ZeroTier has been in touch with, across all its "
                        + "ZeroTier networks. Paths are the public addresses the traffic takes, "
                        + "not addresses to use for a Host.")
            } else if offersAddHost, !peers.isEmpty {
                Text("Tap a peer to add it as a Host. Touch and hold to copy its address.")
            }
        }
    }

    /// Online (or unknown) peers before offline ones, otherwise as reported.
    static func onlineFirst(_ peers: [OverlayPeer]) -> [OverlayPeer] {
        peers.filter { $0.isOnline != false } + peers.filter { $0.isOnline == false }
    }

    @ViewBuilder
    private func zeroTierPeerSections(_ peers: [OverlayPeer]) -> some View {
        let roots = peers.filter { $0.role == "planet" || $0.role == "moon" }
        let members = peers.filter { $0.role != "planet" && $0.role != "moon" }
        Section {
            if members.isEmpty {
                Text("No members yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members) { peer in
                    OverlayPeerRow(peer: peer, showsPaths: true)
                }
            }
        } header: {
            Text("ZeroTier Members")
        } footer: {
            Text(
                "Nodes this device's ZeroTier has been in touch with, across all its ZeroTier "
                    + "networks. A member appears only after traffic first goes its way. Paths "
                    + "are the public addresses the traffic takes, not addresses to use for a "
                    + "Host; a member without one is relayed through a root.")
        }
        if !roots.isEmpty {
            Section {
                ForEach(roots) { peer in
                    OverlayPeerRow(peer: peer, showsPaths: true)
                }
            } header: {
                Text("ZeroTier Roots")
            } footer: {
                Text(
                    "The planet and moon servers this device uses to find members and relay "
                        + "traffic. On a self-hosted planet the root is often the network "
                        + "controller as well.")
            }
        }
    }

    /// This device on the network: node ID, name, and addresses.
    @ViewBuilder
    private func deviceSection(
        _ network: OverlayNetwork, details: OverlayNodeDetails, isOnline: Bool
    ) -> some View {
        let nodeID = network.kind == .zerotier ? store.zeroTierNodeID : details.nodeID
        // Until tsnet has a network map it reports the OS host name, not the
        // device name it will register; only trust the name once online.
        let hostname = isOnline ? details.hostname : nil
        if network.kind == .zerotier || nodeID != nil || hostname != nil
            || !details.addresses.isEmpty
        {
            Section {
                if network.kind == .zerotier {
                    if let nodeID {
                        OverlayCopyableRow(title: "Node ID", value: nodeID)
                    } else {
                        LabeledContent("Node ID", value: "Created on first connect")
                    }
                }
                if let hostname {
                    LabeledContent("Name", value: hostname)
                }
                ForEach(details.addresses, id: \.self) { address in
                    OverlayCopyableRow(
                        title: Self.addressTitle(address, among: details.addresses), value: address)
                }
                // Rarely needed (support, admin APIs), so after what a Host uses.
                if network.kind != .zerotier, let nodeID {
                    OverlayCopyableRow(title: "Node ID", value: nodeID)
                }
            } header: {
                Text("This Device")
            } footer: {
                if network.kind == .zerotier {
                    Text(ZeroTierNodeIDCopy.authorizationHint)
                }
            }
        }
    }

    /// "IPv4" / "IPv6" where the device has both, so two rows do not both
    /// read "Address".
    static func addressTitle(_ address: String, among addresses: [String]) -> String {
        let isIPv6: (String) -> Bool = { $0.contains(":") }
        guard addresses.contains(where: isIPv6), addresses.contains(where: { !isIPv6($0) }) else {
            return "Address"
        }
        return isIPv6(address) ? "IPv6" : "IPv4"
    }

    @ViewBuilder
    private func settingsRows(_ network: OverlayNetwork) -> some View {
        switch network.settings {
        case .tailscale(let hostname, let controlURL):
            LabeledContent("Device name", value: hostname)
            LabeledContent("Coordination server", value: controlURL?.absoluteString ?? "Tailscale")
            LabeledContent("Auth key", value: store.hasSecret(for: network) ? "Saved" : "None")
        case .zerotier(let networkID, let moons, let planet):
            LabeledContent("Network ID", value: networkID)
                .textSelection(.enabled)
            LabeledContent("Planet", value: planet == nil ? "ZeroTier default" : "Custom")
            ForEach(moons, id: \.self) { moon in
                LabeledContent(
                    "Moon",
                    value: "\(OverlayNetwork.hex(moon.worldID, digits: 16)) "
                        + "via \(OverlayNetwork.hex(moon.seed, digits: 10))")
                    .textSelection(.enabled)
            }
        case .easytier(let networkName, let peers, let hostname, let ipv4):
            LabeledContent("Network name", value: networkName)
            LabeledContent("Device name", value: hostname)
            LabeledContent("Address", value: ipv4 ?? "Assigned by the network")
            LabeledContent("Peers", value: peers.joined(separator: "\n"))
        case .easytierConfigServer(let server, let machineID, let hostname, let requireEncryption):
            LabeledContent("Source", value: "Config Server")
            LabeledContent("Server", value: server)
            LabeledContent("Encryption", value: requireEncryption ? "Required" : "Not required")
            if let token = store.secretText(for: network)
                .flatMap(OverlayNetwork.maskedConfigServerToken)
            {
                LabeledContent("User", value: token)
            }
            LabeledContent("Device name", value: hostname)
            OverlayCopyableRow(title: "Machine ID", value: machineID.uuidString.lowercased())
            Button(role: .destructive) {
                isConfirmingMachineIDReset = true
            } label: {
                Label("Reset Machine ID", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(.red)
            }
        }
    }

    private func delete() {
        do {
            try store.remove(networkID)
            dismiss()
        } catch {
            deleteFailed = true
        }
    }
}

/// Add/edit form for an Overlay Network. Secrets go straight to the Keychain
/// through the store; a blank secret field keeps the stored one when editing.
struct OverlayNetworkFormView: View {
    let store: OverlayNetworkStore
    var editing: OverlayNetwork?
    /// Called with a new network's id after it is saved, before the form
    /// closes; not called when editing.
    var onAdded: ((OverlayNetwork.ID) -> Void)?
    @State private var draft: OverlayNetworkDraft
    @State private var saveError: String?
    @State private var isImportingPlanet = false
    @State private var planetError: String?
    @Environment(\.dismiss) private var dismiss

    init(
        store: OverlayNetworkStore, editing: OverlayNetwork? = nil,
        onAdded: ((OverlayNetwork.ID) -> Void)? = nil
    ) {
        self.store = store
        self.editing = editing
        self.onAdded = onAdded
        _draft = State(
            initialValue: editing.map {
                OverlayNetworkDraft(network: $0, configServerURL: store.secretText(for: $0))
            } ?? OverlayNetworkDraft())
    }

    private var hasStoredSecret: Bool {
        editing.map(store.hasSecret(for:)) ?? false
    }

    private var canSave: Bool {
        draft.canSave(hasStoredSecret: hasStoredSecret)
    }

    /// ZeroTier: this network's custom planet, imported from Files.
    private var planetSection: some View {
        Section {
            LabeledContent(
                "Planet",
                value: draft.planet.map { "Custom (\($0.count) bytes)" } ?? "ZeroTier default")
            Button {
                isImportingPlanet = true
            } label: {
                Label(
                    draft.planet == nil ? "Import Planet File…" : "Replace Planet File…",
                    systemImage: "square.and.arrow.down")
            }
            if draft.planet != nil {
                Button(role: .destructive) {
                    draft.planet = nil
                    planetError = nil
                } label: {
                    Label("Use ZeroTier's Planet", systemImage: "arrow.uturn.backward")
                }
            }
        } header: {
            Text("Custom Planet")
        } footer: {
            if let planetError {
                Text(planetError)
                    .foregroundStyle(.red)
            } else {
                Text(
                    "Optional, for a network whose controller runs on self-hosted roots: the "
                        + "planet file their operator provides (as made by mkworld). Only this "
                        + "network uses it; other ZeroTier networks keep their own planet.")
            }
        }
        .fileImporter(isPresented: $isImportingPlanet, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url):
                do {
                    draft.planet = try OverlayNetworkStore.readZeroTierPlanet(from: url)
                    planetError = nil
                } catch {
                    planetError = (error as? OverlayNetworkStoreError)?.message
                        ?? OverlayNetworkStoreError.zeroTierPlanetNotSaved.message
                }
            case .failure:
                planetError = OverlayNetworkStoreError.zeroTierPlanetNotSaved.message
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // The kind decides every field below, so it comes first.
                    // It also decides where the secret lives; changing it on
                    // a saved network would orphan that secret.
                    Picker("Type", selection: $draft.kind) {
                        ForEach(OverlayKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .disabled(editing != nil)
                    plainField("Name", prompt: "Optional", text: $draft.name)
                }

                kindSection
            }
            .navigationTitle(editing == nil ? "Add Network" : "Edit Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .alert(
                "Could not save the network",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    @ViewBuilder
    private var kindSection: some View {
        switch draft.kind {
        case .tailscale:
            Section {
                plainField("Device name", prompt: "heeler", text: $draft.hostname)
            } header: {
                Text("Tailscale")
            } footer: {
                Text(
                    editing == nil
                        ? "How this device appears in your tailnet. After saving, Heeler opens "
                            + "your browser to sign it in."
                        : "How this device appears in your tailnet.")
            }
            Section {
                plainField(
                    "Coordination server", prompt: "Tailscale", text: $draft.controlURL)
                    .keyboardType(.URL)
                secretField("Auth key", prompt: "None")
            } header: {
                Text("Optional")
            } footer: {
                Text(
                    "Leave both blank for a Tailscale account. Enter a Headscale https URL to "
                        + "use your own server. An auth key signs in without the browser.")
            }
        case .zerotier:
            Section {
                plainField("Network ID", prompt: "16 hex digits", text: $draft.networkID)
                    .font(.body.monospaced())
                if let nodeID = store.zeroTierNodeID {
                    OverlayCopyableRow(title: "This device", value: nodeID)
                }
            } header: {
                Text("ZeroTier")
            } footer: {
                if let nodeID = store.zeroTierNodeID {
                    Text(
                        "The 16-digit network ID. This device's node ID: \(nodeID). "
                            + ZeroTierNodeIDCopy.authorizationHint)
                } else {
                    Text(
                        "The 16-digit network ID. This device creates its ZeroTier identity on "
                            + "first connect; its node ID then appears on the network's screen. "
                            + ZeroTierNodeIDCopy.authorizationHint)
                }
            }
            .task { await store.prepareZeroTierIdentity() }
            Section {
                ForEach($draft.moons) { $moon in
                    VStack(alignment: .leading) {
                        plainField("World ID", prompt: "10–16 hex digits", text: $moon.worldID)
                            .font(.body.monospaced())
                        plainField("Seed", prompt: "Root node ID", text: $moon.seed)
                            .font(.body.monospaced())
                    }
                }
                .onDelete { draft.moons.remove(atOffsets: $0) }
                Button {
                    draft.moons.append(OverlayNetworkDraft.MoonDraft())
                } label: {
                    Label("Add Moon", systemImage: "plus")
                }
            } header: {
                Text("Moons")
            } footer: {
                if !draft.invalidMoons.isEmpty {
                    Text(
                        "A moon's world ID is 10 to 16 hexadecimal digits and its seed is a "
                            + "10-digit node ID; neither may be zero.")
                        .foregroundStyle(.red)
                } else {
                    Text(
                        "Optional extra roots, as in zerotier-cli orbit: the moon's world ID and "
                            + "the node ID of one of its roots.")
                }
            }
            planetSection
        case .easytier:
            Section {
                Picker("Source", selection: $draft.easyTierSource) {
                    Text("Manual").tag(OverlayNetwork.EasyTierSource.manual)
                    Text("Config Server").tag(OverlayNetwork.EasyTierSource.configServer)
                }
                .pickerStyle(.segmented)
            } footer: {
                if draft.easyTierSource == .configServer {
                    Text(
                        "The network comes from an EasyTier config server (its web console), "
                            + "which assigns it to this device.")
                }
            }
            if draft.easyTierSource == .configServer {
                easyTierConfigServerSection
            } else {
                easyTierManualSection
            }
        }
    }

    private var easyTierConfigServerSection: some View {
        Section {
            plainField("Server", prompt: "User name or server URL", text: $draft.configServer)
                .keyboardType(.URL)
            plainField("Device name", prompt: "heeler", text: $draft.hostname)
            Toggle("Require Encryption", isOn: $draft.requireEncryption)
            OverlayCopyableRow(title: "Machine ID", value: draft.machineID.uuidString.lowercased())
        } header: {
            Text("Config Server")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let url = draft.configServerURL {
                    Text("Connects to \(url)")
                        .font(.footnote.monospaced())
                    if let warning = EasyTierConfigServerCopy.transportWarning(for: url) {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } else if !draft.configServer.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(
                        "Enter a user name, or a udp://, tcp://, ws://, or wss:// server URL "
                            + "ending in your user name, such as udp://host:22020/user.")
                        .foregroundStyle(.red)
                }
                if !draft.requireEncryption {
                    Label(EasyTierConfigServerCopy.encryptionOffWarning, systemImage: "lock.open")
                        .foregroundStyle(.orange)
                }
                Text(EasyTierConfigServerCopy.formNote)
            }
        }
    }

    @ViewBuilder
    private var easyTierManualSection: some View {
        Section {
            plainField("Network name", prompt: "Required", text: $draft.networkName)
            secretField("Network secret", prompt: "Required")
            plainField("Device name", prompt: "heeler", text: $draft.hostname)
            plainField("Fixed IPv4", prompt: "DHCP (optional)", text: $draft.ipv4)
                .keyboardType(.numbersAndPunctuation)
            VStack(alignment: .leading, spacing: 4) {
                Text("Peers")
                TextField(
                    "Peers", text: $draft.peers,
                    prompt: Text("tcp://host:11010, one per line"), axis: .vertical)
                    .lineLimit(2...6)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .labelsHidden()
                    .accessibilityLabel("Peers")
            }
        } header: {
            Text("EasyTier")
        } footer: {
            if let invalid = draft.invalidPeers.first {
                Text("“\(invalid)” is not a peer such as tcp://host:11010 or udp://host:11010.")
                    .foregroundStyle(.red)
            } else if !draft.ipv4IsValid {
                Text(
                    "A fixed address is a private IPv4 address with a prefix, such as "
                        + "10.144.144.7/24 (not 0.x, 127.x, or 224 and up).")
                    .foregroundStyle(.red)
            } else if draft.ipv4IsHostPrefix {
                Text("EasyTier treats a /32 address as part of its /24. Use the network's own prefix.")
            } else {
                Text(
                    "Peers are URIs such as tcp://public.easytier.top:11010, one per line. "
                        + "Leave the fixed address blank to get one from the network.")
            }
        }
    }

    /// A titled row: the title stays visible beside what was typed, so a
    /// filled-in form still says what each value is.
    private func plainField(
        _ title: String, prompt: String, text: Binding<String>
    ) -> some View {
        LabeledContent {
            TextField(title, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                // A prompt alone is not a label; VoiceOver names the field.
                .accessibilityLabel(title)
        } label: {
            Text(title)
        }
    }

    private func secretField(_ title: String, prompt: String) -> some View {
        // No password content type: these are network secrets, not account
        // passwords, and must not be offered to (or saved by) AutoFill.
        LabeledContent {
            SecureField(
                title, text: $draft.secret,
                prompt: Text(hasStoredSecret ? "Blank keeps current" : prompt))
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel(title)
        } label: {
            Text(title)
        }
    }

    private func save() {
        guard canSave, let network = draft.makeNetwork(id: editing?.id ?? UUID()) else { return }
        do {
            if editing == nil {
                try store.add(network, secret: draft.secretUpdate)
                onAdded?(network.id)
            } else {
                try store.update(network, secret: draft.secretUpdate)
            }
        } catch {
            saveError = (error as? OverlayNetworkStoreError)?.message
                ?? "The network or its secret could not be saved."
            return
        }
        dismiss()
    }
}

enum ZeroTierNodeIDCopy {
    static let authorizationHint =
        "On a private network, an admin authorizes this node ID in ZeroTier Central or the "
        + "network's own controller."
}

enum EasyTierConfigServerCopy {
    static let formNote =
        "A user name uses the official server, config-server.easytier.cn. In the EasyTier "
        + "console, assign up to 8 networks to this device; Heeler only connects out and drops "
        + "their listeners. A Host on this network reaches the assigned network its address "
        + "or name is on, so give the networks different subnets. The server knows the "
        + "network secrets and decides which peers this device connects to."

    static let encryptionOffWarning =
        "Without required encryption, Heeler also uses a server that does not offer EasyTier's "
        + "encrypted connection, in clear text: anyone on the network path can read the user name "
        + "and the network secret, change the network the server sends, or pose as the server."

    /// The risk of a config server URL's transport, or nil for wss://, the
    /// only one that authenticates the server.
    static func transportWarning(for url: String) -> String? {
        switch URLComponents(string: url)?.scheme?.lowercased() {
        case "ws":
            return "ws:// sends the user name (the server's token) in clear text when it connects, "
                + "and nothing verifies the server. Prefer wss://."
        case "udp", "tcp":
            return "udp:// and tcp:// encrypt the session but do not verify the server: someone who "
                + "can intercept the connection could pose as it and learn the network secret. "
                + "Prefer wss:// on networks you do not trust."
        default:
            return nil
        }
    }
}

/// Settings › Overlay Networks › a network › Diagnostics: the node's raw
/// state, read-only, with Copy All for a bug report. Never starts the node.
struct OverlayDiagnosticsView: View {
    let store: OverlayNetworkStore
    let networkID: OverlayNetwork.ID
    @State private var diagnostics = OverlayDiagnostics()
    @State private var copied = false

    var body: some View {
        List {
            if diagnostics.isEmpty {
                ContentUnavailableView(
                    "No Diagnostics", systemImage: "stethoscope",
                    description: Text("Connect the network to see its state."))
            } else {
                Section("State") {
                    ForEach(Array(diagnostics.entries.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.label)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(entry.value)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    if diagnostics.events.isEmpty {
                        Text("No events yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(diagnostics.events.reversed().enumerated()), id: \.offset) { _, event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.date.formatted(date: .omitted, time: .standard))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(event.message)
                                .font(.callout)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Recent Events")
                } footer: {
                    Text("Newest first; the last 50 of this app session.")
                }
            }
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = diagnostics.text
                    copied = true
                    AccessibilityNotification.Announcement("Copied").post()
                } label: {
                    Label(copied ? "Copied" : "Copy All", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(diagnostics.isEmpty)
            }
        }
        .task {
            while !Task.isCancelled {
                diagnostics = await store.diagnostics(networkID)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
