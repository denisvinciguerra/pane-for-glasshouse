import XCTest
@testable import PaneKit

final class ARPTableTests: XCTestCase {
    func testEntryGivesNormalizedMAC() {
        let out = "? (192.0.2.10) at 0:11:22:3:44:55 on en0 ifscope [ethernet]"
        XCTAssertEqual(ARPTable.parse(out, host: "192.0.2.10"), "00:11:22:03:44:55")
    }

    func testNoEntryIsNil() {
        XCTAssertNil(ARPTable.parse("192.0.2.10 (192.0.2.10) -- no entry", host: "192.0.2.10"))
    }

    func testIncompleteIsNil() {
        let out = "? (192.0.2.10) at (incomplete) on en0 ifscope [ethernet]"
        XCTAssertNil(ARPTable.parse(out, host: "192.0.2.10"))
    }

    func testPermanentEntryReadsMAC() {
        let out = "? (192.0.2.10) at 0:11:22:33:44:55 on en0 permanent [ethernet]"
        XCTAssertEqual(ARPTable.parse(out, host: "192.0.2.10"), "00:11:22:33:44:55")
    }

    func testOtherHostWithSamePrefixIsIgnored() {
        let short = "? (192.0.2.1) at 0:11:22:33:44:55 on en0 ifscope [ethernet]"
        let long = "? (192.0.2.10) at 0:11:22:33:44:55 on en0 ifscope [ethernet]"
        XCTAssertNil(ARPTable.parse(short, host: "192.0.2.10"))
        XCTAssertNil(ARPTable.parse(long, host: "192.0.2.1"))
    }
}
