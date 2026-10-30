import Foundation
import Network

/// Asks macOS whether it refuses Pane's connections to the local network. `URLSession` hides the
/// reason in an object `NWPath` cannot read, so a trial `NWConnection` reports it instead.
public enum LocalNetworkCheck {
    /// True when the trial connection's first path says local network access is prohibited.
    /// False when access is allowed, the port is invalid, or nothing is known after `timeout`.
    public static func isDenied(host: String, port: Int, timeout: Duration = .seconds(1)) async -> Bool {
        guard (1...65535).contains(port), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        defer { connection.cancel() }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let gate = Gate(continuation)
            connection.stateUpdateHandler = { _ in
                if let path = connection.currentPath {
                    gate.finish(path.unsatisfiedReason == .localNetworkDenied)
                }
            }
            connection.start(queue: DispatchQueue(label: "fr.synlink.pane.localnetwork"))
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(timeout.components.seconds * 1000)
                + Int(timeout.components.attoseconds / 1_000_000_000_000_000))) {
                gate.finish(false)
            }
        }
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?

        init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

        func finish(_ result: Bool) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: result)
        }
    }
}
