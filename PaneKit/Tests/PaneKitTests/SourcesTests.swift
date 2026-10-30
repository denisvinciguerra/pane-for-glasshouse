import XCTest
@testable import PaneKit

final class SourcesTests: XCTestCase {
    func testOrderAndActive() throws {
        let stats = try JSONDecoder().decode(Stats.self, from: Fixture.data("stats"))
        let list = sources(from: stats)
        XCTAssertEqual(list.map(\.id), ["livetv", "hdmi1", "hdmi2", "hdmi3", "hdmi4"])
        XCTAssertEqual(list.first?.label, "TV")
        XCTAssertEqual(list.last?.label, "PS5 Console de jeu")
        XCTAssertEqual(list.filter(\.isActive).map(\.id), ["hdmi4"])
    }

    func testNumericOrderBeyondNine() throws {
        let stats = try JSONDecoder().decode(Stats.self, from: Data(#"{"inputs":{"hdmi10":"A","hdmi2":"B"}}"#.utf8))
        XCTAssertEqual(sources(from: stats).map(\.id), ["livetv", "hdmi2", "hdmi10"])
    }

    func testDefaultHDMINameShortens() throws {
        let stats = try JSONDecoder().decode(Stats.self, from: Fixture.data("stats"))
        XCTAssertEqual(sources(from: stats).first { $0.id == "hdmi1" }?.label, "HDMI 1")
    }
}
