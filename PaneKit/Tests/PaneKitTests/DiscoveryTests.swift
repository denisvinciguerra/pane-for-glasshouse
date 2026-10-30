import XCTest
@testable import PaneKit

final class DiscoveryTests: XCTestCase {
    /// Records which hosts were probed and how many probes run at once; can hold probes until released.
    private actor Tracker {
        private(set) var started: [String] = []
        private(set) var running = 0
        private(set) var maxRunning = 0
        private var blocking = false
        private var blocked: [CheckedContinuation<Void, Never>] = []
        private var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

        func blockProbes() { blocking = true }

        func begin(_ host: String) async {
            started.append(host)
            running += 1
            maxRunning = max(maxRunning, running)
            if let w = waiter, started.count >= w.count { waiter = nil; w.continuation.resume() }
            if blocking { await withCheckedContinuation { blocked.append($0) } }
            else { await Task.yield() }
            running -= 1
        }

        func waitUntilStarted(_ count: Int) async {
            if started.count >= count { return }
            await withCheckedContinuation { waiter = (count, $0) }
        }

        func releaseAll() {
            blocking = false
            let all = blocked
            blocked = []
            all.forEach { $0.resume() }
        }
    }

    private struct HostAPI: GlasshouseAPI {
        let host: String
        let tracker: Tracker
        let answer: @Sendable (String) -> Result<Data, APIError>

        func get<T: Decodable & Sendable>(_ path: String, as: T.Type) async throws(APIError) -> T {
            if path == "/api/caps" { await tracker.begin(host) }
            let data: Data
            switch answer(host) {
            case .success(let d): data = d
            case .failure(let e): throw e
            }
            do { return try JSONDecoder().decode(T.self, from: path == "/api/caps" ? data : Fixture.data("stats")) }
            catch { throw .decoding("\(error)") }
        }
        func getText(_ path: String) async throws(APIError) -> String { throw .unreachable }
        func getData(_ path: String) async throws(APIError) -> Data { throw .unreachable }
        func send(_ command: Command) async throws(APIError) {}
    }

    private func discovery(
        ssdp: SSDPResult = SSDPResult(hosts: [], denied: false), local: [String] = [],
        tracker: Tracker = Tracker(),
        answer: @escaping @Sendable (String) -> Result<Data, APIError> = { _ in .success(Fixture.data("caps")) }
    ) -> Discovery {
        Discovery(ssdp: { ssdp }, localHosts: { local },
                  probe: TVProbe(makeAPI: { HostAPI(host: $0.host, tracker: tracker, answer: answer) }))
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [DiscoveredTV] = []
        func add(_ tv: DiscoveredTV) { lock.lock(); items.append(tv); lock.unlock() }
        var all: [DiscoveredTV] { lock.lock(); defer { lock.unlock() }; return items }
    }

    func testSSDPHostsAreProbedFirstAndOnce() async {
        let tracker = Tracker()
        let d = discovery(ssdp: SSDPResult(hosts: ["192.0.2.20"], denied: false),
                          local: ["192.0.2.20", "192.0.2.21"], tracker: tracker)
        _ = await d.run(tokensByHost: [:], found: { _ in })
        let started = await tracker.started
        // Probes start concurrently, so only the set and the count are stable.
        XCTAssertEqual(started.sorted(), ["192.0.2.20", "192.0.2.21"])
    }

    func testReportsFoundAndNeedsTokenOnly() async {
        let got = Collected()
        let d = discovery(local: ["192.0.2.1", "192.0.2.2", "192.0.2.3", "192.0.2.4"]) { host in
            switch host {
            case "192.0.2.1": return .success(Fixture.data("caps"))
            case "192.0.2.2": return .failure(.badToken)
            case "192.0.2.3": return .failure(.http(500))
            default: return .failure(.unreachable)
            }
        }
        let end = await d.run(tokensByHost: [:], found: { got.add($0) })
        XCTAssertEqual(end, .finished)
        let hosts = Set(got.all.map(\.host))
        XCTAssertEqual(hosts, ["192.0.2.1", "192.0.2.2"])
        for tv in got.all {
            if tv.host == "192.0.2.2" { XCTAssertEqual(tv.outcome, .needsToken) }
            else if case .found = tv.outcome {} else { XCTFail("\(tv)") }
        }
    }

    func testRunProbesTheGivenPort() async {
        final class Ports: @unchecked Sendable {
            private let lock = NSLock()
            private var items: Set<Int> = []
            func add(_ port: Int) { lock.lock(); items.insert(port); lock.unlock() }
            var all: Set<Int> { lock.lock(); defer { lock.unlock() }; return items }
        }
        let ports = Ports()
        let tracker = Tracker()
        let d = Discovery(ssdp: { SSDPResult(hosts: [], denied: false) },
                          localHosts: { ["192.0.2.1"] },
                          probe: TVProbe(makeAPI: { endpoint in
            ports.add(endpoint.port)
            return HostAPI(host: endpoint.host, tracker: tracker) { _ in .success(Fixture.data("caps")) }
        }))
        _ = await d.run(port: 8081, tokensByHost: [:], found: { _ in })
        XCTAssertEqual(ports.all, [8081])
    }

    func testNeverMoreThanWidthAtOnce() async {
        let tracker = Tracker()
        await tracker.blockProbes()
        let hosts = (1...120).map { "192.0.2.\($0)" }
        let d = discovery(local: hosts, tracker: tracker) { _ in .failure(.unreachable) }
        let task = Task { await d.run(tokensByHost: [:], found: { _ in }) }
        await tracker.waitUntilStarted(Discovery.width)
        for _ in 0..<50 { await Task.yield() }
        let (running, started) = await (tracker.running, tracker.started.count)
        XCTAssertEqual(running, Discovery.width)
        XCTAssertEqual(started, Discovery.width)
        await tracker.releaseAll()
        _ = await task.value
        let (count, most) = await (tracker.started.count, tracker.maxRunning)
        XCTAssertEqual(count, 120)
        XCTAssertLessThanOrEqual(most, Discovery.width)
    }

    func testHostOnlyReceivesItsOwnToken() async {
        final class Seen: @unchecked Sendable {
            private let lock = NSLock()
            private var items: [String: [String?]] = [:]
            func add(_ host: String, _ token: String?) { lock.lock(); items[host, default: []].append(token); lock.unlock() }
            func tokens(_ host: String) -> [String?] { lock.lock(); defer { lock.unlock() }; return items[host] ?? [] }
        }
        let seen = Seen()
        let tracker = Tracker()
        let got = Collected()
        let d = Discovery(ssdp: { SSDPResult(hosts: [], denied: false) },
                          localHosts: { ["192.0.2.1", "192.0.2.2"] },
                          probe: TVProbe(makeAPI: { endpoint in
            seen.add(endpoint.host, endpoint.token)
            return HostAPI(host: endpoint.host, tracker: tracker) { _ in
                endpoint.token == "secret" ? .success(Fixture.data("caps")) : .failure(.badToken)
            }
        }))
        let end = await d.run(tokensByHost: ["192.0.2.1": "secret"], found: { got.add($0) })
        XCTAssertEqual(end, .finished)
        XCTAssertEqual(seen.tokens("192.0.2.2"), [nil])
        XCTAssertEqual(seen.tokens("192.0.2.1"), [nil, "secret"])
        let byHost = Dictionary(uniqueKeysWithValues: got.all.map { ($0.host, $0.outcome) })
        XCTAssertEqual(byHost["192.0.2.2"], .needsToken)
        guard case .found(let tv) = byHost["192.0.2.1"] else { return XCTFail("\(byHost)") }
        XCTAssertEqual(tv.token, "secret")
    }

    func testEveryProbeDeniedEndsDenied() async {
        let d = discovery(local: ["192.0.2.1", "192.0.2.2"]) { _ in .failure(.localNetworkDenied) }
        let end = await d.run(tokensByHost: [:], found: { _ in })
        XCTAssertEqual(end, .localNetworkDenied)
    }

    func testSomeProbesNotDeniedEndsFinished() async {
        let d = discovery(local: ["192.0.2.1", "192.0.2.2"]) { $0 == "192.0.2.1" ? .failure(.localNetworkDenied) : .failure(.unreachable) }
        let end = await d.run(tokensByHost: [:], found: { _ in })
        XCTAssertEqual(end, .finished)
    }

    func testSSDPDeniedEndsDenied() async {
        let d = discovery(ssdp: SSDPResult(hosts: [], denied: true))
        let end = await d.run(tokensByHost: [:], found: { _ in })
        XCTAssertEqual(end, .localNetworkDenied)
    }

    func testSSDPDeniedButTVFoundEndsFinished() async {
        let d = discovery(ssdp: SSDPResult(hosts: [], denied: true), local: ["192.0.2.1"])
        let end = await d.run(tokensByHost: [:], found: { _ in })
        XCTAssertEqual(end, .finished)
    }

    func testNothingFoundEndsFinished() async {
        let d = discovery(local: ["192.0.2.1"]) { _ in .failure(.unreachable) }
        let end = await d.run(tokensByHost: [:], found: { _ in })
        XCTAssertEqual(end, .finished)
        let none = discovery()
        let end2 = await none.run(tokensByHost: [:], found: { _ in })
        XCTAssertEqual(end2, .finished)
    }

    func testCancellationStopsProbing() async {
        let tracker = Tracker()
        await tracker.blockProbes()
        let d = discovery(local: (1...120).map { "192.0.2.\($0)" }, tracker: tracker) { _ in .failure(.unreachable) }
        let task = Task { await d.run(tokensByHost: [:], found: { _ in }) }
        await tracker.waitUntilStarted(Discovery.width)
        task.cancel()
        await tracker.releaseAll()
        _ = await task.value
        let count = await tracker.started.count
        XCTAssertEqual(count, Discovery.width)
    }
}
