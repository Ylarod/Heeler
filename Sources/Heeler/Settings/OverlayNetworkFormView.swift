import HeelerOverlay
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Add/edit form for an Overlay Network. Secrets go straight to the Keychain
/// through the store; a blank secret field keeps the stored one when editing.
/// Adding picks the kind first and ends with one button that says what
/// happens next (a Tailscale network then signs in or connects).
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

    /// The add button's title: what saving starts.
    private var addTitle: String {
        guard draft.kind == .tailscale else { return "Add Network" }
        return draft.secretUpdate == nil ? "Continue to Sign In" : "Add and Connect"
    }

    var body: some View {
        NavigationStack {
            Form {
                // The kind decides every field below, so it comes first.
                // It also decides where the secret lives; changing it on a
                // saved network would orphan that secret.
                if editing == nil {
                    kindPicker
                }
                Section {
                    if let editing {
                        LabeledContent("Type", value: editing.kind.displayName)
                    }
                    plainField("Name", prompt: "Optional", text: $draft.name)
                    if draft.kind == .tailscale {
                        plainField("Device name", prompt: "heeler", text: $draft.hostname)
                    }
                } footer: {
                    if draft.kind == .tailscale {
                        Text("How this device appears in your tailnet.")
                    }
                }

                kindSection
            }
            .navigationTitle(editing == nil ? "Add Network" : "Edit Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if editing != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!canSave)
                    }
                }
            }
            .modifier(
                OverlayFormBottomBar(isPresented: editing == nil) {
                    Button(action: save) {
                        Text(addTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                })
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
                NavigationLink {
                    TailscaleAdvancedForm(draft: $draft, hasStoredSecret: hasStoredSecret)
                } label: {
                    LabeledContent("Advanced", value: tailscaleAdvancedSummary)
                }
            } footer: {
                if !draft.controlURLIsValid {
                    Text("The coordination server must be an https URL. Fix it in Advanced.")
                        .foregroundStyle(.red)
                }
            }
            if let editing, let nodeID = store.details[editing.id]?.nodeID {
                Section {
                    OverlayCopyableRow(title: "Node ID", value: nodeID)
                } header: {
                    Text("This Device")
                } footer: {
                    Text("Support and admin tools may ask for it.")
                }
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

    /// Which optional Tailscale settings are set, beside Advanced.
    private var tailscaleAdvancedSummary: String {
        var parts: [String] = []
        if !draft.controlURL.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(draft.controlURLValue?.host() ?? "Invalid server")
        }
        if draft.secretUpdate != nil {
            parts.append("Auth key")
        } else if hasStoredSecret {
            parts.append("Auth key saved")
        }
        return parts.isEmpty ? "Optional" : parts.joined(separator: ", ")
    }

    /// The kinds side by side, each with what joining it takes. A header,
    /// not a row: a row clips to the section's larger corner radius, which
    /// cuts the outer corners of the first and last card.
    private var kindPicker: some View {
        Section {
        } header: {
            OverlayKindPicker(selection: $draft.kind)
                .textCase(nil)
                .listRowInsets(EdgeInsets())
                .padding(.top, 12)
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

/// Add Network's kind choice: a card per kind, side by side (stacked at
/// accessibility text sizes), each saying what joining it takes.
private struct OverlayKindPicker: View {
    @Binding var selection: OverlayKind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        layout {
            ForEach(OverlayKind.allCases, id: \.self) { kind in
                card(kind)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Type")
    }

    private func card(_ kind: OverlayKind) -> some View {
        let isSelected = selection == kind
        return Button {
            selection = kind
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                OverlayKindGlyph(kind: kind)
                Text(kind.displayName)
                    .font(.subheadline.weight(.semibold))
                    // Explicit colors: a section header dims its content.
                    .foregroundStyle(Color.primary)
                Text(Self.blurb(kind))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: .rect(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
            }
            .contentShape(.rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static func blurb(_ kind: OverlayKind) -> String {
        switch kind {
        case .tailscale: "Sign in with your account"
        case .zerotier: "Join by network ID"
        case .easytier: "Peers or a config server"
        }
    }
}

/// Tailscale's optional settings, one push away from the form: a Headscale
/// server and an auth key that signs in without the browser.
private struct TailscaleAdvancedForm: View {
    @Binding var draft: OverlayNetworkDraft
    let hasStoredSecret: Bool

    var body: some View {
        Form {
            Section {
                TextField("Coordination server", text: $draft.controlURL, prompt: Text("Tailscale"))
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Coordination Server")
            } footer: {
                if draft.controlURLIsValid {
                    Text(
                        "Leave blank for a Tailscale account. Enter an https URL to use your own "
                            + "Headscale server.")
                } else {
                    Text("Enter an https URL, such as https://headscale.example.com.")
                        .foregroundStyle(.red)
                }
            }
            Section {
                // No password content type: an auth key is not an account
                // password and must not be offered to (or saved by) AutoFill.
                SecureField(
                    "Auth key", text: $draft.secret,
                    prompt: Text(hasStoredSecret ? "Blank keeps current" : "None"))
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Auth Key")
            } footer: {
                Text("Signs this device in without the browser. Heeler keeps it in the Keychain.")
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The form's one button at the bottom, above the keyboard, with the
/// system's scroll edge effect where there is one.
private struct OverlayFormBottomBar<Bar: View>: ViewModifier {
    let isPresented: Bool
    @ViewBuilder let bar: Bar

    func body(content: Content) -> some View {
        if !isPresented {
            content
        } else if #available(iOS 26, *) {
            content.safeAreaBar(edge: .bottom) { bar }
        } else {
            content.safeAreaInset(edge: .bottom) {
                bar.background(Color(.systemGroupedBackground))
            }
        }
    }
}
