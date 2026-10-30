import XCTest
@testable import PaneKit

final class TVAddressTests: XCTestCase {
    func testBareHostTakesDefaultPort()      { XCTAssertEqual(TVAddress.parse("  192.0.2.10 \n"), TVAddress(host: "192.0.2.10", port: 8080, token: nil)) }
    func testHostWithPort()                  { XCTAssertEqual(TVAddress.parse("tv.local:8081")?.port, 8081) }
    func testDashboardLinkKeepsPortAndToken() {
        XCTAssertEqual(TVAddress.parse("http://192.0.2.10:8080/?tab=privacy&k=s%20e"), TVAddress(host: "192.0.2.10", port: 8080, token: "s e"))
    }
    func testLinkWithoutPortUsesHTTPPort()   { XCTAssertEqual(TVAddress.parse("http://tv.example/")?.port, 80) }
    func testUppercaseSchemeAndTrailingSlash() { XCTAssertEqual(TVAddress.parse("HTTP://192.0.2.10:8080/")?.host, "192.0.2.10") }
    func testEmptyTokenIsNone()              { XCTAssertNil(TVAddress.parse("http://192.0.2.10:8080/?k=")?.token) }
    func testHTTPSIsRefused()                { XCTAssertNil(TVAddress.parse("https://192.0.2.10:8443/")) }
    func testBadPortIsRefused()              { XCTAssertNil(TVAddress.parse("192.0.2.10:70000")) }
    func testPortZeroIsRefused()             { XCTAssertNil(TVAddress.parse("192.0.2.10:0")) }
    func testFTPIsRefused()                  { XCTAssertNil(TVAddress.parse("ftp://192.0.2.10/")) }
    func testIPv6IsRefused()                 { XCTAssertNil(TVAddress.parse("[2001:db8::1]:8080")) } // the client composes http://host:port without brackets
    func testBareQueryIsRefused()            { XCTAssertNil(TVAddress.parse("?k=abc")) }
    func testGarbageIsRefused()              { XCTAssertNil(TVAddress.parse("not an address")); XCTAssertNil(TVAddress.parse("")) }
}
