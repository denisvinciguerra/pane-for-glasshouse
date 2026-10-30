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

    init(model: AppModel) {
        self.model = model
    }

    /// Cancels the previous search, clears the results and starts again. A stored token goes only
    /// to its own TV's address.
    func start() {
        task?.cancel()
        generation += 1
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
        }
    }

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
