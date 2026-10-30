import Foundation

/// A Glasshouse server found at an address, with the token that opened it (`nil` for an open server).
public struct FoundTV: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let token: String?
    public let mac: String?
    public let model: String?
    public let version: String

    public init(host: String, port: Int, token: String?, mac: String?, model: String?, version: String) {
        self.host = host; self.port = port; self.token = token
        self.mac = mac; self.model = model; self.version = version
    }

    /// The model before its first ".": "OLED65G45LW" for "OLED65G45LW.DEUQLJP".
    public var shortModel: String? {
        guard let model, !model.isEmpty else { return nil }
        return String(model.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }
}

public enum ProbeOutcome: Equatable, Sendable {
    case found(FoundTV), needsToken, badToken, notGlasshouse, unreachable, localNetworkDenied
}

/// Asks one address whether it is a Glasshouse server, and with which token.
public struct TVProbe: Sendable {
    public typealias MakeAPI = @Sendable (Endpoint) -> any GlasshouseAPI
    private let makeAPI: MakeAPI
    private let makeDetailAPI: MakeAPI?

    /// `makeDetailAPI` reads `/api/stats` (model and MAC); it may be slower than `makeAPI`, which
    /// finds hosts (a TV in standby answers caps at once and stats in seconds). Default: `makeAPI`.
    public init(makeAPI: @escaping MakeAPI = { GlasshouseClient(endpoint: $0) }, makeDetailAPI: MakeAPI? = nil) {
        self.makeAPI = makeAPI
        self.makeDetailAPI = makeDetailAPI
    }

    /// `token` non nil: the only one tried. Otherwise none, then `knownTokens` (empty and duplicates dropped).
    public func probe(host: String, port: Int, token: String?, knownTokens: [String]) async -> ProbeOutcome {
        var candidates: [String?] = []
        if let token {
            candidates = [token]
        } else {
            candidates = [nil]
            var seen = Set<String>()
            for t in knownTokens where !t.isEmpty && seen.insert(t).inserted { candidates.append(t) }
        }
        for candidate in candidates {
            let api = makeAPI(Endpoint(host: host, port: port, token: candidate))
            let detail = makeDetailAPI?(Endpoint(host: host, port: port, token: candidate)) ?? api
            switch await attempt(api, detail: detail) {
            case .found(let version, let stats):
                return .found(FoundTV(host: host, port: port, token: candidate, mac: stats?.mac,
                                      model: stats?.device?.model, version: version))
            case .badToken: continue
            case .notGlasshouse: return .notGlasshouse
            case .unreachable: return .unreachable
            case .localNetworkDenied: return .localNetworkDenied
            }
        }
        return token != nil ? .badToken : .needsToken
    }

    private enum Attempt {
        case found(version: String, stats: Stats?), badToken, notGlasshouse, unreachable, localNetworkDenied
    }

    private func attempt(_ api: any GlasshouseAPI, detail: any GlasshouseAPI) async -> Attempt {
        do {
            let caps = try await api.get("/api/caps", as: Caps.self)
            guard caps.ok else { return .notGlasshouse }
            return .found(version: caps.version, stats: try? await detail.get("/api/stats", as: Stats.self))
        } catch {
            switch error {
            case .badToken: return .badToken
            case .unreachable: return .unreachable
            case .localNetworkDenied: return .localNetworkDenied
            case .http(404): break // too old for /api/caps (R37)
            default: return .notGlasshouse
            }
        }
        do {
            let stats = try await detail.get("/api/stats", as: Stats.self)
            // Any JSON server answers 404 then something: only a MAC or a model says it is Glasshouse.
            guard stats.mac != nil || stats.device?.model != nil else { return .notGlasshouse }
            return .found(version: "", stats: stats)
        } catch {
            switch error {
            case .badToken: return .badToken
            case .unreachable: return .unreachable
            case .localNetworkDenied: return .localNetworkDenied
            default: return .notGlasshouse
            }
        }
    }
}
