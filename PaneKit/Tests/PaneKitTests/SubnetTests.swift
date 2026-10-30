import XCTest
@testable import PaneKit

final class SubnetTests: XCTestCase {
    private let me: UInt32 = 0xC000020A // 192.0.2.10

    private func expected24() -> [UInt32] {
        (1...254).map { 0xC0000200 + UInt32($0) }.filter { $0 != 0xC000020A }
    }

    func testSlash24ExcludesSelfNetworkAndBroadcast() {
        let hosts = Subnet.hostsAround(me, prefixLength: 24)
        XCTAssertEqual(hosts.count, 253)
        XCTAssertEqual(hosts, expected24())
        XCTAssertEqual(Subnet.dotted(hosts.first!), "192.0.2.1")
        XCTAssertEqual(Subnet.dotted(hosts.last!), "192.0.2.254")
    }

    func testWidePrefixNarrowedTo24() {
        XCTAssertEqual(Subnet.hostsAround(me, prefixLength: 16), expected24())
    }

    func testNarrowPrefixKept() {
        XCTAssertEqual(Subnet.hostsAround(me, prefixLength: 30), [0xC0000209])
    }

    func testLinkLocalIsNotSwept() {
        XCTAssertFalse(Subnet.isSwept(0xA9FE0304)) // 169.254.3.4
        XCTAssertTrue(Subnet.isSwept(0xC0000204)) // 192.0.2.4
    }

    private let wifi = Subnet.Interface(address: 0xC000020A, netmask: 0xFFFFFF00) // 192.0.2.10/24
    private let linkLocal = Subnet.Interface(address: 0xA9FE0304, netmask: 0xFFFF0000) // 169.254.3.4/16

    func testAddressInsideASweptSubnetIsLocal() {
        XCTAssertTrue(Subnet.isLocal("192.0.2.20", interfaces: [linkLocal, wifi]))
    }

    func testAddressOfAnotherSubnetIsNotLocal() {
        XCTAssertFalse(Subnet.isLocal("198.51.100.20", interfaces: [wifi]))
        XCTAssertFalse(Subnet.isLocal("192.0.2.20", interfaces: []))
    }

    func testHostNameIsNotLocal() {
        XCTAssertFalse(Subnet.isLocal("tv.local", interfaces: [wifi]))
        XCTAssertFalse(Subnet.isLocal("192.0.2", interfaces: [wifi]))
    }

    func testLinkLocalInterfaceIsIgnored() {
        XCTAssertFalse(Subnet.isLocal("169.254.3.9", interfaces: [linkLocal]))
    }

    func testDotted() {
        XCTAssertEqual(Subnet.dotted(0xC000020A), "192.0.2.10")
    }
}
