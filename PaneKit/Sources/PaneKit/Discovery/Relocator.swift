import Foundation

/// Finds a TV again by its MAC when its address changed: the add screen's search (SSDP, then the
/// sweep), without any token. The Mac's ARP table proves which host has the MAC; only when it has
/// no entry does an open server's word, the MAC in its /api/stats, count.
public struct Relocator: Sendable {
    public typealias Search = @Sendable (_ port: Int, _ found: @escaping @MainActor (DiscoveredTV) -> Void) async -> DiscoveryEnd

    private let search: Search
    private let macOf: @Sendable (String) async -> String?

    public init(search: @escaping Search = { await Discovery().run(port: $0, tokensByHost: [:], found: $1) },
                macOf: @escaping @Sendable (String) async -> String? = ARPTable.mac(of:)) {
        self.search = search
        self.macOf = macOf
    }

    /// The host of the first Glasshouse server on `port` whose MAC is `mac`; nil when the search ends
    /// without one. `excluding`: the current address, not checked. No token is sent: the session does
    /// that, to the host returned.
    public func locate(mac: String, port: Int, excluding: String) async -> String? {
        guard let wanted = WakeOnLAN.normalized(mac: mac) else { return nil }
        let (servers, yield) = AsyncStream<DiscoveredTV>.makeStream()
        let search = search
        let searching = Task {
            _ = await search(port) { tv in yield.yield(tv) }
            yield.finish()
        }
        defer { searching.cancel() }
        // Checked one by one, as they arrive: a slow ARP lookup does not hold the search back.
        for await tv in servers where tv.host != excluding {
            if await Self.mac(of: tv, macOf: macOf) == wanted { return tv.host }
        }
        return nil
    }

    /// The ARP table's MAC for the host; the one an open server reports only when the table has none
    /// (any server can put any MAC in its stats).
    private static func mac(of tv: DiscoveredTV, macOf: @Sendable (String) async -> String?) async -> String? {
        if let seen = await macOf(tv.host).flatMap(WakeOnLAN.normalized(mac:)) { return seen }
        if case .found(let server) = tv.outcome { return server.mac.flatMap(WakeOnLAN.normalized(mac:)) }
        return nil
    }
}

/// When the next search for a TV may start: 5 minutes after its first, 15 after its second, then
/// 60 after each one. A TV that answers again starts over (`reset`).
public struct RelocationThrottle: Sendable {
    /// The least time after a TV's first, second, then any later search before the next one.
    public static let intervals: [Duration] = [.seconds(5 * 60), .seconds(15 * 60), .seconds(60 * 60)]

    private var searches: [UUID: (last: ContinuousClock.Instant, count: Int)] = [:]

    public init() {}

    public mutating func allow(_ id: UUID, at now: ContinuousClock.Instant) -> Bool {
        let count = searches[id]?.count ?? 0
        if let last = searches[id]?.last, now - last < Self.intervals[min(count, Self.intervals.count) - 1] { return false }
        searches[id] = (now, count + 1)
        return true
    }

    /// The TV answered: its next search, if it is lost again, may start at once.
    public mutating func reset(_ id: UUID) {
        searches[id] = nil
    }
}
