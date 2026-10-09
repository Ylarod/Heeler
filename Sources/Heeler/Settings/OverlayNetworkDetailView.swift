import HeelerOverlay
import SwiftUI
import UIKit

/// One network: a status card with the switch (or the step in progress,
/// or Sign In) and this device's address, then the network's machines.
/// Edit, Copy Node ID, Sign Out, and Delete are in the … menu.
struct OverlayNetworkDetailView: View {
    let store: OverlayNetworkStore
    let networkID: OverlayNetwork.ID
    let onHostAdded: (Host.ID) -> Void
    /// Set for a network just added or signed in from the list: a Tailscale
    /// network starts its sign-in (or Connect, with an auth key) when the
    /// screen opens.
    var startsOnAppear = false
    @State private var didStartOnAppear = false
    @State private var isEditing = false
    @State private var isEnteringAuthKey = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingMachineIDReset = false
    @State private var deleteFailed = false
    @State private var authKeyError: String?
    @State private var hostRequest: HostFormRequest?
    @State private var pendingOnboardingHostID: Host.ID?
    /// The Sign In in progress: owned here rather than by `.task(id:)`,
    /// which a navigation push can start twice for one request.
    @State private var signInTask: Task<Void, Never>?
    @State private var signInToken: UUID?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Injected app-wide by `ContentView`; absent in previews, where
    /// machines offer no Add Host….
    @Environment(HostStore.self) private var hostStore: HostStore?

    private static let adminConsoleURL = URL(string: "https://login.tailscale.com/admin/machines")

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
        .sheet(item: $hostRequest, onDismiss: {
            // As in Hosts, wait for the form to close before onboarding can
            // present its first-connection trust alert (#359, #426).
            guard let id = pendingOnboardingHostID else { return }
            pendingOnboardingHostID = nil
            onHostAdded(id)
        }) { request in
            if let hostStore {
                switch request {
                case .add(let request):
                    HostFormView(store: hostStore, prefill: request.draft, focusesUsername: true) {
                        saved in
                        pendingOnboardingHostID = saved.id
                    }
                case .edit(let host):
                    HostFormView(store: hostStore, editing: host)
                }
            }
        }
    }

    private func content(_ network: OverlayNetwork) -> some View {
        let status = store.statuses[networkID] ?? .stopped
        let details = store.details[networkID] ?? OverlayNodeDetails()
        let isStartingSignIn = signInTask != nil
        let headline = OverlayNetworkHeadline(
            network: network, store: store, isStartingSignIn: isStartingSignIn)
        let control = store.control(for: network)
        let isSigningOut = control == .signingOut
        // Before the node is online its peer list says nothing useful.
        let peers = status.isOnline ? details.peers : nil
        let searchesMachines = OverlayPeerList.offersPeers(network.kind) && !(peers ?? []).isEmpty
        let isSearching = searchesMachines && !query.trimmingCharacters(in: .whitespaces).isEmpty
        return List {
            if isSearching {
                searchResults(peers ?? [], kind: network.kind)
            } else {
                statusSection(
                    network, headline: headline, control: control, status: status, details: details,
                    isStartingSignIn: isStartingSignIn)

                if network.kind == .zerotier {
                    zeroTierDeviceSection
                }

                if !details.assignedNetworks.isEmpty {
                    assignedNetworksSection(details.assignedNetworks)
                }

                if let peers {
                    peersSection(peers, kind: network.kind)
                        .disabled(isSigningOut)
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
            }
        }
        .modifier(
            MachineSearch(
                isEnabled: searchesMachines, query: $query,
                prompt: network.kind == .tailscale ? "Machines" : "Peers"))
        .onChange(of: searchesMachines) { _, searches in
            if !searches { query = "" }
        }
        .navigationTitle(network.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                moreMenu(
                    network, nodeID: network.kind == .zerotier ? nil : details.nodeID,
                    control: control, isStartingSignIn: isStartingSignIn)
            }
        }
        .sheet(isPresented: $isEditing) {
            OverlayNetworkFormView(store: store, editing: network)
        }
        .sheet(isPresented: $isEnteringAuthKey) {
            TailscaleAuthKeySheet { signIn(withAuthKey: $0) }
        }
        .confirmationDialog(
            "Delete \(network.displayName)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Network", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(OverlayNetworkCopy.deleteMessage)
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
        .alert(
            "Could not save the auth key",
            isPresented: Binding(
                get: { authKeyError != nil },
                set: { if !$0 { authKeyError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authKeyError ?? "")
        }
    }

    // MARK: Status

    /// The status card: what the network is doing, its switch or the step
    /// in progress, the sign-in or approval it waits on, and this device's
    /// address once it has one.
    private func statusSection(
        _ network: OverlayNetwork, headline: OverlayNetworkHeadline, control: OverlayNetworkControl,
        status: OverlayNodeStatus, details: OverlayNodeDetails, isStartingSignIn: Bool
    ) -> some View {
        let offersSignIn = isStartingSignIn || control == .signIn
        return Section {
            VStack(alignment: .leading, spacing: 14) {
                OverlayStatusHeader(headline: headline) {
                    // While the browser sign-in is being prepared, the
                    // card's own button shows it.
                    if !isStartingSignIn {
                        OverlayNetworkControlView(
                            network: network, store: store,
                            onCancel: {
                                store.cancelConnect(networkID)
                                cancelSignIn()
                            })
                    }
                }
                if offersSignIn {
                    signInButtons(isStartingSignIn: isStartingSignIn)
                } else if headline.isAwaitingApproval, network.tailscaleControlURL == nil,
                    let url = Self.adminConsoleURL
                {
                    Link(destination: url) {
                        Label("Open Admin Console", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .fontWeight(.semibold)
                    .accessibilityHint("Opens the tailnet's machines in the browser to approve this device")
                }
            }
            .padding(.vertical, 4)
            .animation(.snappy, value: headline)
            if status.isOnline, !details.addresses.isEmpty {
                OverlayDeviceAddresses(name: details.hostname, addresses: details.addresses)
            }
        } footer: {
            if let footer = statusFooter(
                network, headline: headline, control: control, status: status,
                offersSignIn: offersSignIn)
            {
                Text(footer)
            }
        }
    }

    /// Sign In with Browser, which shows its own progress while the login
    /// page is prepared, and the auth-key alternative (Cancel meanwhile).
    private func signInButtons(isStartingSignIn: Bool) -> some View {
        VStack(spacing: 12) {
            OverlayActivityButton(
                title: isStartingSignIn ? "Opening Browser…" : "Sign In with Browser",
                style: .filled, isLoading: isStartingSignIn, action: startSignIn)
            Button(isStartingSignIn ? "Cancel" : "Use an Auth Key Instead") {
                if isStartingSignIn {
                    store.cancelConnect(networkID)
                    cancelSignIn()
                } else {
                    isEnteringAuthKey = true
                }
            }
            // Its own tap target, not the row's.
            .buttonStyle(.borderless)
            .accessibilityLabel(isStartingSignIn ? "Cancel sign-in" : "Use an auth key instead")
        }
        .frame(maxWidth: .infinity)
    }

    /// What the card's state means for Hosts, or what happens next.
    private func statusFooter(
        _ network: OverlayNetwork, headline: OverlayNetworkHeadline, control: OverlayNetworkControl,
        status: OverlayNodeStatus, offersSignIn: Bool
    ) -> String? {
        if let signOutFailure = store.signOutFailures[networkID] {
            return "Heeler signed this device out and forgot its login, but could not reach "
                + "the coordination server (\(signOutFailure.presentation.summary)). Remove "
                + "the device in the tailnet's admin console if it is still listed."
        }
        if case .waiting = status,
            case .easytierConfigServer(_, let machineID, _, _) = network.settings
        {
            return "In the EasyTier console, assign a network to the device with machine ID "
                + "\(machineID.uuidString.lowercased())."
        }
        if offersSignIn {
            return "\(network.deviceName ?? "This device") joins the tailnet as its own device. "
                + "Its address and the tailnet's machines appear here afterwards."
        }
        switch control {
        case .connecting:
            return "Hosts on this network wait for it."
        case .signingOut, .signIn:
            return nil
        case .toggle:
            break
        }
        if headline.isAwaitingApproval {
            guard let server = network.tailscaleControlURL?.host() else {
                return "Heeler joins on its own once approved."
            }
            return "Heeler joins on its own once the device is approved on \(server)."
        }
        if headline.tone == .failed {
            return "Turn the switch on to try again. If it keeps failing, check the internet "
                + "connection, or the network's settings in Edit."
        }
        return nil
    }

    /// ZeroTier's node ID is needed before the first connect, to authorize
    /// it, so it stays on the screen rather than in the … menu.
    private var zeroTierDeviceSection: some View {
        Section {
            if let nodeID = store.zeroTierNodeID {
                OverlayCopyableRow(title: "Node ID", value: nodeID)
            } else {
                LabeledContent("Node ID", value: "Created on first connect")
            }
        } header: {
            Text("This Device")
        } footer: {
            Text(ZeroTierNodeIDCopy.authorizationHint)
        }
    }

    // MARK: Machines

    @ViewBuilder
    private func peersSection(_ peers: [OverlayPeer], kind: OverlayKind) -> some View {
        if kind == .zerotier {
            zeroTierPeerSections(peers)
        } else {
            let groups = OverlayPeerList.groupedByNetwork(peers)
            if groups.count > 1 || groups.first?.network != nil {
                // A config server's networks, one section each.
                ForEach(groups, id: \.network) { group in
                    machinesSection(group.peers, kind: kind, network: group.network)
                }
            } else {
                machinesSection(peers, kind: kind)
            }
        }
    }

    private func machinesSection(
        _ peers: [OverlayPeer], kind: OverlayKind, network: String? = nil
    ) -> some View {
        let noun = kind == .tailscale ? "Machines" : "Peers"
        return Section {
            if peers.isEmpty {
                emptyMachines(kind)
            } else {
                ForEach(OverlayPeerList.sorted(peers.map(OverlayPeerCandidate.init))) { candidate in
                    machineRow(candidate)
                }
            }
        } header: {
            Text(network.map { "\(noun) · \($0)" } ?? noun)
        } footer: {
            if hostStore != nil, !peers.isEmpty {
                Text(
                    "Tap a \(kind == .tailscale ? "machine" : "peer") to add it as a Host. Touch "
                        + "and hold to copy its address.")
            }
        }
    }

    @ViewBuilder
    private func emptyMachines(_ kind: OverlayKind) -> some View {
        if kind == .tailscale {
            ContentUnavailableView {
                Label("Only This Device So Far", systemImage: OverlayKind.glyphSymbol)
            } description: {
                Text(
                    "Install Tailscale on your Mac and sign in with the same account. It appears "
                        + "here, ready to add as a Host.")
            }
        } else {
            Text("No peers yet")
                .foregroundStyle(.secondary)
        }
    }

    private func searchResults(_ peers: [OverlayPeer], kind: OverlayKind) -> some View {
        let matches = OverlayPeerList.sorted(
            OverlayPeerList.filter(peers.map(OverlayPeerCandidate.init), query: query))
        return Section {
            if matches.isEmpty {
                Text(kind == .tailscale ? "No matching machines" : "No matching peers")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(matches) { candidate in
                    machineRow(candidate)
                }
            }
        } footer: {
            Text("Matches names and addresses.")
        }
    }

    private func machineRow(_ candidate: OverlayPeerCandidate) -> some View {
        let host = hostStore.flatMap {
            OverlayPeerList.host(for: candidate, networkID: networkID, among: $0.hosts)
        }
        let canAdd = hostStore != nil && !candidate.addresses.isEmpty
        return OverlayMachineRow(
            candidate: candidate, isHost: host != nil,
            onAdd: canAdd
                ? {
                    hostRequest = .add(
                        OverlayPeerHostRequest(
                            draft: HostDraft(overlayPeer: candidate, networkID: networkID)))
                } : nil,
            onEditHost: host.map { host in { hostRequest = .edit(host) } })
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

    /// ZeroTier reports the node's peers across every network it joined,
    /// with physical paths (public IP/port) rather than overlay addresses,
    /// so they are labelled as such and not offered for copying. Its roots
    /// (planet and moons) are listed apart from the ordinary nodes.
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
                    ZeroTierPeerRow(peer: peer)
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
                    ZeroTierPeerRow(peer: peer)
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

    // MARK: Menu

    /// Everything but the switch: Edit, what support may ask for, and the
    /// destructive actions, which confirm first.
    private func moreMenu(
        _ network: OverlayNetwork, nodeID: String?, control: OverlayNetworkControl,
        isStartingSignIn: Bool
    ) -> some View {
        // Sign Out only once there may be a login to forget.
        let offersSignOut = network.kind == .tailscale && !store.needsSignIn(network)
        return Menu {
            Button {
                isEditing = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            if let nodeID {
                Button {
                    UIPasteboard.general.string = nodeID
                    AccessibilityNotification.Announcement("Copied").post()
                } label: {
                    Label("Copy Node ID", systemImage: "doc.on.doc")
                }
            }
            Divider()
            if case .easytierConfigServer = network.settings {
                Button(role: .destructive) {
                    isConfirmingMachineIDReset = true
                } label: {
                    Label("Reset Machine ID", systemImage: "arrow.counterclockwise")
                }
            }
            if offersSignOut {
                Button(role: .destructive) {
                    isConfirmingSignOut = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(control == .connecting || isStartingSignIn)
            }
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete Network", systemImage: "trash")
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        // Nothing to change while the device leaves the tailnet.
        .disabled(control == .signingOut)
    }

    // MARK: Actions

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

    /// Saves the auth key like Edit would, then signs in with it: no
    /// browser unless the key is refused.
    private func signIn(withAuthKey key: String) {
        guard let network = store.network(id: networkID) else { return }
        do {
            try store.update(network, secret: key)
        } catch {
            authKeyError = (error as? OverlayNetworkStoreError)?.message
                ?? "The auth key could not be saved in the Keychain."
            return
        }
        startSignIn()
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

/// The Host form a machine opens: a new Host prefilled with it, or the
/// Host that already reaches it.
private enum HostFormRequest: Identifiable {
    case add(OverlayPeerHostRequest)
    case edit(Host)

    var id: UUID {
        switch self {
        case .add(let request): request.id
        case .edit(let host): host.id
        }
    }
}

/// Machine search, offered once there are machines to search.
private struct MachineSearch: ViewModifier {
    let isEnabled: Bool
    @Binding var query: String
    let prompt: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(
                text: $query, placement: .navigationBarDrawer(displayMode: .always),
                prompt: prompt)
        } else {
            content
        }
    }
}

/// The top of the status card: a tinted badge for the state, the title and
/// line under it, and the network's switch (or the step in progress) at the
/// trailing edge, below them at accessibility text sizes.
private struct OverlayStatusHeader<Trailing: View>: View {
    let headline: OverlayNetworkHeadline
    @ViewBuilder let trailing: Trailing
    @ScaledMetric(relativeTo: .body) private var badgeSize = 36.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(spacing: 12) {
                Image(systemName: headline.symbol)
                    .font(.system(size: badgeSize * 0.42, weight: .semibold))
                    .foregroundStyle(headline.tone.color)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: badgeSize, height: badgeSize)
                    .background(headline.tone.color.opacity(0.15), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline.title)
                        .font(.body.weight(.semibold))
                        .contentTransition(.opacity)
                    if let subtitle = headline.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Status: \(headline.title)" + (headline.subtitle.map { ", \($0)" } ?? ""))
            }
            trailing
        }
    }
}

/// This device's addresses on the network: the one to share in large type
/// with a copy button, the rest under it. Touch and hold copies any.
private struct OverlayDeviceAddresses: View {
    let name: String?
    let addresses: [String]
    @State private var copied = false

    var body: some View {
        let primary = addresses.first { !$0.contains(":") } ?? addresses.first ?? ""
        VStack(alignment: .leading, spacing: 2) {
            Text(name.map { "This device · \($0)" } ?? "This device")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text(primary)
                    .font(.title2.monospaced().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    copy(primary)
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.body.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.12), in: .circle)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy \(primary)")
            }
            ForEach(addresses.filter { $0 != primary }, id: \.self) { address in
                Text(address)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            ForEach(addresses, id: \.self) { address in
                OverlayCopyAddressButton(address: address, among: addresses) { copy(address) }
            }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private func copy(_ address: String) {
        UIPasteboard.general.string = address
        copied = true
        AccessibilityNotification.Announcement("Copied").post()
    }
}

/// "Copy IPv4" with the address under it, in a context menu.
private struct OverlayCopyAddressButton: View {
    let address: String
    let among: [String]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text("Copy \(OverlayStatusCopy.addressTitle(address, among: among))")
                Text(address)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
    }
}

/// A machine on the network: online dot, name, the address a Host would
/// use and how it is reached, and Add (or a Host tag once a Host reaches
/// it). Touch and hold copies its addresses.
private struct OverlayMachineRow: View {
    let candidate: OverlayPeerCandidate
    let isHost: Bool
    /// nil where it cannot be a Host (no address, or no Host store).
    let onAdd: (() -> Void)?
    let onEditHost: (() -> Void)?

    var body: some View {
        let primaryAction = onEditHost ?? onAdd
        HStack(spacing: 10) {
            Button {
                primaryAction?()
            } label: {
                details
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(primaryAction == nil)
            .accessibilityHint(
                isHost ? "Edits the Host on this machine" : onAdd == nil ? "" : "Adds it as a Host")
            if isHost {
                Text("Host")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.fill.tertiary, in: .capsule)
                    .accessibilityHidden(true)
            } else if let onAdd {
                Button("Add", action: onAdd)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .fontWeight(.semibold)
                    .accessibilityLabel("Add \(candidate.displayName) as a Host")
            }
        }
        .contextMenu {
            if let onEditHost {
                Button(action: onEditHost) {
                    Label("Edit Host…", systemImage: "pencil")
                }
            } else if let onAdd {
                Button(action: onAdd) {
                    Label("Add Host…", systemImage: "plus")
                }
            }
            if !candidate.addresses.isEmpty {
                Divider()
            }
            ForEach(candidate.addresses, id: \.self) { address in
                OverlayCopyAddressButton(address: address, among: candidate.addresses) {
                    UIPasteboard.general.string = address
                }
            }
        }
    }

    private var details: some View {
        let reachability = OverlayStatusCopy.peerReachability(candidate.peer)
        let address = candidate.ipv4 ?? candidate.addresses.first
        return HStack(spacing: 10) {
            if let isOnline = candidate.isOnline {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(isOnline ? .green : .secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayName)
                    .foregroundStyle(candidate.isOffline ? .secondary : .primary)
                Group {
                    switch (address, reachability.isEmpty) {
                    case (let address?, false):
                        Text("\(Text(address).monospaced()) · \(reachability)")
                    case (let address?, true):
                        Text(address).monospaced()
                    case (nil, _):
                        Text(reachability)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isHost ? "Host" : "")
    }
}

/// A ZeroTier member or root: its paths are where traffic goes, not
/// addresses to use for a Host, so it offers neither Add nor Copy.
private struct ZeroTierPeerRow: View {
    let peer: OverlayPeer

    var body: some View {
        let summary = OverlayStatusCopy.peerSummary(peer)
        VStack(alignment: .leading, spacing: 2) {
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
                Text("Path: " + peer.addresses.joined(separator: ", "))
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

/// "Use an Auth Key Instead": one field, then Sign In with it.
private struct TailscaleAuthKeySheet: View {
    let onSignIn: (String) -> Void
    @State private var key = ""
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // No password content type: an auth key is not an
                    // account password and must not be offered to AutoFill.
                    SecureField("Auth key", text: $key, prompt: Text("tskey-auth-…"))
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isFocused)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                } footer: {
                    Text(
                        "Create one in the tailnet's admin console under Settings › Keys. Heeler "
                            + "keeps it in the Keychain and signs in with it again after a sign-out.")
                }
            }
            .navigationTitle("Auth Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign In", action: signIn)
                        .disabled(trimmedKey.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }

    private func signIn() {
        guard !trimmedKey.isEmpty else { return }
        onSignIn(trimmedKey)
        dismiss()
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
