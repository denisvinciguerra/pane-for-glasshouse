import XCTest
@testable import PaneKit

final class TVProbeTests: XCTestCase {
    /// One FakeAPI per candidate token (`""` for none). The server accepts `accepted` only; any other
    /// token gets `.badToken` on caps.
    private struct Rig {
        let probe: TVProbe
        let apis: [String: FakeAPI]
    }

    private func rig(accepted: String?, tokens: [String] = [], configure: (FakeAPI) async -> Void = { _ in }) async -> Rig {
        var apis: [String: FakeAPI] = [:]
        for t in [""] + tokens + (accepted.map { [$0] } ?? []) where apis[t] == nil {
            let api = FakeAPI()
            if t != (accepted ?? "") { await api.fail("/api/caps", .badToken) } else { await configure(api) }
            apis[t] = api
        }
        let frozen = apis
        let refusing = FakeAPI()
        await refusing.fail("/api/caps", .badToken)
        let probe = TVProbe(makeAPI: { frozen[$0.token ?? ""] ?? refusing })
        return Rig(probe: probe, apis: apis)
    }

    func testOpenServerIsFoundWithMACModelAndVersion() async {
        let r = await rig(accepted: nil)
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: [])
        XCTAssertEqual(out, .found(FoundTV(host: "192.0.2.10", port: 8080, token: nil, mac: "00:11:22:33:44:55",
                                           model: "OLED65G45LW.DEUQLJP", version: "0.132.0")))
        XCTAssertEqual(FoundTV(host: "h", port: 1, token: nil, mac: nil, model: "OLED65G45LW.DEUQLJP", version: "").shortModel, "OLED65G45LW")
        XCTAssertNil(FoundTV(host: "h", port: 1, token: nil, mac: nil, model: "", version: "").shortModel)
    }

    func testKnownTokenIsTriedAfterNone() async {
        let r = await rig(accepted: "secret", tokens: ["x"])
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: ["", "x", "x", "secret"])
        guard case .found(let tv) = out else { return XCTFail("\(out)") }
        XCTAssertEqual(tv.token, "secret")
    }

    func testNoKnownTokenWorksNeedsToken() async {
        let r = await rig(accepted: "secret")
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: ["x"])
        XCTAssertEqual(out, .needsToken)
    }

    func testGivenWrongTokenIsBadTokenWithoutTryingOthers() async {
        let r = await rig(accepted: "secret", tokens: ["x"])
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: "x", knownTokens: ["secret"])
        XCTAssertEqual(out, .badToken)
        let paths = await r.apis["secret"]!.paths
        XCTAssertTrue(paths.isEmpty)
    }

    func testCapsMissingFallsBackToStats() async {
        let r = await rig(accepted: nil) { await $0.fail("/api/caps", .http(404)) }
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: [])
        guard case .found(let tv) = out else { return XCTFail("\(out)") }
        XCTAssertEqual(tv.version, "")
        XCTAssertEqual(tv.mac, "00:11:22:33:44:55")
    }

    func testOldServerWithEmptyStatsIsNotGlasshouse() async {
        let r = await rig(accepted: nil) {
            await $0.fail("/api/caps", .http(404))
            await $0.serve("/api/stats", Data("{}".utf8))
        }
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: [])
        XCTAssertEqual(out, .notGlasshouse)
    }

    func testOldServerWithMACIsFound() async {
        let r = await rig(accepted: nil) {
            await $0.fail("/api/caps", .http(404))
            await $0.serve("/api/stats", Data(#"{"mac":"00:11:22:33:44:55"}"#.utf8))
        }
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: [])
        guard case .found(let tv) = out else { return XCTFail("\(out)") }
        XCTAssertEqual(tv.mac, "00:11:22:33:44:55")
    }

    func testHTMLPageIsNotGlasshouse() async {
        let r = await rig(accepted: nil) { await $0.fail("/api/caps", .decoding("html")) }
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: [])
        XCTAssertEqual(out, .notGlasshouse)
    }

    func testJSONWithoutOKIsNotGlasshouse() async {
        let r = await rig(accepted: nil) { await $0.serve("/api/caps", Data(#"{"allowControl":true}"#.utf8)) }
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: [])
        XCTAssertEqual(out, .notGlasshouse)
    }

    func testPlain401IsNotGlasshouse() async {
        let r = await rig(accepted: nil) { await $0.fail("/api/caps", .http(401)) }
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: [])
        XCTAssertEqual(out, .notGlasshouse)
    }

    func testUnreachableStopsAtOnce() async {
        let r = await rig(accepted: nil, tokens: ["x"]) { await $0.fail("/api/caps", .unreachable) }
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: ["x"])
        XCTAssertEqual(out, .unreachable)
        let paths = await r.apis[""]!.paths
        XCTAssertEqual(paths, ["/api/caps"])
        let other = await r.apis["x"]!.paths
        XCTAssertTrue(other.isEmpty)
    }

    func testDeniedIsReported() async {
        let r = await rig(accepted: nil) { await $0.fail("/api/caps", .localNetworkDenied) }
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: [])
        XCTAssertEqual(out, .localNetworkDenied)
    }

    func testStatsFailureStillFinds() async {
        let r = await rig(accepted: nil) { await $0.fail("/api/stats", .http(500)) }
        let out = await r.probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: [])
        XCTAssertEqual(out, .found(FoundTV(host: "192.0.2.10", port: 8080, token: nil, mac: nil, model: nil, version: "0.132.0")))
    }

    func testStatsGoThroughDetailClientWhenGiven() async {
        let caps = FakeAPI()
        await caps.fail("/api/stats", .unreachable)
        let detail = FakeAPI()
        let probe = TVProbe(makeAPI: { _ in caps }, makeDetailAPI: { _ in detail })
        let out = await probe.probe(host: "192.0.2.10", port: 8080, token: nil, knownTokens: [])
        guard case .found(let found) = out else { return XCTFail("\(out)") }
        XCTAssertEqual(found.mac, "00:11:22:33:44:55")
        XCTAssertEqual(found.model, "OLED65G45LW.DEUQLJP")
    }
}
