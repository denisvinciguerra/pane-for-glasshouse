import XCTest
@testable import PaneKit

final class DemoTVTests: XCTestCase {
    private func stats(_ tv: DemoTV) async throws -> Stats {
        try await tv.get("/api/stats", as: Stats.self)
    }

    func testServesStatsWithoutNetwork() async throws {
        let s = try await stats(DemoTV())
        XCTAssertEqual(s.device?.model, "OLED65G45LW")
        XCTAssertEqual(PowerState.from(s), .on)
    }

    func testSourceCommandChangesCurrentInput() async throws {
        let tv = DemoTV()
        try await tv.send(.input("hdmi2"))
        let s = try await stats(tv)
        XCTAssertEqual(s.appName, "PS7")
        XCTAssertEqual(s.app, "hdmi2")
        let hdmi = try await tv.get("/api/hdmi", as: HDMIPayload.self)
        XCTAssertEqual(hdmi.inputs.filter(\.active).map(\.label), ["PS7"])
    }

    func testVolumeCommands() async throws {
        let tv = DemoTV()
        let initial = try await stats(tv)
        let before = try XCTUnwrap(initial.volume)
        try await tv.send(.volumeStep(1))
        try await tv.send(.mute(true))
        let after = try await stats(tv)
        XCTAssertEqual(after.volume, before + 1)
        XCTAssertEqual(after.muted, true)
    }

    func testPowerOffThenOn() async throws {
        let tv = DemoTV()
        try await tv.send(.powerOff)
        let off = try await stats(tv)
        XCTAssertEqual(PowerState.from(off), .standby)
        try await tv.send(.powerOn)
        let on = try await stats(tv)
        XCTAssertEqual(PowerState.from(on), .on)
    }

    func testStartsInStandbyWhenAsked() async throws {
        let tv = DemoTV(standby: true)
        let off = try await stats(tv)
        XCTAssertEqual(PowerState.from(off), .standby)
        try await tv.send(.powerOn)
        let on = try await stats(tv)
        XCTAssertEqual(PowerState.from(on), .on)
    }

    func testLaunchingAnAppChangesNowShowing() async throws {
        let tv = DemoTV()
        try await tv.send(.launchApp("netflix"))
        let s = try await stats(tv)
        XCTAssertEqual(s.appName, "NetMovies")
        XCTAssertEqual(s.appId, "netflix")
    }

    func testPictureModeCommandUpdatesThePictureRow() async throws {
        let tv = DemoTV()
        try await tv.send(.pictureMode("hdrCinema"))
        let picture = try await tv.get("/api/picture", as: PicturePayload.self)
        let row = try XCTUnwrap(picture.rows.first { $0.id == "pictureMode" })
        guard case .choice(let value, _) = row.kind else { return XCTFail("not a choice") }
        XCTAssertEqual(value, "hdrCinema")
    }

    func testEveryPathTheSessionReadsDecodes() async throws {
        let tv = DemoTV()
        _ = try await tv.get("/api/caps", as: Caps.self)
        _ = try await tv.get("/api/game", as: GamePayload.self)
        _ = try await tv.get("/api/audio?with=settings", as: AudioPayload.self)
        _ = try await tv.get("/api/lgsettings?section=hdmi,devices", as: LGSettingsPayload.self)
    }

    func testAppIconIsServed() async throws {
        let data = try await DemoTV().getData("/api/apps/icon?id=netflix")
        XCTAssertGreaterThan(data.count, 8)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testDemoAppsAreInvented() async throws {
        let s = try await stats(DemoTV())
        XCTAssertEqual(s.apps?.map(\.title), ["PearTV", "NetMovies", "Musicify"])
        XCTAssertEqual(s.inputs, ["hdmi1": "Pear", "hdmi2": "PS7", "hdmi3": "YBox", "hdmi4": "PC"])
    }

    /// Ids (`netflix`, `com.webos.app.hdmi1`) are technical and never shown; every other string is.
    func testNoRealBrandInDemoData() throws {
        let brands = ["apple tv", "netflix", "spotify", "youtube", "ps5", "playstation", "xbox"]
        let idKeys: Set<String> = ["id", "app", "app_id", "appId"]
        func strings(_ value: Any, key: String?) -> [String] {
            switch value {
            case let s as String: return idKeys.contains(key ?? "") ? [] : [s]
            case let a as [Any]: return a.flatMap { strings($0, key: key) }
            case let d as [String: Any]: return d.flatMap { strings($0.value, key: $0.key) }
            default: return []
            }
        }
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appending(path: "../../Sources/PaneKit/Resources/Demo")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            for text in strings(json, key: nil) {
                let lower = text.lowercased()
                for brand in brands where lower.contains(brand) {
                    XCTFail("\(file.lastPathComponent): \"\(text)\" names \(brand)")
                }
            }
        }
    }

    func testEveryDemoAppHasAnIcon() async throws {
        let tv = DemoTV()
        let s = try await stats(tv)
        let apps = try XCTUnwrap(s.apps)
        for app in apps {
            let data = try await tv.getData("/api/apps/icon?id=\(app.id)")
            XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], app.id)
        }
    }

    @MainActor
    func testDemoSessionRereadsTheStatsAfterACommand() async {
        let session = TVSession(api: DemoTV(), mac: nil, sleep: { _ in }, rereadsAfterCommands: true)
        await session.loadCapsAndTabs()
        await session.refreshStats()
        let sent = await session.send(.launchApp("netflix"))
        XCTAssertTrue(sent)
        XCTAssertEqual(session.stats?.appName, "NetMovies")
    }

    @MainActor
    func testOtherSessionsWaitForThePoll() async {
        let session = TVSession(api: DemoTV(), mac: nil, sleep: { _ in })
        await session.loadCapsAndTabs()
        await session.refreshStats()
        let sent = await session.send(.launchApp("netflix"))
        XCTAssertTrue(sent)
        XCTAssertEqual(session.stats?.appName, "Pear")
    }

    func testUnknownPathIs404() async throws {
        do {
            _ = try await DemoTV().get("/api/nope", as: Stats.self)
            XCTFail("expected a 404")
        } catch {
            XCTAssertEqual(error, .http(404))
        }
    }
}
