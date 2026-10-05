import Foundation

/// Editable form state behind `HostFormView`, validated before it becomes a
/// catalog Host. Text-field friendly (port is a string) so the view stays
/// dumb and the rules stay testable.
struct HostDraft: Equatable, Sendable {
    var name = ""
    var address = ""
    var port = "22"
    var username = ""
    var authMethod: Host.AuthMethod = .deviceKey
    /// Blank means "keep the stored password" when editing.
    var password = ""
    var sessionName = ""
    /// Blank means a direct connection. When set, Address/Port above are
    /// resolved from the Jump Host, not from this device.
    var jumpAddress = ""
    var jumpPort = "22"
    /// Blank reuses the Host's own username.
    var jumpUsername = ""

    init() {}

    /// Prefill for editing an existing Host.
    init(host: Host) {
        name = host.name
        address = host.address
        port = String(host.port)
        username = host.username
        authMethod = host.authMethod
        sessionName = host.sessionName
        jumpAddress = host.jumpAddress
        jumpPort = String(host.jumpPort)
        jumpUsername = host.jumpUsername
    }

    /// Prefill for adding a copy of `host`: every field Edit prefills, the
    /// stored `password` for password authentication, and the next free
    /// numbered name among `existingNames` (display names).
    init(duplicating host: Host, password: String?, existingNames: [String]) {
        self.init(host: host)
        name = Self.duplicateName(of: host.displayName, existingNames: existingNames)
        if host.authMethod == .password {
            self.password = password ?? ""
        }
    }

    /// `name 2`, `name 3`, … — the first one not taken. A name that is
    /// already a numbered copy of an existing name (a plain number from 2)
    /// continues that count (`box 2` → `box 3`) instead of stacking numbers
    /// (`box 2 2`).
    static func duplicateName(of name: String, existingNames: [String]) -> String {
        let taken = Set(existingNames.map { $0.trimmingCharacters(in: .whitespaces) })
        var base = name.trimmingCharacters(in: .whitespaces)
        if let space = base.lastIndex(of: " ") {
            let number = base[base.index(after: space)...]
            let stem = String(base[..<space])
            if number.allSatisfy({ ("0"..."9").contains($0) }),
               number.first != "0", let value = Int(number), value >= 2,
               taken.contains(stem)
            {
                base = stem
            }
        }
        var count = 2
        while taken.contains("\(base) \(count)") {
            count += 1
        }
        return "\(base) \(count)"
    }

    var portNumber: Int? {
        guard let value = Int(port), (1...65535).contains(value) else { return nil }
        return value
    }

    var jumpPortNumber: Int? {
        guard let value = Int(jumpPort), (1...65535).contains(value) else { return nil }
        return value
    }

    var usesJumpHost: Bool {
        !jumpAddress.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isValid: Bool {
        let trimmedSessionName = sessionName.trimmingCharacters(in: .whitespaces)
        return !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && portNumber != nil
            && (trimmedSessionName.isEmpty || HerdrSessionName.isValid(trimmedSessionName))
            // A blank jump address disables the hop entirely, so its port only
            // has to parse when the hop is actually in use.
            && (!usesJumpHost || jumpPortNumber != nil)
    }

    /// Form-level validity including credential intent. A blank password can
    /// only mean "keep current" when the existing Host already used password
    /// authentication; new Hosts and Device Key -> Password changes require
    /// an actual secret to persist.
    func canSave(editing existingHost: Host?) -> Bool {
        guard isValid else { return false }
        guard authMethod == .password, password.isEmpty else { return true }
        return existingHost?.authMethod == .password
    }

    /// The catalog Host this draft describes, or nil while invalid. Pass the
    /// existing id when editing so the Host keeps its identity (and its
    /// Keychain password account).
    func makeHost(id: UUID = UUID()) -> Host? {
        guard isValid, let portNumber else { return nil }
        return Host(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespaces),
            port: portNumber,
            username: username.trimmingCharacters(in: .whitespaces),
            authMethod: authMethod,
            sessionName: sessionName.trimmingCharacters(in: .whitespaces),
            jumpAddress: jumpAddress.trimmingCharacters(in: .whitespaces),
            jumpPort: jumpPortNumber ?? 22,
            jumpUsername: jumpUsername.trimmingCharacters(in: .whitespaces))
    }

    /// What to hand `HostStore.add/update` as the password argument: a new
    /// secret to store, or nil for "leave storage as it is".
    var passwordUpdate: String? {
        guard authMethod == .password, !password.isEmpty else { return nil }
        return password
    }
}
