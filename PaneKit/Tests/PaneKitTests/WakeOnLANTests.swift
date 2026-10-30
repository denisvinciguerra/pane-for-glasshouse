import XCTest
@testable import PaneKit

final class WakeOnLANTests: XCTestCase {
    func testPacket() throws {
        let p = try XCTUnwrap(WakeOnLAN.packet(mac: "00:11:22:33:44:55"))
        XCTAssertEqual(p.count, 102)
        XCTAssertEqual(Array(p.prefix(6)), [UInt8](repeating: 0xFF, count: 6))
        XCTAssertEqual(Array(p[6..<12]), [0x00, 0x11, 0x22, 0x33, 0x44, 0x55])
        XCTAssertEqual(Array(p[96..<102]), [0x00, 0x11, 0x22, 0x33, 0x44, 0x55])
    }

    func testSeparatorsAndCase() throws {
        XCTAssertEqual(WakeOnLAN.packet(mac: "AA-bb-CC-dd-EE-ff"), WakeOnLAN.packet(mac: "aa:bb:cc:dd:ee:ff"))
        XCTAssertNotNil(WakeOnLAN.packet(mac: "aa:bb:cc:dd:ee:ff"))
    }

    func testNormalizedMAC() {
        XCTAssertEqual(WakeOnLAN.normalized(mac: "00-11-22-AA-bb-CC"), "00:11:22:aa:bb:cc")
        XCTAssertNil(WakeOnLAN.normalized(mac: "00:11:22"))
    }

    func testNormalizedAcceptsSingleDigitGroups() {
        XCTAssertEqual(WakeOnLAN.normalized(mac: "0:11:2:33:44:5"), "00:11:02:33:44:05")
    }

    func testMixedSeparatorsAreRejected() {
        XCTAssertNil(WakeOnLAN.normalized(mac: "00:11-22:33:44:55"))
    }

    func testSignedGroupIsRejected() {
        XCTAssertNil(WakeOnLAN.normalized(mac: "+1:11:22:33:44:55"))
    }

    func testThreeDigitGroupIsRejected() {
        XCTAssertNil(WakeOnLAN.normalized(mac: "000:11:22:33:44:55"))
    }

    func testInvalidMac() async {
        for bad in ["nope", "", "00:11:22:33:44", "00:11:22:33:44:55:66", "00:11:22:33:44:zz"] {
            XCTAssertNil(WakeOnLAN.packet(mac: bad), bad)
        }
        do { try await WakeOnLAN.send(mac: "nope"); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? WakeOnLANError, .invalidMAC) }
    }

    func testDirectedBroadcast() {
        func addr(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> in_addr_t {
            in_addr_t(UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d)).bigEndian
        }
        XCTAssertEqual(WakeOnLAN.directedBroadcast(address: addr(192, 168, 12, 68), netmask: addr(255, 255, 255, 0)),
                       addr(192, 168, 12, 255))
        XCTAssertEqual(WakeOnLAN.directedBroadcast(address: addr(10, 1, 2, 3), netmask: addr(255, 255, 0, 0)),
                       addr(10, 1, 255, 255))
    }
}
