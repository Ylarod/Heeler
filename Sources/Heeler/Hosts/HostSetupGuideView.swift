import SwiftUI
import UIKit

/// Links and commands the Setup Guide points at. The commands match the
/// README's "Adding a machine" section.
enum HostSetupGuide {
    /// The README's Installation section, which flows straight into the
    /// pairing steps.
    static let url = URL(string: "https://github.com/ZingerLittleBee/Heeler#installation")
    static let herdrInstallURL = URL(string: "https://herdr.dev/docs/install/")
    static let windowsGuideURL = URL(
        string: "https://github.com/ZingerLittleBee/Heeler/blob/main/docs/guides/windows-setup.md")
    static let pluginInstallCommand = "herdr plugin install ZingerLittleBee/Heeler/plugin --ref main --yes"
    static let pairCommand = "herdr plugin action invoke heeler.pair"
}

/// How the guide hands the user back to the Host list once the machine is
/// ready to add.
enum HostSetupGuideAction: Equatable {
    case scanToPair
    case addManually
}

enum HostSetupPlatform: String, CaseIterable, Identifiable {
    case unix
    case windows

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .unix: "macOS / Linux"
        case .windows: "Windows"
        }
    }
}

/// Step-by-step instructions for preparing a machine and adding it as a
/// Host. With `onAction`, the last step starts Pairing or the manual form;
/// without it, as under Settings, the guide is reference only.
struct HostSetupGuideView: View {
    var onAction: (@MainActor (HostSetupGuideAction) -> Void)? = nil
    /// Closes the guide where it is presented as a sheet.
    var onClose: (@MainActor () -> Void)? = nil
    @State private var platform: HostSetupPlatform = .unix

    var body: some View {
        Form {
            Section {
                Picker("Platform", selection: $platform) {
                    ForEach(HostSetupPlatform.allCases) { platform in
                        Text(platform.title).tag(platform)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Heeler connects over SSH to a machine that runs herdr.")
            }

            switch platform {
            case .unix: unixSteps
            case .windows: windowsSteps
            }

            if let url = HostSetupGuide.url {
                Section {
                    ExternalLinkRow("Full Guide on GitHub", systemImage: "book", destination: url)
                }
            }
        }
        .readableColumnPage()
        .navigationTitle("Setup Guide")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }

    @ViewBuilder
    private var unixSteps: some View {
        Section {
            SetupStep(
                number: 1, title: "Install herdr",
                detail: "Version 0.7.5 or newer, with Node 20 or newer."
            ) {
                if let url = HostSetupGuide.herdrInstallURL {
                    Link("herdr Install Guide", destination: url)
                        .font(.subheadline)
                }
            }
            SetupStep(
                number: 2, title: "Turn on SSH",
                detail: "On a Mac, turn on Remote Login in System Settings › General › Sharing. On Linux, run the OpenSSH server.")
            SetupStep(
                number: 3, title: "Show a Pairing Code",
                detail: "Run these on the machine. The second command shows a QR code."
            ) {
                CommandBlock(command: HostSetupGuide.pluginInstallCommand)
                CommandBlock(command: HostSetupGuide.pairCommand)
            }
            SetupStep(
                number: 4, title: "Scan It",
                detail: onAction == nil
                    ? "In Hosts, tap Scan to Pair and point the camera at the code."
                    : "Point the camera at the code. The machine is added as a Host."
            ) {
                if let onAction {
                    Button {
                        onAction(.scanToPair)
                    } label: {
                        // A Form row tints Label icons, which would vanish
                        // into the prominent button's fill.
                        Label("Scan to Pair", systemImage: "qrcode.viewfinder")
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var windowsSteps: some View {
        Section {
            SetupStep(
                number: 1, title: "Set Up herdr on Windows",
                detail: "Native Windows needs herdr 0.9.3 or newer and OpenSSH Server."
            ) {
                if let url = HostSetupGuide.windowsGuideURL {
                    Link("Windows Setup Guide", destination: url)
                        .font(.subheadline)
                }
            }
            SetupStep(
                number: 2, title: "Add the Host",
                detail: onAction == nil
                    ? "Windows Hosts are added by hand: in Hosts, tap Add Host and enter the address and login."
                    : "Windows Hosts are added by hand with their address and login."
            ) {
                if let onAction {
                    Button("Add Manually", systemImage: "plus") {
                        onAction(.addManually)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

/// One numbered step: a badge, a title, a sentence, and optional content
/// such as commands or the action that finishes the guide.
private struct SetupStep<Content: View>: View {
    let number: Int
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder var content: Content

    init(
        number: Int, title: LocalizedStringKey, detail: LocalizedStringKey,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.number = number
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number, format: .number)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.15), in: .circle)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 7 }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

/// A shell command with a Copy button, so it can be pasted into the
/// machine's terminal.
private struct CommandBlock: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                UIPasteboard.general.string = command
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.footnote.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(copied ? "Copied" : "Copy Command")
        }
        .padding(.leading, 10)
        .padding(.vertical, 6)
        .padding(.trailing, 4)
        .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 8))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

#Preview("Actions") {
    NavigationStack {
        HostSetupGuideView(onAction: { _ in }, onClose: {})
    }
}

#Preview("Reference") {
    NavigationStack {
        HostSetupGuideView()
    }
}
