import Foundation
import Observation

/// What the chip of another saved TV shows.
public struct TVGlanceState: Equatable, Sendable {
    public enum Reach: Equatable, Sendable { case unknown, reached, unreachable, localNetworkDenied, badToken }
    public let reach: Reach
    public let state: PowerState?        // nil until a first answer
    public let nowShowing: String?       // Header.nowShowing

    public init(reach: Reach, state: PowerState?, nowShowing: String?) {
        self.reach = reach
        self.state = state
        self.nowShowing = nowShowing
    }
}

/// Polls `/api/stats` of the saved TVs other than the active one. A TV that does not answer is
/// never shown as off: `state` stays nil.
@MainActor @Observable
public final class TVGlance {
    public private(set) var states: [UUID: TVGlanceState] = [:]

    @ObservationIgnored private let makeAPI: @Sendable (TVConfig) -> any GlasshouseAPI
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private var tvs: [UUID: TVConfig] = [:]
    /// The newest read issued per TV: only that one may apply its answer.
    @ObservationIgnored private var issued: [UUID: Int] = [:]
    @ObservationIgnored private var counter = 0

    public init(makeAPI: @escaping @Sendable (TVConfig) -> any GlasshouseAPI, interval: Duration = .seconds(30)) {
        self.makeAPI = makeAPI
        self.interval = interval
    }

    /// The TVs to watch: the saved ones minus the active one. Drops the state of the others at once.
    /// Returns the TVs that have nothing to show: those that joined and those that moved, which the
    /// caller may read at once with `refreshNow(only:)` rather than at the next round.
    @discardableResult
    public func update(tvs new: [TVConfig]) -> Set<UUID> {
        let old = tvs
        tvs = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for id in Array(states.keys) where tvs[id] == nil { states[id] = nil }
        for id in Array(issued.keys) where tvs[id] == nil { issued[id] = nil }
        var fresh: Set<UUID> = []
        for (id, tv) in tvs {
            if let was = old[id] {
                // A moved TV starts again as unknown rather than showing the old address's answer.
                if was.host != tv.host || was.port != tv.port {
                    states[id] = nil
                    fresh.insert(id)
                }
            } else {
                fresh.insert(id)
            }
        }
        return fresh
    }

    /// What every TV showed is old news (the app was away): each chip goes back to unknown until
    /// its next answer, and the reads already asked will land nothing.
    public func markStale() {
        for id in Array(states.keys) {
            states[id] = TVGlanceState(reach: .unknown, state: nil, nowShowing: nil)
        }
        issued = [:]
    }

    /// Polls every `interval` until cancelled. Waits one interval before its first round: the
    /// caller reads once with `refreshNow()` and then starts this.
    public func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { break }
            await refreshNow()
        }
    }

    /// One read of every TV, or of those in `ids`, at once. Each answer applies as it arrives. The
    /// client is rebuilt for every round, so a changed token is picked up.
    public func refreshNow(only ids: Set<UUID>? = nil) async {
        var jobs: [(TVConfig, Int, any GlasshouseAPI)] = []
        for tv in tvs.values where ids?.contains(tv.id) ?? true {
            counter += 1
            issued[tv.id] = counter
            jobs.append((tv, counter, makeAPI(tv)))
        }
        await withTaskGroup(of: (TVConfig, Int, TVGlanceState).self) { group in
            for (tv, seq, api) in jobs {
                group.addTask { (tv, seq, await Self.read(api)) }
            }
            for await (tv, seq, state) in group {
                // Cancelled, superseded by a newer read, removed or moved meanwhile: discard.
                guard !Task.isCancelled, issued[tv.id] == seq,
                      let now = tvs[tv.id], now.host == tv.host, now.port == tv.port else { continue }
                states[tv.id] = state
            }
        }
    }

    nonisolated private static func read(_ api: any GlasshouseAPI) async -> TVGlanceState {
        do {
            let stats = try await api.get("/api/stats", as: Stats.self)
            return TVGlanceState(reach: .reached, state: PowerState.from(stats),
                                 nowShowing: Header(stats: stats).nowShowing)
        } catch {
            switch error {
            case .localNetworkDenied: return TVGlanceState(reach: .localNetworkDenied, state: nil, nowShowing: nil)
            case .badToken: return TVGlanceState(reach: .badToken, state: nil, nowShowing: nil)
            default: return TVGlanceState(reach: .unreachable, state: nil, nowShowing: nil)
            }
        }
    }
}
