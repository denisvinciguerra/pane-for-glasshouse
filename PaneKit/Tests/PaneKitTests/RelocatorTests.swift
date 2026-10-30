import XCTest
@testable import PaneKit

final class RelocatorTests: XCTestCase {
    private static let wanted = "00:11:22:33:44:55"

    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var ports: [Int] = []
        private var hosts: [String] = []
        func searched(port: Int) { lock.lock(); ports.append(port); lock.unlock() }
        func asked(_ host: String) { lock.lock(); hosts.append(host); lock.unlock() }
        var searchPorts: [Int] { lock.lock(); defer { lock.unlock() }; return ports }
        var askedHosts: [String] { lock.lock(); defer { lock.unlock() }; return hosts }
    }

    private func found(_ host: String, mac: String?) -> DiscoveredTV {
        DiscoveredTV(host: host, outcome: .found(FoundTV(host: host, port: 8080, token: nil, mac: mac, model: nil, version: "0.130.0")))
    }

    private func locked(_ host: String) -> DiscoveredTV { DiscoveredTV(host: host, outcome: .needsToken) }

    /// `tvs`: what the search reports; `arp`: the MAC the ARP table has for each host.
    private func relocator(tvs: [DiscoveredTV], arp: [String: String] = [:], log: Log) -> Relocator {
        Relocator(search: { port, found in
            log.searched(port: port)
            for tv in tvs { await found(tv) }
            return .finished
        }, macOf: { host in
            log.asked(host)
            return arp[host]
        })
    }

    func testTokenProtectedTVFoundByARP() async {
        let r = relocator(tvs: [locked("192.0.2.20")], arp: ["192.0.2.20": Self.wanted], log: Log())
        let host = await r.locate(mac: Self.wanted, port: 8080, excluding: "192.0.2.10")
        XCTAssertEqual(host, "192.0.2.20")
    }

    func testOpenServerUsesReportedMAC() async {
        let r = relocator(tvs: [found("192.0.2.21", mac: "00-11-22-33-44-55")], log: Log())
        let host = await r.locate(mac: Self.wanted, port: 8080, excluding: "192.0.2.10")
        XCTAssertEqual(host, "192.0.2.21")
    }

    func testOpenServerReportingTheMACButARPDisagreesIsIgnored() async {
        let r = relocator(tvs: [found("192.0.2.21", mac: Self.wanted)], arp: ["192.0.2.21": "AA:BB:CC:DD:EE:FF"], log: Log())
        let host = await r.locate(mac: Self.wanted, port: 8080, excluding: "192.0.2.10")
        XCTAssertNil(host)
    }

    func testARPWinsOverReportedMAC() async {
        let r = relocator(tvs: [found("192.0.2.21", mac: "AA:BB:CC:DD:EE:FF")], arp: ["192.0.2.21": Self.wanted], log: Log())
        let host = await r.locate(mac: Self.wanted, port: 8080, excluding: "192.0.2.10")
        XCTAssertEqual(host, "192.0.2.21")
    }

    func testFoundServerWithoutMACUsesARP() async {
        let r = relocator(tvs: [found("192.0.2.21", mac: nil)], arp: ["192.0.2.21": "0:11:22:33:44:55"], log: Log())
        let host = await r.locate(mac: Self.wanted, port: 8080, excluding: "192.0.2.10")
        XCTAssertEqual(host, "192.0.2.21")
    }

    func testFirstMatchCancelsTheSearch() async {
        let log = Log()
        let cancelled = expectation(description: "the search is cancelled")
        let r = Relocator(search: { _, found in
            await found(DiscoveredTV(host: "192.0.2.20", outcome: .needsToken))
            // Waits for the next server, which never comes: the match must stop the search.
            do { try await Task.sleep(for: .seconds(60)) } catch { cancelled.fulfill() }
            await found(DiscoveredTV(host: "192.0.2.21", outcome: .needsToken))
            return .finished
        }, macOf: { host in
            log.asked(host)
            return host == "192.0.2.20" ? Self.wanted : nil
        })
        let host = await r.locate(mac: Self.wanted, port: 8080, excluding: "192.0.2.10")
        XCTAssertEqual(host, "192.0.2.20")
        await fulfillment(of: [cancelled], timeout: 5)
        XCTAssertEqual(log.askedHosts, ["192.0.2.20"])
    }

    func testOtherMACIsIgnored() async {
        let r = relocator(tvs: [found("192.0.2.21", mac: "AA:BB:CC:DD:EE:FF"), locked("192.0.2.22")],
                          arp: ["192.0.2.22": "AA:BB:CC:DD:EE:FF"], log: Log())
        let host = await r.locate(mac: Self.wanted, port: 8080, excluding: "192.0.2.10")
        XCTAssertNil(host)
    }

    func testCurrentAddressIsSkipped() async {
        let log = Log()
        let r = relocator(tvs: [locked("192.0.2.10")], arp: ["192.0.2.10": Self.wanted], log: log)
        let host = await r.locate(mac: Self.wanted, port: 8080, excluding: "192.0.2.10")
        XCTAssertNil(host)
        XCTAssertTrue(log.askedHosts.isEmpty)
    }

    func testInvalidMACSkipsTheSearch() async {
        let log = Log()
        let r = relocator(tvs: [found("192.0.2.21", mac: Self.wanted)], log: log)
        let host = await r.locate(mac: "bad", port: 8080, excluding: "192.0.2.10")
        XCTAssertNil(host)
        XCTAssertTrue(log.searchPorts.isEmpty)
    }

    func testSearchUsesTheTVsPort() async {
        let log = Log()
        let r = relocator(tvs: [], log: log)
        _ = await r.locate(mac: Self.wanted, port: 8081, excluding: "192.0.2.10")
        XCTAssertEqual(log.searchPorts, [8081])
    }

    func testThrottleBacksOff5Then15Then60Minutes() {
        var t = RelocationThrottle()
        let a = UUID(), b = UUID()
        var now = ContinuousClock.now
        XCTAssertTrue(t.allow(a, at: now))
        XCTAssertTrue(t.allow(b, at: now + .seconds(1)))
        for minutes in [5, 15, 60, 60] {
            XCTAssertFalse(t.allow(a, at: now + .seconds(minutes * 60 - 1)), "\(minutes) min")
            now += .seconds(minutes * 60)
            XCTAssertTrue(t.allow(a, at: now), "\(minutes) min")
        }
    }

    func testThrottleResetStartsOver() {
        var t = RelocationThrottle()
        let a = UUID(), b = UUID()
        let t0 = ContinuousClock.now
        XCTAssertTrue(t.allow(a, at: t0))
        XCTAssertTrue(t.allow(a, at: t0 + .seconds(300)))
        XCTAssertTrue(t.allow(b, at: t0 + .seconds(300)))
        t.reset(a)
        XCTAssertTrue(t.allow(a, at: t0 + .seconds(301)))
        XCTAssertFalse(t.allow(a, at: t0 + .seconds(600)))
        XCTAssertTrue(t.allow(a, at: t0 + .seconds(601)))
        XCTAssertFalse(t.allow(b, at: t0 + .seconds(599)))
    }
}
