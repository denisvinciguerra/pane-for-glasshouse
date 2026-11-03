import Observation
import PaneKit

/// The live search for TVs on the network, for the add screen: results in the order they
/// answer, one per host.
@MainActor @Observable final class DiscoverySearch {
    enum Phase { case idle, searching, finished, denied }

    private(set) var phase: Phase = .idle
    private(set) var results: [DiscoveredTV] = []

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// The app came back to the foreground during the search: it starts again once if it ends
    /// refused or empty, since what it met may predate the user's answer.
    @ObservationIgnored private var retryAtEnd = false

    init(model: AppModel) {
        self.model = model
    }

    /// Cancels the previous search, clears the results and starts again. A stored token goes only
    /// to its own TV's address.
    func start() {
        task?.cancel()
        generation += 1
        retryAtEnd = false
        let current = generation
        results = []
        phase = .searching
        let discovery = model.discovery
        let tokens = model.store.tokensByHost
        task = Task { [weak self] in
            let end = await discovery.run(tokensByHost: tokens) { found in
                self?.receive(found, generation: current)
            }
            guard let self, !Task.isCancelled, generation == current else { return }
            phase = end == .localNetworkDenied ? .denied : .finished
            if retryAtEnd, wantsRetry { start() }
        }
    }

    /// The app is in the foreground again (iOS): back from the local network prompt or from
    /// Settings, the system may allow now what it refused. A search that ended refused or empty
    /// starts again; one still running does so at its end, if it ends that way.
    func retryAfterReturn() {
        switch phase {
        case .searching: retryAtEnd = true
        case .denied, .finished: if wantsRetry { start() }
        case .idle: break
        }
    }

    private var wantsRetry: Bool { phase == .denied || (phase == .finished && results.isEmpty) }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        if phase == .searching { phase = .idle }
    }

    private func receive(_ found: DiscoveredTV, generation: Int) {
        guard generation == self.generation else { return }
        if let index = results.firstIndex(where: { $0.host == found.host }) {
            results[index] = found
        } else {
            results.append(found)
        }
    }
}
