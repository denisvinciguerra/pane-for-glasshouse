import XCTest
@testable import PaneKit

/// Hands out one `FakeAPI` per host and records every `makeAPI` call.
private final class Fakes: @unchecked Sendable {
    private let lock = NSLock()
    private var byHost: [String: FakeAPI] = [:]
    private(set) var built: [TVConfig] = []

    func api(_ host: String) -> FakeAPI {
        lock.withLock {
            if let a = byHost[host] { return a }
            let a = FakeAPI(); byHost[host] = a; return a
        }
    }
    func make(_ tv: TVConfig) -> any GlasshouseAPI {
        lock.withLock { built.append(tv) }
        return api(tv.host)
    }
    var builtCount: Int { lock.withLock { built.count } }
}

@MainActor
final class TVGlanceTests: XCTestCase {
    private func tv(_ name: String, _ host: String, id: UUID = UUID()) -> TVConfig {
        TVConfig(id: id, name: name, host: host)
    }
    private func glance(_ fakes: Fakes, interval: Duration = .seconds(3600)) -> TVGlance {
        TVGlance(makeAPI: { fakes.make($0) }, interval: interval)
    }

    func testReadsEachTVState() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1"), b = tv("B", "192.0.2.2")
        await fakes.api(b.host).serve("/api/stats", Fixture.data("stats-standby"))
        let g = glance(fakes)
        g.update(tvs: [a, b])
        await g.refreshNow()
        XCTAssertEqual(g.states[a.id]?.reach, .reached)
        XCTAssertEqual(g.states[a.id]?.state, .on)
        XCTAssertNotNil(g.states[a.id]?.nowShowing)
        XCTAssertEqual(g.states[b.id]?.reach, .reached)
        XCTAssertEqual(g.states[b.id]?.state, .standby)
    }

    func testUnreachableIsNotOff() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1")
        await fakes.api(a.host).fail("/api/stats", .unreachable)
        let g = glance(fakes)
        g.update(tvs: [a])
        await g.refreshNow()
        XCTAssertEqual(g.states[a.id], TVGlanceState(reach: .unreachable, state: nil, nowShowing: nil))
    }

    func testOtherErrorsMapToUnreachableOrTheirOwnReach() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1"), b = tv("B", "192.0.2.2"), c = tv("C", "192.0.2.3")
        await fakes.api(a.host).fail("/api/stats", .http(500))
        await fakes.api(b.host).fail("/api/stats", .badToken)
        await fakes.api(c.host).fail("/api/stats", .decoding("x"))
        let g = glance(fakes)
        g.update(tvs: [a, b, c])
        await g.refreshNow()
        XCTAssertEqual(g.states[a.id]?.reach, .unreachable)
        XCTAssertEqual(g.states[b.id]?.reach, .badToken)
        XCTAssertEqual(g.states[c.id]?.reach, .unreachable)
        XCTAssertNil(g.states[b.id]?.state)
    }

    func testLocalNetworkDeniedIsItsOwnReach() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1")
        await fakes.api(a.host).fail("/api/stats", .localNetworkDenied)
        let g = glance(fakes)
        g.update(tvs: [a])
        await g.refreshNow()
        XCTAssertEqual(g.states[a.id]?.reach, .localNetworkDenied)
        XCTAssertNil(g.states[a.id]?.state)
    }

    func testUpdateDropsRemovedTVs() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1"), b = tv("B", "192.0.2.2")
        let g = glance(fakes)
        g.update(tvs: [a, b])
        await g.refreshNow()
        XCTAssertNotNil(g.states[b.id])
        let before = await fakes.api(b.host).paths.count
        g.update(tvs: [a])
        XCTAssertNil(g.states[b.id])
        await g.refreshNow()
        let after = await fakes.api(b.host).paths.count
        XCTAssertEqual(before, after)
    }

    func testUpdateWithNewAddressUsesTheNewClient() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1")
        let g = glance(fakes)
        g.update(tvs: [a])
        await g.refreshNow()
        var moved = a; moved.host = "192.0.2.9"
        g.update(tvs: [moved])
        XCTAssertNil(g.states[a.id])
        await g.refreshNow()
        XCTAssertEqual(fakes.built.last?.host, "192.0.2.9")
        let old = await fakes.api("192.0.2.1").paths.count
        XCTAssertEqual(old, 1)
        let new = await fakes.api("192.0.2.9").paths.count
        XCTAssertEqual(new, 1)
    }

    func testChangedTokenIsPickedUpWithTheSameAddress() async {
        let tokens = TokenBox()
        let seen = TokenLog()
        let g = TVGlance(makeAPI: { _ in
            let t = tokens.value
            seen.add(t)
            return TokenAPI(token: t)
        }, interval: .seconds(3600))
        let a = tv("A", "192.0.2.1")
        g.update(tvs: [a])
        await g.refreshNow()
        XCTAssertEqual(g.states[a.id]?.reach, .badToken)
        tokens.value = "new"
        await g.refreshNow()
        XCTAssertEqual(g.states[a.id]?.reach, .reached)
        XCTAssertEqual(seen.all, ["old", "new"])
    }

    func testResultApplyAsItArrives() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1"), b = tv("B", "192.0.2.2")
        let slow = fakes.api(a.host)
        await slow.hold("/api/stats")
        let g = glance(fakes)
        g.update(tvs: [a, b])
        let read = Task { await g.refreshNow() }
        while g.states[b.id] == nil { await Task.yield() }
        XCTAssertNil(g.states[a.id])
        await slow.release("/api/stats")
        await read.value
        XCTAssertNotNil(g.states[a.id])
    }

    func testOlderRoundFinishingLastAppliesNothing() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1")
        let api = fakes.api(a.host)
        await api.hold("/api/stats")           // the first round reads "on" but stays held
        let g = glance(fakes)
        g.update(tvs: [a])
        let first = Task { await g.refreshNow() }
        while await api.heldCount("/api/stats") == 0 { await Task.yield() }
        await api.serve("/api/stats", Fixture.data("stats-standby"))
        await g.refreshNow()
        XCTAssertEqual(g.states[a.id]?.state, .standby)
        await api.release("/api/stats")
        await first.value
        XCTAssertEqual(g.states[a.id]?.state, .standby, "the older round must not overwrite")
    }

    func testCancelledRoundAppliesNothing() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1")
        let api = fakes.api(a.host)
        await api.hold("/api/stats")
        let g = glance(fakes)
        g.update(tvs: [a])
        let read = Task { await g.refreshNow() }
        while await api.heldCount("/api/stats") == 0 { await Task.yield() }
        read.cancel()
        await api.release("/api/stats")
        await read.value
        XCTAssertNil(g.states[a.id])
    }

    func testRenamingStillReads() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1")
        let g = glance(fakes)
        g.update(tvs: [a])
        await g.refreshNow()
        var renamed = a; renamed.name = "Bedroom"
        g.update(tvs: [renamed])
        XCTAssertNotNil(g.states[a.id], "a rename keeps the state")
        await g.refreshNow()
        XCTAssertEqual(g.states[a.id]?.reach, .reached)
    }

    func testReadFinishingAfterRemovalLeavesNoGhost() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1")
        let held = fakes.api(a.host)
        await held.hold("/api/stats")
        let g = glance(fakes)
        g.update(tvs: [a])
        let read = Task { await g.refreshNow() }
        while await held.heldCount("/api/stats") == 0 { await Task.yield() }
        g.update(tvs: [])
        await held.release("/api/stats")
        await read.value
        XCTAssertNil(g.states[a.id])
    }

    func testOldAddressResultNeverAppliesToNewAddress() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1")
        let old = fakes.api(a.host)
        await old.hold("/api/stats")
        let g = glance(fakes)
        g.update(tvs: [a])
        let read = Task { await g.refreshNow() }
        while await old.heldCount("/api/stats") == 0 { await Task.yield() }
        var moved = a; moved.host = "192.0.2.9"
        await fakes.api(moved.host).fail("/api/stats", .unreachable)
        g.update(tvs: [moved])
        XCTAssertNil(g.states[a.id])
        await old.release("/api/stats")
        await read.value
        XCTAssertNil(g.states[a.id], "the old address's answer must be dropped")
        await g.refreshNow()
        XCTAssertEqual(g.states[a.id]?.reach, .unreachable)
    }

    func testMarkStaleForgetsWhatEachTVShowed() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1"), b = tv("B", "192.0.2.2")
        await fakes.api(b.host).fail("/api/stats", .localNetworkDenied)
        let g = glance(fakes)
        g.update(tvs: [a, b])
        await g.refreshNow()
        XCTAssertEqual(g.states[a.id]?.state, .on)
        g.markStale()
        let unknown = TVGlanceState(reach: .unknown, state: nil, nowShowing: nil)
        XCTAssertEqual(g.states[a.id], unknown)
        XCTAssertEqual(g.states[b.id], unknown)
        await g.refreshNow()
        XCTAssertEqual(g.states[a.id]?.state, .on, "the next read shows the TV again")
    }

    func testMarkStaleDropsAReadInFlight() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1")
        let api = fakes.api(a.host)
        let g = glance(fakes)
        g.update(tvs: [a])
        await g.refreshNow()
        await api.hold("/api/stats")
        let read = Task { await g.refreshNow() }
        while await api.heldCount("/api/stats") == 0 { await Task.yield() }
        g.markStale()
        await api.release("/api/stats")
        await read.value
        XCTAssertEqual(g.states[a.id]?.reach, .unknown, "an answer asked before the app left is not news")
    }

    func testUpdateReturnsTheTVsToReadAtOnce() {
        let g = glance(Fakes())
        let a = tv("A", "192.0.2.1"), b = tv("B", "192.0.2.2")
        XCTAssertEqual(g.update(tvs: [a]), [a.id])
        XCTAssertEqual(g.update(tvs: [a, b]), [b.id], "a TV that joins")
        var renamed = a; renamed.name = "Bedroom"
        XCTAssertEqual(g.update(tvs: [renamed, b]), [], "a rename keeps the state")
        var moved = renamed; moved.host = "192.0.2.9"
        XCTAssertEqual(g.update(tvs: [moved, b]), [a.id], "a moved TV starts again as unknown")
        XCTAssertEqual(g.update(tvs: [b]), [])
    }

    func testRefreshNowOnlyReadsTheTVsGiven() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1"), b = tv("B", "192.0.2.2")
        await fakes.api(b.host).serve("/api/stats", Fixture.data("stats-standby"))
        let g = glance(fakes)
        g.update(tvs: [a])
        await g.refreshNow()
        let joined = g.update(tvs: [a, b])
        await g.refreshNow(only: joined)
        XCTAssertEqual(g.states[b.id]?.state, .standby, "the TV that joined is read at once")
        let readsOfA = await fakes.api(a.host).paths.count
        XCTAssertEqual(readsOfA, 1, "the others wait for their round")
    }

    func testRefreshNowReadsAtOnce() async {
        let fakes = Fakes()
        let a = tv("A", "192.0.2.1"), b = tv("B", "192.0.2.2")
        let g = glance(fakes, interval: .seconds(3600))
        g.update(tvs: [a, b])
        await g.refreshNow()
        let loop = Task { await g.run() }
        await fakes.api(a.host).serve("/api/stats", Fixture.data("stats-standby"))
        await g.refreshNow()
        XCTAssertEqual(g.states[a.id]?.state, .standby)
        let n = await fakes.api(b.host).paths.count
        XCTAssertEqual(n, 2)
        loop.cancel()
        await loop.value
    }
}

private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock(); private var t = "old"
    var value: String { get { lock.withLock { t } } set { lock.withLock { t = newValue } } }
}
private final class TokenLog: @unchecked Sendable {
    private let lock = NSLock(); private var a: [String] = []
    func add(_ s: String) { lock.withLock { a.append(s) } }
    var all: [String] { lock.withLock { a } }
}
/// Answers like a TV that only accepts the token "new".
private struct TokenAPI: GlasshouseAPI {
    let token: String
    func get<T: Decodable & Sendable>(_ path: String, as: T.Type) async throws(APIError) -> T {
        guard token == "new" else { throw .badToken }
        do { return try JSONDecoder().decode(T.self, from: Fixture.data("stats")) } catch { throw .decoding("\(error)") }
    }
    func getText(_ path: String) async throws(APIError) -> String { throw .http(404) }
    func getData(_ path: String) async throws(APIError) -> Data { throw .http(404) }
    func send(_ command: Command) async throws(APIError) {}
}
