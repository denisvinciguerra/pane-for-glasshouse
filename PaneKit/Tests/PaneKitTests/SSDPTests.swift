import XCTest
@testable import PaneKit

final class SSDPTests: XCTestCase {
    func testSearchMessage() {
        let message = SSDP.searchMessage(target: "urn:lge-com:service:webos-second-screen:1")
        XCTAssertTrue(message.hasPrefix("M-SEARCH * HTTP/1.1\r\n"))
        XCTAssertTrue(message.contains("HOST: 239.255.255.250:1900\r\n"))
        XCTAssertTrue(message.contains("MAN: \"ssdp:discover\"\r\n"))
        XCTAssertTrue(message.contains("MX: 2\r\n"))
        XCTAssertTrue(message.contains("ST: urn:lge-com:service:webos-second-screen:1\r\n"))
        XCTAssertTrue(message.hasSuffix("\r\n\r\n"))
    }

    func testWebOSReply() {
        XCTAssertTrue(SSDP.isWebOSReply("HTTP/1.1 200 OK\r\nSERVER: WebOS/4.1.0 UPnP/1.0\r\n"))
        XCTAssertTrue(SSDP.isWebOSReply("server: LGE WebOS TV/Version 0.9"))
        XCTAssertFalse(SSDP.isWebOSReply("SERVER: Linux UPnP/1.0 Sonos"))
        XCTAssertFalse(SSDP.isWebOSReply("ST: webos-second-screen\r\nSERVER: Linux UPnP/1.0 Sonos"))
    }
}
