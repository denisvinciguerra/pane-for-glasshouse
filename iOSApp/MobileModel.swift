import Observation
import PaneKit
import SwiftUI

/// The iOS app's state around `AppModel`: the glance at the other TVs, the iPad's column order,
/// and the foreground life. Nothing runs while the app is in the background.
@MainActor @Observable final class MobileModel {
    let app: AppModel
    /// The state of the saved TVs other than the active one, for their chips.
    let glance: TVGlance
    /// iPad, side by side: the remote in the left column rather than the right one.
    var remoteOnLeft: Bool {
        didSet { defaults.set(remoteOnLeft, forKey: Self.remoteOnLeftKey) }
    }

    /// The More tab's last page, HDMI or Stats, to open it on again: kept here so that no layout
    /// holds tab state of its own.
    var morePage: PaneTab = .hdmi

    private static let remoteOnLeftKey = "remoteOnLeft"

    @ObservationIgnored private let defaults: UserDefaults
    /// The glance's first read and then its loop, while the app is in the foreground.
    @ObservationIgnored private var glanceTask: Task<Void, Never>?

    init(app: AppModel, defaults: UserDefaults = .standard) {
        self.app = app
        self.defaults = defaults
        let store = app.store
        // TVGlance builds its clients on the main actor, when a round starts.
        glance = TVGlance(makeAPI: { tv in MainActor.assumeIsolated { Self.client(for: tv, in: store) } })
        remoteOnLeft = defaults.bool(forKey: Self.remoteOnLeftKey)
        followTVs()
    }

    /// The token goes only to the address saved now: a TV moved or removed since the glance's last
    /// `update(tvs:)` is read without it, and the glance drops that answer.
    private static func client(for tv: TVConfig, in store: TVConfigStore) -> any GlasshouseAPI {
        let saved = store.tvs.first { $0.id == tv.id }
        let endpoint = saved?.host == tv.host && saved?.port == tv.port
            ? store.endpoint(for: tv)
            : Endpoint(host: tv.host, port: tv.port)
        return GlasshouseClient(endpoint: endpoint, timeout: Discovery.detailTimeout)
    }

    /// The saved TVs other than the one the session talks to (all of them during the demo).
    private var otherTVs: [TVConfig] { app.store.tvs.filter { $0.id != app.activeID } }

    /// Keeps the glance on `otherTVs` as TVs are added, removed, moved or made active: observed
    /// once, then again after each change, so no chip outlives its TV or reads an old address. In
    /// the foreground, a TV that joins (the one just left for another chip, or a new one) or moves
    /// is read at once rather than at the next round.
    private func followTVs() {
        let tvs = withObservationTracking { otherTVs } onChange: { [weak self] in
            // Called before the change: read the new list once it is made.
            Task { @MainActor in self?.followTVs() }
        }
        let fresh = glance.update(tvs: tvs)
        guard glanceTask != nil, !fresh.isEmpty else { return }
        let glance = glance
        Task { await glance.refreshNow(only: fresh) }
    }

    /// Foreground: the session reads the active TV at once and then every 2 s, the glance reads the
    /// others at once and then every 30 s. Background: everything stops, and what the session and
    /// the glance show is marked old, so that the return shows no state hours old (a TV gone to
    /// deep standby only answers by its timeout). `.inactive` (a call, the
    /// Control Center, a system alert) changes nothing; coming back from it reads again only what
    /// the system refused, which the local network prompt just answered may now allow.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            guard glanceTask == nil else {
                app.reactivate()
                if glance.states.values.contains(where: { $0.reach == .localNetworkDenied }) { startGlance() }
                return
            }
            app.resume()
            glance.update(tvs: otherTVs)
            startGlance()
        case .background:
            app.pause()
            glanceTask?.cancel()
            glanceTask = nil
            glance.markStale()
        default:
            break
        }
    }

    /// The glance's first read at once, then its loop; replaces the one running.
    private func startGlance() {
        glanceTask?.cancel()
        let glance = glance
        glanceTask = Task {
            await glance.refreshNow()
            // It waits one interval before its first round.
            await glance.run()
        }
    }
}
