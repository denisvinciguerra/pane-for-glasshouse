import XCTest
@testable import PaneKit

final class PowerStateTests: XCTestCase {
    private func stats(_ json: String) throws -> Stats {
        try JSONDecoder().decode(Stats.self, from: Data(json.utf8))
    }

    func testCompStatusRunningIsMaintenance() throws {
        let s = try stats(#"{"oled":{"comp_status":"Running"},"powerState":{"systemOn":true,"screenOn":true,"label":"On"}}"#)
        XCTAssertEqual(PowerState.from(s), .maintenance)
    }
    func testSystemOffIsStandby() throws {
        XCTAssertEqual(PowerState.from(try stats(#"{"powerState":{"systemOn":false}}"#)), .standby)
    }
    func testRawStandbyIsStandby() throws {
        XCTAssertEqual(PowerState.from(try stats(#"{"powerState":{"raw":"Standby"}}"#)), .standby)
    }
    func testRawActiveStandbyIsStandby() throws {
        XCTAssertEqual(PowerState.from(try stats(#"{"powerState":{"raw":"Active Standby","systemOn":true}}"#)), .standby)
    }
    func testScreenOffIsScreenOff() throws {
        XCTAssertEqual(PowerState.from(try stats(#"{"powerState":{"systemOn":true,"screenOn":false}}"#)), .screenOff)
    }
    func testSystemOnIsOn() throws {
        XCTAssertEqual(PowerState.from(try stats(#"{"powerState":{"systemOn":true}}"#)), .on)
    }
    func testLabelOnIsOn() throws {
        XCTAssertEqual(PowerState.from(try stats(#"{"powerState":{"label":"On"}}"#)), .on)
    }
    func testNoPowerInfoIsOn() throws {
        XCTAssertEqual(PowerState.from(try stats(#"{"ok":true}"#)), .on)
    }
    func testNilIsUnreachable() {
        XCTAssertEqual(PowerState.from(nil), .unreachable)
    }
    func testG4FixtureIsOn() throws {
        XCTAssertEqual(PowerState.from(try JSONDecoder().decode(Stats.self, from: Fixture.data("stats"))), .on)
    }
    func testStandbyFixtureIsStandby() throws {
        XCTAssertEqual(PowerState.from(try JSONDecoder().decode(Stats.self, from: Fixture.data("stats-standby"))), .standby)
    }
}
