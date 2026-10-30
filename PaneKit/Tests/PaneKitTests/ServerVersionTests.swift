import XCTest
@testable import PaneKit

final class ServerVersionTests: XCTestCase {
    func testOrdersNumerically()  { XCTAssertLessThan(ServerVersion("0.99.0")!, ServerVersion("0.126.0")!) }
    func testShortAndPrefixed()   { XCTAssertEqual(ServerVersion("v0.126"), ServerVersion("0.126.0")) }
    func testPreReleaseSuffixIsIgnored() {
        XCTAssertEqual(ServerVersion("0.133.0-rc1"), ServerVersion("0.133.0"))
        XCTAssertEqual(ServerVersion("0.133.0+abc"), ServerVersion("0.133.0"))
        XCTAssertEqual(ServerVersion("0.133.0-beta.2"), ServerVersion("0.133.0"))
    }
    func testSurroundingSpacesAreTrimmed() { XCTAssertEqual(ServerVersion(" 0.132.0\n"), ServerVersion("0.132.0")) }
    func testSignsAreRejected()   { XCTAssertNil(ServerVersion("+0.1.2")); XCTAssertNil(ServerVersion("0.-1")) }
    func testUnreadable()         { XCTAssertNil(ServerVersion("")); XCTAssertNil(ServerVersion("dev")) }
}
