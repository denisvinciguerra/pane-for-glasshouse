import Foundation
import Observation
import os
import Security

/// A TV the app knows. Its token is not here: it lives in a `SecretStore`.
public struct TVConfig: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var mac: String?

    public init(id: UUID = UUID(), name: String, host: String, port: Int = 8080, mac: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.mac = mac
    }
}

public protocol SecretStore: Sendable {
    func token(for id: UUID) -> String?
    /// `nil` deletes the token.
    func setToken(_ token: String?, for id: UUID)
}

/// Tokens as generic passwords: service "fr.synlink.pane", account the TV's id.
public final class KeychainSecretStore: SecretStore {
    private static let service = "fr.synlink.pane"
    private static let log = Logger(subsystem: "fr.synlink.pane", category: "keychain")

    /// Logs an unexpected status (never the token).
    private static func check(_ status: OSStatus, _ operation: String) {
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("Keychain \(operation, privacy: .public) failed: OSStatus \(status, privacy: .public)")
        }
    }

    public init() {}

    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: id.uuidString]
    }

    public func token(for id: UUID) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        Self.check(status, "read")
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setToken(_ token: String?, for id: UUID) {
        guard let token, !token.isEmpty else {
            Self.check(SecItemDelete(query(id) as CFDictionary), "delete")
            return
        }
        let data = Data(token.utf8)
        let status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(id)
            add[kSecValueData as String] = data
            Self.check(SecItemAdd(add as CFDictionary, nil), "add")
        } else {
            Self.check(status, "update")
        }
    }
}

/// The TVs and the active one, in the defaults ("tvs", "activeTV"); tokens go to the secrets.
@MainActor @Observable public final class TVConfigStore {
    private static let tvsKey = "tvs"
    private static let activeKey = "activeTV"

    public private(set) var tvs: [TVConfig]
    public var activeID: UUID? {
        didSet { defaults.set(activeID?.uuidString, forKey: Self.activeKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: any SecretStore

    public init(defaults: UserDefaults = .standard, secrets: SecretStore = KeychainSecretStore()) {
        self.defaults = defaults
        self.secrets = secrets
        tvs = defaults.data(forKey: Self.tvsKey).flatMap { try? JSONDecoder().decode([TVConfig].self, from: $0) } ?? []
        activeID = defaults.string(forKey: Self.activeKey).flatMap(UUID.init(uuidString:))
    }

    public var active: TVConfig? { tvs.first { $0.id == activeID } }

    /// Replaces the TV with the same id, or appends it; activates it when no TV is active.
    /// A `nil` or empty token deletes the stored one.
    public func upsert(_ tv: TVConfig, token: String?) {
        if let i = tvs.firstIndex(where: { $0.id == tv.id }) { tvs[i] = tv } else { tvs.append(tv) }
        save()
        secrets.setToken(token?.isEmpty == true ? nil : token, for: tv.id)
        if active == nil { activeID = tv.id }
    }

    /// Replaces a known TV (the MAC it reported, say), keeping its token. An unknown id changes nothing.
    public func update(_ tv: TVConfig) {
        guard let i = tvs.firstIndex(where: { $0.id == tv.id }), tvs[i] != tv else { return }
        tvs[i] = tv
        save()
    }

    /// Forgets a TV and its token. When it was the active one, the first other TV takes over,
    /// if any.
    public func remove(_ id: UUID) {
        tvs.removeAll { $0.id == id }
        save()
        secrets.setToken(nil, for: id)
        if activeID == id { activeID = tvs.first?.id }
    }

    public func token(for id: UUID) -> String? { secrets.token(for: id) }

    /// `nil` or empty deletes the token.
    public func setToken(_ token: String?, for id: UUID) {
        secrets.setToken(token?.isEmpty == true ? nil : token, for: id)
    }

    /// The tokens of the TVs by host (lowercased); TVs without a token are skipped and,
    /// when two TVs share a host, the first in the list wins.
    public var tokensByHost: [String: String] {
        var result: [String: String] = [:]
        for tv in tvs {
            guard let token = secrets.token(for: tv.id), !token.isEmpty else { continue }
            let key = tv.host.lowercased()
            if result[key] == nil { result[key] = token }
        }
        return result
    }

    /// The token of the TV stored at that host (case-insensitive) and port.
    public func token(forHost host: String, port: Int) -> String? {
        guard let tv = tvs.first(where: { $0.host.caseInsensitiveCompare(host) == .orderedSame && $0.port == port })
        else { return nil }
        let token = secrets.token(for: tv.id)
        return token?.isEmpty == true ? nil : token
    }

    /// Renames a TV; the name is trimmed and an empty one is ignored.
    public func rename(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = tvs.firstIndex(where: { $0.id == id }), tvs[i].name != name else { return }
        tvs[i].name = name
        save()
    }

    /// The TV already in the list that `found` is: same MAC (normalized), else same host
    /// (case ignored) and port.
    public func match(_ found: FoundTV) -> TVConfig? {
        if let mac = found.mac.flatMap(WakeOnLAN.normalized(mac:)),
           let tv = tvs.first(where: { $0.mac.flatMap(WakeOnLAN.normalized(mac:)) == mac }) {
            return tv
        }
        let foundMAC = found.mac.flatMap(WakeOnLAN.normalized(mac:))
        return tvs.first { tv in
            guard tv.host.caseInsensitiveCompare(found.host) == .orderedSame && tv.port == found.port else { return false }
            // Two TVs that swapped addresses must not merge: known, different MACs mean another TV.
            if let foundMAC, let stored = tv.mac.flatMap(WakeOnLAN.normalized(mac:)), stored != foundMAC { return false }
            return true
        }
    }

    /// The TV of the list, other than `id`, at that host (case ignored) and port.
    public func owner(host: String, port: Int, excluding id: UUID) -> TVConfig? {
        tvs.first { $0.id != id && $0.host.caseInsensitiveCompare(host) == .orderedSame && $0.port == port }
    }

    /// "TV", then "TV 2", "TV 3"… the first not used.
    public func nextName() -> String {
        let taken = Set(tvs.map(\.name))
        let first = String(localized: "TV", bundle: .module)
        if !taken.contains(first) { return first }
        var n = 2
        while taken.contains(String(localized: "TV \(n)", bundle: .module)) { n += 1 }
        return String(localized: "TV \(n)", bundle: .module)
    }

    /// Updates the TV `match` finds (address, port, MAC when known, token as found: `nil`
    /// deletes it, an open server) and keeps its id and name; otherwise adds a new TV named
    /// `name ?? nextName()`. Activates it when none is active. Returns the TV as written.
    @discardableResult public func add(_ found: FoundTV, name: String? = nil) -> TVConfig {
        let mac = found.mac.flatMap(WakeOnLAN.normalized(mac:))
        var tv: TVConfig
        if var existing = match(found) {
            existing.host = found.host
            existing.port = found.port
            if let mac { existing.mac = mac }
            tv = existing
        } else {
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            tv = TVConfig(name: trimmed.flatMap { $0.isEmpty ? nil : $0 } ?? nextName(),
                          host: found.host, port: found.port, mac: mac)
        }
        upsert(tv, token: found.token)
        return tv
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tvs) { defaults.set(data, forKey: Self.tvsKey) }
    }

    public func endpoint(for tv: TVConfig) -> Endpoint {
        Endpoint(host: tv.host, port: tv.port, token: secrets.token(for: tv.id))
    }
}
