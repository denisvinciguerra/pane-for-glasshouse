import XCTest
import os
@testable import PaneKit

/// URLProtocol double. State lives behind a lock so Swift 6 strict concurrency is satisfied.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable { case response(status: Int, body: Data), failure(URLError.Code) }

    struct Recorded: Sendable { let request: URLRequest; let body: Data }

    private struct State { var reply: Reply = .response(status: 200, body: Data()); var recorded: Recorded? }
    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func program(_ r: Reply) { state.withLock { $0 = State(reply: r, recorded: nil) } }
    static var lastRequest: Recorded? { state.withLock { $0.recorded } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                body.append(buf, count: n)
            }
            stream.close()
        }
        let req = request
        let captured = body
        let reply = Self.state.withLock { st -> Reply in
            st.recorded = Recorded(request: req, body: captured)
            return st.reply
        }
        switch reply {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .response(let status, let data):
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

final class GlasshouseClientTests: XCTestCase {
    private func makeClient(host: String = "192.0.2.10", token: String? = "t0k", language: String = "fr", timeout: TimeInterval = 4,
                            denied: @escaping @Sendable (String, Int) async -> Bool = { _, _ in false }) -> GlasshouseClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return GlasshouseClient(
            endpoint: Endpoint(host: host, port: 8080, token: token),
            session: URLSession(configuration: cfg),
            language: language, timeout: timeout, localNetworkDenied: denied)
    }

    private func ok() { StubURLProtocol.program(.response(status: 200, body: Data(#"{"ok":true}"#.utf8))) }

    func testSendsBearerAndLanguageAndNoOrigin() async throws {
        ok()
        try await makeClient().send(.rcu(.ok))
        let req = try XCTUnwrap(StubURLProtocol.lastRequest).request
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer t0k")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Glasshouse-Lang"), "fr")
        XCTAssertNil(req.value(forHTTPHeaderField: "Origin"))
        XCTAssertEqual(req.timeoutInterval, 4)
    }

    func testControlPostsJSON() async throws {
        ok()
        try await makeClient().send(.rcu(.ok))
        let rec = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(rec.request.httpMethod, "POST")
        XCTAssertEqual(rec.request.url?.path, "/api/control")
        XCTAssertEqual(rec.request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: rec.body), Command.rcu(.ok).body)
    }

    func testUnauthorizedMapsToBadToken() async {
        StubURLProtocol.program(.response(status: 401, body: Data()))
        do { try await makeClient().send(.rcu(.ok)); XCTFail("expected error") }
        catch { XCTAssertEqual(error, .badToken) }
    }

    func testTimeoutIsApplied() async throws {
        ok()
        try await makeClient(timeout: 1.2).send(.rcu(.ok))
        XCTAssertEqual(try XCTUnwrap(StubURLProtocol.lastRequest).request.timeoutInterval, 1.2)
    }

    func testUnauthorizedWithTokenWordingIsBadToken() async {
        StubURLProtocol.program(.response(status: 401, body: Data(#"{"ok":false,"error":"bad or missing token"}"#.utf8)))
        do { try await makeClient().send(.rcu(.ok)); XCTFail("expected error") }
        catch { XCTAssertEqual(error, .badToken) }
    }

    func testUnauthorizedWithoutTokenWordingIsHTTP() async {
        StubURLProtocol.program(.response(status: 401, body: Data("<html>Login</html>".utf8)))
        do { try await makeClient().send(.rcu(.ok)); XCTFail("expected error") }
        catch { XCTAssertEqual(error, .http(401)) }
    }

    func testLocalNetworkDenialMapsToDenied() async {
        let asked = OSAllocatedUnfairLock(initialState: [String]())
        StubURLProtocol.program(.failure(.notConnectedToInternet))
        let denying = makeClient(denied: { host, port in asked.withLock { $0.append("\(host):\(port)") }; return true })
        do { try await denying.send(.rcu(.ok)); XCTFail("expected error") }
        catch { XCTAssertEqual(error, .localNetworkDenied) }
        XCTAssertEqual(asked.withLock { $0 }, ["192.0.2.10:8080"])

        do { try await makeClient(denied: { _, _ in false }).send(.rcu(.ok)); XCTFail("expected error") }
        catch { XCTAssertEqual(error, .unreachable) }
    }

    func testCancelledRequestNeverChecksTheLocalNetwork() async {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        StubURLProtocol.program(.failure(.cancelled))
        let client = makeClient(denied: { _, _ in calls.withLock { $0 += 1 }; return true })
        do { try await client.send(.rcu(.ok)); XCTFail("expected error") }
        catch { XCTAssertEqual(error, .unreachable) }
        XCTAssertEqual(calls.withLock { $0 }, 0)
    }

    func testOtherStatusMapsToHttp() async {
        StubURLProtocol.program(.response(status: 500, body: Data()))
        do { try await makeClient().send(.rcu(.ok)); XCTFail("expected error") }
        catch { XCTAssertEqual(error, .http(500)) }
    }

    func testRejectedCommand() async {
        StubURLProtocol.program(.response(status: 200, body: Data(#"{"ok":false,"error":"controls disabled in config"}"#.utf8)))
        do { try await makeClient().send(.rcu(.ok)); XCTFail("expected error") }
        catch { XCTAssertEqual(error, .rejected("controls disabled in config")) }
    }

    func testTimeoutMapsToUnreachable() async {
        StubURLProtocol.program(.failure(.timedOut))
        do { try await makeClient().send(.rcu(.ok)); XCTFail("expected error") }
        catch { XCTAssertEqual(error, .unreachable) }
    }

    func testDecodesCaps() async throws {
        StubURLProtocol.program(.response(status: 200, body: Fixture.data("caps")))
        let caps = try await makeClient().get("/api/caps", as: Caps.self)
        XCTAssertTrue(caps.allowControl)
        XCTAssertEqual(caps.version, "0.132.0")
    }

    func testBadJSONMapsToDecoding() async {
        StubURLProtocol.program(.response(status: 200, body: Data("nope".utf8)))
        do { _ = try await makeClient().get("/api/caps", as: Caps.self); XCTFail("expected error") }
        catch { if case .decoding = error {} else { XCTFail("got \(error)") } }
    }

    func testGetText() async throws {
        StubURLProtocol.program(.response(status: 200, body: Data("<html>".utf8)))
        let text = try await makeClient().getText("/")
        XCTAssertEqual(text, "<html>")
    }

    func testGetDataSendsTheTokenAndKeepsTheQuery() async throws {
        StubURLProtocol.program(.response(status: 200, body: Fixture.data("app-icon.png")))
        let data = try await makeClient().getData("/api/apps/icon?id=com.example.app")
        XCTAssertEqual(data, Fixture.data("app-icon.png"))
        let req = try XCTUnwrap(StubURLProtocol.lastRequest).request
        XCTAssertEqual(req.url?.absoluteString, "http://192.0.2.10:8080/api/apps/icon?id=com.example.app")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer t0k")
    }

    func testDashboardURL() {
        XCTAssertEqual(makeClient(token: "t").dashboardURL(tab: "picture")?.absoluteString,
                       "http://192.0.2.10:8080/?tab=picture&k=t")
        XCTAssertEqual(makeClient(token: nil).dashboardURL(tab: nil)?.absoluteString, "http://192.0.2.10:8080/")
    }

    func testInvalidHostIsUnreachableWithoutRequest() async {
        StubURLProtocol.program(.response(status: 200, body: Data(#"{"ok":true}"#.utf8)))
        let client = makeClient(host: "bad host")
        do { try await client.send(.rcu(.ok)); XCTFail("expected error") }
        catch { XCTAssertEqual(error, .unreachable) }
        do { _ = try await client.getText("/"); XCTFail("expected error") }
        catch { XCTAssertEqual(error, .unreachable) }
        XCTAssertNil(StubURLProtocol.lastRequest)
        XCTAssertNil(client.dashboardURL(tab: nil))
        XCTAssertNil(makeClient(host: "").dashboardURL(tab: nil))
    }

    func testHostWithTrailingNewlineStillWorks() async throws {
        ok()
        let client = makeClient(host: "192.0.2.10\n")
        try await client.send(.rcu(.ok))
        XCTAssertEqual(StubURLProtocol.lastRequest?.request.url?.absoluteString, "http://192.0.2.10:8080/api/control")
        XCTAssertEqual(client.dashboardURL(tab: nil)?.absoluteString, "http://192.0.2.10:8080/?k=t0k")
    }
}

final class LocalNetworkCheckTests: XCTestCase {
    /// An invalid port returns before any connection is made.
    func testInvalidPortsAreNotDenied() async {
        for port in [0, -1, 70000] {
            let denied = await LocalNetworkCheck.isDenied(host: "192.0.2.10", port: port)
            XCTAssertFalse(denied, "port \(port)")
        }
    }
}
