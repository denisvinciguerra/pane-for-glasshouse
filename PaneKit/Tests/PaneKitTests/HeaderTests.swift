import XCTest
@testable import PaneKit

final class HeaderTests: XCTestCase {
    func testG4Header() throws {
        let stats = try JSONDecoder().decode(Stats.self, from: Fixture.data("stats"))
        let header = Header(stats: stats)
        XCTAssertEqual(header.model, "OLED65G45LW")
        XCTAssertEqual(header.state, .on)
        XCTAssertEqual(header.nowShowing, "PS5 Console de jeu")
        XCTAssertEqual(header.signal, "3840×2160 @ 60 Hz")   // recorded fixture: 60 Hz
        XCTAssertEqual(header.rangeBadge, "HDR10")
    }

    func testNilStatsHeader() {
        let header = Header(stats: nil)
        XCTAssertEqual(header.model, "")
        XCTAssertEqual(header.state, .unreachable)
        XCTAssertNil(header.nowShowing); XCTAssertNil(header.signal); XCTAssertNil(header.rangeBadge)
    }

    func testNowShowingPrefersAppNameThenDisplayTitle() throws {
        let a = try JSONDecoder().decode(Stats.self, from: Data(#"{"app":"x","app_name":"Netflix","display_title":"Show"}"#.utf8))
        XCTAssertEqual(Header(stats: a).nowShowing, "Netflix")
        let b = try JSONDecoder().decode(Stats.self, from: Data(#"{"app":"x","display_title":"Show"}"#.utf8))
        XCTAssertEqual(Header(stats: b).nowShowing, "Show")
    }

    func testStandbyFixtureHeaderState() throws {
        let stats = try JSONDecoder().decode(Stats.self, from: Fixture.data("stats-standby"))
        XCTAssertEqual(Header(stats: stats).state, .standby)
    }

    func testNowShowingFallsBackToInputName() throws {
        let s = try JSONDecoder().decode(Stats.self, from: Data(#"{"app":"hdmi4","inputs":{"hdmi4":"X"}}"#.utf8))
        XCTAssertEqual(Header(stats: s).nowShowing, "X")
    }
}
