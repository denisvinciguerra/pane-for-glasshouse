import Foundation

/// A Glasshouse server found on the network: `.found`, or `.needsToken` when no known token opened it.
public struct DiscoveredTV: Equatable, Sendable {
    public let host: String
    public let outcome: ProbeOutcome

    public init(host: String, outcome: ProbeOutcome) {
        self.host = host
        self.outcome = outcome
    }
}

public enum DiscoveryEnd: Equatable, Sendable { case finished, localNetworkDenied }

public struct Discovery: Sendable {
    public static let probeTimeout: TimeInterval = 1.2
    /// For the stats of a TV already found: one in standby takes seconds to answer them.
    public static let detailTimeout: TimeInterval = 8
    public static let width = 48

    private let ssdp: @Sendable () async -> SSDPResult
    private let localHosts: @Sendable () -> [String]
    private let probe: TVProbe

    public init(ssdp: @escaping @Sendable () async -> SSDPResult = { await SSDP.search() },
                localHosts: @escaping @Sendable () -> [String] = Subnet.localHosts,
                probe: TVProbe = TVProbe(makeAPI: { GlasshouseClient(endpoint: $0, timeout: Discovery.probeTimeout) },
                                         makeDetailAPI: { GlasshouseClient(endpoint: $0, timeout: Discovery.detailTimeout) })) {
        self.ssdp = ssdp
        self.localHosts = localHosts
        self.probe = probe
    }

    /// SSDP hosts first, then the sweep, each probed once on `port`, `width` at a time: without a token,
    /// then with the one in `tokensByHost` for that host (keys compared case-insensitively). A host
    /// never receives another TV's token; one that wants a token and has none is `.needsToken`. `found` receives each Glasshouse TV as soon as it answers. Ends
    /// `.localNetworkDenied` when nothing was found and either SSDP was refused or every probe was.
    public func run(port: Int = 8080, tokensByHost: [String: String], found: @escaping @MainActor (DiscoveredTV) -> Void) async -> DiscoveryEnd {
        let search = await ssdp()
        var seen = Set<String>()
        let hosts = (search.hosts + localHosts()).filter { seen.insert($0).inserted }

        var lowered: [String: String] = [:]
        for (host, token) in tokensByHost { lowered[host.lowercased()] = token }
        let tokens = lowered

        var probed = 0
        var denied = 0
        var reported = false
        let probe = self.probe
        await withTaskGroup(of: ProbeOutcome.self) { group in
            func collect(_ outcome: ProbeOutcome) {
                probed += 1
                switch outcome {
                case .localNetworkDenied: denied += 1
                case .found, .needsToken: reported = true
                default: break
                }
            }
            var running = 0
            for host in hosts {
                if Task.isCancelled { break }
                if running >= Self.width, let outcome = await group.next() {
                    running -= 1
                    collect(outcome)
                    if Task.isCancelled { break }
                }
                running += 1
                group.addTask {
                    let outcome = await probe.probe(host: host, port: port, token: nil, knownTokens: tokens[host.lowercased()].map { [$0] } ?? [])
                    switch outcome {
                    case .found, .needsToken: await found(DiscoveredTV(host: host, outcome: outcome))
                    default: break
                    }
                    return outcome
                }
            }
            for await outcome in group { collect(outcome) }
        }
        if !reported, search.denied || (probed > 0 && denied == probed) { return .localNetworkDenied }
        return .finished
    }
}
