import XCTest
@testable import PaneKit

final class StatsTests: XCTestCase {
    func testDecodesG4Fixture() throws {
        let stats = try JSONDecoder().decode(Stats.self, from: Fixture.data("stats"))
        XCTAssertEqual(stats.device?.model, "OLED65G45LW.DEUQLJP")
        XCTAssertNotNil(stats.volume)
        XCTAssertEqual(stats.inputs?["hdmi4"], "PS5 Console de jeu")
        XCTAssertNotNil(stats.hdmiDiag?.phyMode)
    }

    func testTypeDriftLosesOnlyTheDriftedField() throws {
        var text = String(decoding: Fixture.data("stats"), as: UTF8.self)
        for (from, to) in [(#""temp": 43,"#, #""temp": 43.5,"#), (#""load": 51,"#, #""load": "x","#),
                           (#""systemOn": true,"#, #""systemOn": "yes","#)] {
            XCTAssertTrue(text.contains(from), from)
            text = text.replacingOccurrences(of: from, with: to)
        }
        let s = try JSONDecoder().decode(Stats.self, from: Data(text.utf8))
        XCTAssertEqual(s.temp, 44, "a Double where an Int was is rounded")
        XCTAssertNil(s.load)
        XCTAssertNil(s.powerState?.systemOn)
        XCTAssertEqual(s.powerState?.screenOn, true, "the rest of the nested struct stays")
        XCTAssertEqual(s.volume, 31)
        XCTAssertEqual(s.device?.model, "OLED65G45LW.DEUQLJP")
        XCTAssertEqual(s.mac, "00:11:22:33:44:55")
        XCTAssertNotNil(s.mem?.total)
    }

    func testNestedAndArrayDrift() throws {
        let json = #"{"cores":[54,43.5,"x"],"mem":{"total":"x","avail":537952},"oled":{"panel_hours":1538.4,"comp_status":7},"volume":true,"inputs":{"hdmi1":"A"},"hdmi_diag":{"port":"4","vrr":true}}"#
        let s = try JSONDecoder().decode(Stats.self, from: Data(json.utf8))
        XCTAssertEqual(s.cores, [54, 44])
        XCTAssertNil(s.mem?.total)
        XCTAssertEqual(s.mem?.avail, 537952)
        XCTAssertEqual(s.oled?.panelHours, 1538)
        XCTAssertNil(s.oled?.compStatus)
        XCTAssertNil(s.volume)
        XCTAssertEqual(s.inputs, ["hdmi1": "A"])
        XCTAssertNil(s.hdmiDiag?.port)
        XCTAssertEqual(s.hdmiDiag?.vrr, true)
    }

    func testMinimalStatsDecodes() throws {
        let s = try JSONDecoder().decode(Stats.self, from: Data(#"{"ok":true}"#.utf8))
        XCTAssertNil(s.device); XCTAssertNil(s.powerState); XCTAssertNil(s.volume); XCTAssertNil(s.app)
        XCTAssertNil(s.inputs); XCTAssertNil(s.signal); XCTAssertNil(s.oled); XCTAssertNil(s.cores)
        XCTAssertNil(s.tvwebVersion); XCTAssertNil(s.uptime); XCTAssertNil(s.sleepTimer)
    }

    func testDecodesApps() throws {
        let stats = try JSONDecoder().decode(Stats.self, from: Fixture.data("stats"))
        XCTAssertTrue(stats.apps?.contains(Stats.App(id: "com.apple.appletv", title: "Apple TV")) ?? false)
        let standby = try JSONDecoder().decode(Stats.self, from: Fixture.data("stats-standby"))
        _ = standby.apps
    }

    func testAppWithoutIdOrTitleIsSkipped() throws {
        let json = ##"{"apps":[{"id":"a","title":"A","iconColor":"#fff"},{"id":"b"},{"title":"C"},5]}"##
        let s = try JSONDecoder().decode(Stats.self, from: Data(json.utf8))
        XCTAssertEqual(s.apps, [Stats.App(id: "a", title: "A")])
    }
}
