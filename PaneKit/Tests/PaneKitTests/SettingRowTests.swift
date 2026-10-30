import XCTest
@testable import PaneKit

final class SettingRowTests: XCTestCase {
    private func row(_ rows: [SettingRow], _ id: String) -> SettingRow? { rows.first { $0.id == id } }

    func testDecodesPictureFixture() throws {
        let p = try JSONDecoder().decode(PicturePayload.self, from: Fixture.data("picture"))
        XCTAssertEqual(p.rows.count, 54)
        XCTAssertEqual(row(p.rows, "backlight")?.kind, .number(value: 100, min: 0, max: 100))
        XCTAssertEqual(row(p.rows, "contrast")?.active, false)
        XCTAssertEqual(p.rows.filter { $0.cms != nil }.count, 18)
        XCTAssertNil(row(p.rows, "dynamicColor")?.cms)
        XCTAssertEqual(row(p.rows, "dynamicColor")?.group, "cms")
    }

    func testSwitchAndChoice() throws {
        let p = try JSONDecoder().decode(PicturePayload.self, from: Fixture.data("picture"))
        XCTAssertEqual(row(p.rows, "filmMakerMode")?.kind, .toggle(on: true))
        guard case .choice(_, let choices)? = row(p.rows, "pictureMode")?.kind else { return XCTFail("not a choice") }
        XCTAssertEqual(choices.count, 8)
        XCTAssertTrue(choices.contains { $0.label == "HDR Filmmaker" })
    }

    func testUnknownTypeIsKeptAsUnsupported() throws {
        let json = #"{"ok":true,"rows":[{"id":"a","section":"picture","type":"switch","title":"A","on":true},{"id":"x","section":"picture","type":"rgbGrid","title":"X"},{"id":"b","section":"picture","type":"number","title":"B","value":1,"min":0,"max":2}]}"#
        let p = try JSONDecoder().decode(LGSettingsPayload.self, from: Data(json.utf8))
        XCTAssertEqual(p.rows.count, 3)
        XCTAssertEqual(p.rows[1].kind, .unsupported("rgbGrid"))
    }

    func testChoiceWithoutChoicesIsUnsupported() throws {
        let json = #"{"id":"x","section":"sound","type":"choice","title":"X","value":"a"}"#
        let r = try JSONDecoder().decode(SettingRow.self, from: Data(json.utf8))
        XCTAssertEqual(r.kind, .unsupported("choice"))
    }

    func testIncompleteNumberAndSwitchAreUnsupported() throws {
        let n = try JSONDecoder().decode(SettingRow.self, from: Data(#"{"id":"n","section":"s","type":"number","title":"N","value":1}"#.utf8))
        XCTAssertEqual(n.kind, .unsupported("number"))
        let s = try JSONDecoder().decode(SettingRow.self, from: Data(#"{"id":"s","section":"s","type":"switch","title":"S"}"#.utf8))
        XCTAssertEqual(s.kind, .unsupported("switch"))
    }

    func testRowsMissingIdentityAreSkippedNotFatal() throws {
        let json = #"{"rows":[{"id":"a","section":"s","title":"A","on":false},{"section":"s","title":"no id"},42,{"id":"b","section":"s","title":"B","on":true}]}"#
        let p = try JSONDecoder().decode(LGSettingsPayload.self, from: Data(json.utf8))
        XCTAssertEqual(p.rows.map(\.id), ["a", "b"])
    }

    func testNumbersMayBeIntsOrDoubles() throws {
        let json = #"{"id":"n","section":"s","type":"number","title":"N","value":1.5,"min":-2,"max":3}"#
        let r = try JSONDecoder().decode(SettingRow.self, from: Data(json.utf8))
        XCTAssertEqual(r.kind, .number(value: 1.5, min: -2, max: 3))
    }

    func testNumberOutOfShapeIsUnsupported() throws {
        func kind(_ value: String, _ min: String, _ max: String) throws -> SettingRow.Kind {
            let json = #"{"id":"n","section":"s","type":"number","title":"N","value":"# + value + #","min":"# + min + #","max":"# + max + #"}"#
            return try JSONDecoder().decode(SettingRow.self, from: Data(json.utf8)).kind
        }
        XCTAssertEqual(try kind("5", "10", "0"), .unsupported("number"), "min above max")
        XCTAssertEqual(try kind("2e9", "0", "100"), .unsupported("number"))
        XCTAssertEqual(try kind("5", "-2e9", "100"), .unsupported("number"))
        XCTAssertEqual(try kind("5", "0", "1e300"), .unsupported("number"))
        XCTAssertEqual(try kind("5", "5", "5"), .number(value: 5, min: 5, max: 5))
        XCTAssertEqual(try kind("-1e9", "-1e9", "1e9"), .number(value: -1e9, min: -1e9, max: 1e9))
    }

    func testAudioFixture() throws {
        let a = try JSONDecoder().decode(AudioPayload.self, from: Fixture.data("audio"))
        let rows = try XCTUnwrap(a.lgSettings)
        XCTAssertEqual(rows.count, 12)
        guard case .choice(_, let choices)? = row(rows, "soundOutput")?.kind else { return XCTFail("not a choice") }
        XCTAssertEqual(choices.count, 8)
        XCTAssertEqual(row(rows, "audioBalance")?.kind, .number(value: 0, min: -50, max: 50))
    }

    func testGameAndHdmiFixturesDecode() throws {
        let g = try JSONDecoder().decode(GamePayload.self, from: Fixture.data("game"))
        XCTAssertEqual(g.rows?.count, 9)
        let h = try JSONDecoder().decode(LGSettingsPayload.self, from: Fixture.data("lgsettings-hdmi-devices"))
        XCTAssertFalse(h.rows.isEmpty)
    }
}
