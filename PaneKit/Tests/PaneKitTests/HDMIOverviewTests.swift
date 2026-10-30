import XCTest
@testable import PaneKit

final class HDMIOverviewTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: Fixture.data(name))
    }

    func testG4() throws {
        let overview = HDMIOverview(hdmi: try decode(HDMIPayload.self, "hdmi"), stats: try decode(Stats.self, "stats"),
                                    audio: try decode(AudioPayload.self, "audio"),
                                    lgSettings: try decode(LGSettingsPayload.self, "lgsettings-hdmi-devices"))
        XCTAssertEqual(overview.ports.map(\.name), ["HDMI 1", "Denon Home\u{00A0}Cinema", "Apple OTT", "PS5 Console de jeu"])
        XCTAssertEqual(overview.ports.map(\.id), [1, 2, 3, 4])
        XCTAssertTrue(overview.ports.allSatisfy(\.deviceSeen))
        XCTAssertEqual(overview.ports.map(\.isActive), [false, false, false, true])
        // Recorded fixture: 60 Hz and RGB 4:4:4. hdmi_diag.port is 3 (0-based) yet belongs to the active port 4.
        XCTAssertEqual(overview.ports[3].signal, "3840×2160 @ 60 Hz · FRL 32 Gbps · RGB 4:4:4 · HDCP 2.3")
        XCTAssertEqual(overview.ports[3].flags, ["ALLM"])
        for port in overview.ports.prefix(3) { XCTAssertNil(port.signal); XCTAssertEqual(port.flags, []) }
        XCTAssertEqual(overview.ports.map(\.isARC), [false, true, false, false])
        XCTAssertEqual(overview.receiver, "AVR-X4500H · eARC")
        let ids = overview.settings.map(\.id)
        XCTAssertTrue(ids.contains("deepColor")); XCTAssertTrue(ids.contains("simplinkEnable"))
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertTrue(overview.settings.allSatisfy { $0.section == "hdmi" || $0.section == "devices" })
    }

    func testNoStats() throws {
        let overview = HDMIOverview(hdmi: try decode(HDMIPayload.self, "hdmi"), stats: nil, audio: nil, lgSettings: nil)
        XCTAssertEqual(overview.ports.count, 4)
        XCTAssertTrue(overview.ports.allSatisfy { $0.signal == nil && $0.flags.isEmpty && !$0.isARC })
        XCTAssertNil(overview.receiver)
        XCTAssertEqual(overview.settings, [])
    }

    func testSettingsFallBackToAudioWithoutDuplicates() throws {
        let audio = try decode(AudioPayload.self, "audio")
        let overview = HDMIOverview(hdmi: try decode(HDMIPayload.self, "hdmi"), stats: nil, audio: audio, lgSettings: nil)
        let ids = overview.settings.map(\.id)
        XCTAssertTrue(ids.contains("deepColor"))
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertTrue(overview.settings.allSatisfy { $0.section == "hdmi" })
    }

    func testUnknownInputElementIsSkipped() throws {
        let json = #"{"inputs":[{"id":"HDMI_1","port":1,"label":"A","active":false},{"bogus":1}]}"#
        let hdmi = try JSONDecoder().decode(HDMIPayload.self, from: Data(json.utf8))
        XCTAssertEqual(hdmi.inputs.count, 1)
        XCTAssertFalse(HDMIOverview(hdmi: hdmi, stats: nil, audio: nil, lgSettings: nil).ports[0].deviceSeen)
    }
}
