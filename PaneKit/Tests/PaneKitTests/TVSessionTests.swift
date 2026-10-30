import XCTest
@testable import PaneKit

@MainActor
final class TVSessionTests: XCTestCase {
    private func session(_ api: FakeAPI, mac: String? = nil,
                         sleep: @escaping @Sendable (Duration) async -> Void = parked,
                         wake: @escaping @Sendable (String) async throws -> Void = { _ in XCTFail("no Wake-on-LAN expected") }) -> TVSession {
        makeSession(api, mac: mac, sleep: sleep, wake: wake)
    }

    private func ready(_ api: FakeAPI = FakeAPI(), mac: String? = nil,
                       wake: @escaping @Sendable (String) async throws -> Void = { _ in XCTFail("no Wake-on-LAN expected") }) async -> TVSession {
        let s = session(api, mac: mac, wake: wake)
        await s.loadCapsAndTabs()
        await s.refreshStats()
        return s
    }

    func testStartsUnreachable() {
        let s = session(FakeAPI())
        XCTAssertEqual(s.power, .unreachable)
        XCTAssertNil(s.stats)
        XCTAssertFalse(s.canControl)
    }

    func testRefreshStatsSetsPower() async {
        let s = session(FakeAPI())
        await s.refreshStats()
        XCTAssertEqual(s.power, .on)
        XCTAssertEqual(s.stats?.volume, 31)
        XCTAssertNil(s.lastError)
    }

    func testUnreachableMarksStateAndKeepsLastStats() async {
        let api = FakeAPI()
        let s = await ready(api)
        XCTAssertTrue(s.canControl)
        await api.fail("/api/stats", .unreachable)
        await s.refreshStats()
        XCTAssertEqual(s.power, .unreachable)
        XCTAssertEqual(s.lastError, .unreachable)
        XCTAssertNotNil(s.stats)
        XCTAssertEqual(s.stats?.volume, 31)
        XCTAssertFalse(s.canControl)

        await api.serve("/api/stats", Fixture.data("stats"))
        await s.refreshStats()
        XCTAssertEqual(s.power, .on)
        XCTAssertNil(s.lastError)
    }

    func testBadTokenIsDistinctFromUnreachable() async {
        let api = FakeAPI()
        await api.fail("/api/stats", .badToken)
        let s = session(api)
        await s.refreshStats()
        XCTAssertEqual(s.lastError, .badToken)
        XCTAssertEqual(s.power, .unreachable)
    }

    func testControlDisabledBlocksCommands() async {
        let api = FakeAPI()
        await api.serve("/api/caps", Data(#"{"allowControl":false,"allowPower":true,"version":"0.132.0"}"#.utf8))
        let s = await ready(api)
        XCTAssertEqual(s.power, .on)
        XCTAssertFalse(s.canControl)
        await s.send(.rcu(.up))
        let commands = await api.commands
        XCTAssertEqual(commands, [])
        XCTAssertEqual(s.transientMessage, SessionText.controlsOff())
    }

    func testUnreachableBlocksCommands() async {
        let api = FakeAPI()
        let s = await ready(api)
        await api.fail("/api/stats", .unreachable)
        await s.refreshStats()
        await s.send(.mute(true))
        let commands = await api.commands
        XCTAssertEqual(commands, [])
        XCTAssertEqual(s.transientMessage, SessionText.unreachable())
    }

    func testOptimisticVolume() async {
        let api = FakeAPI()
        let s = await ready(api)
        await s.send(.volumeStep(1))
        XCTAssertEqual(s.stats?.volume, 32)
        await s.send(.volume(12))
        XCTAssertEqual(s.stats?.volume, 12)
        await s.send(.mute(true))
        XCTAssertEqual(s.stats?.muted, true)
        await s.send(.input("hdmi2"))
        XCTAssertEqual(s.stats?.app, "hdmi2")
        let commands = await api.commands
        XCTAssertEqual(commands, [.volumeStep(1), .volume(12), .mute(true), .input("hdmi2")])
        XCTAssertNil(s.transientMessage)
    }

    func testOptimisticSettingRow() async throws {
        let s = await ready()
        await s.refresh(.picture)
        let picture = try XCTUnwrap(s.picture)
        let number = try XCTUnwrap(picture.rows.first { if case .number = $0.kind { true } else { false } })
        await s.send(.lgSetting(id: number.id, .number(7)))
        guard case .number(let value, _, _) = s.picture?.rows.first(where: { $0.id == number.id })?.kind
        else { return XCTFail("row kind changed") }
        XCTAssertEqual(value, 7)

        let toggle = try XCTUnwrap(picture.rows.first { if case .toggle = $0.kind { true } else { false } })
        guard case .toggle(let was) = toggle.kind else { return XCTFail() }
        await s.send(.lgSetting(id: toggle.id, .bool(!was)))
        XCTAssertEqual(s.picture?.rows.first { $0.id == toggle.id }?.kind, .toggle(on: !was))

        let choice = try XCTUnwrap(picture.rows.first {
            if case .choice(_, let choices) = $0.kind { choices.count > 1 } else { false }
        })
        guard case .choice(let current, let choices) = choice.kind else { return XCTFail() }
        let other = try XCTUnwrap(choices.first { $0.value != current }).value
        await s.send(.lgSetting(id: choice.id, .string(other)))
        XCTAssertEqual(s.picture?.rows.first { $0.id == choice.id }?.kind, .choice(value: other, choices: choices))
    }

    func testRejectedCommandSurfacesErrorAndRollsBack() async {
        let api = FakeAPI()
        let s = await ready(api)
        await api.failSend(.rejected("x"))
        await s.send(.volumeStep(1))
        XCTAssertEqual(s.transientMessage, "x")
        XCTAssertEqual(s.lastError, .rejected("x"))
        XCTAssertEqual(s.stats?.volume, 31)
        await s.refreshStats()
        XCTAssertEqual(s.stats?.volume, 31)
        XCTAssertNil(s.lastError)
    }

    func testRejectedSettingRollsBackRow() async throws {
        let api = FakeAPI()
        let s = await ready(api)
        await s.refresh(.picture)
        let row = try XCTUnwrap(s.picture?.rows.first { if case .toggle = $0.kind { true } else { false } })
        guard case .toggle(let was) = row.kind else { return XCTFail() }
        await api.failSend(.rejected("nope"))
        await s.send(.lgSetting(id: row.id, .bool(!was)))
        XCTAssertEqual(s.picture?.rows.first { $0.id == row.id }?.kind, .toggle(on: was))
        XCTAssertEqual(s.transientMessage, "nope")
    }

    func testTransientMessageClearsAfterFourSeconds() async {
        let api = FakeAPI()
        let log = SleepLog()
        let s = TVSession(api: api, mac: nil, sleep: { await log.record($0) })
        await s.loadCapsAndTabs()
        await s.refreshStats()
        await api.failSend(.rejected("x"))
        await s.send(.mute(true))
        XCTAssertEqual(s.transientMessage, "x")
        await s.messageTask?.value
        XCTAssertNil(s.transientMessage)
        let durations = await log.durations
        XCTAssertEqual(durations, [.seconds(4)])
    }

    func testTogglePowerFromStandbyPowersOn() async {
        let api = FakeAPI()
        await api.serve("/api/stats", Fixture.data("stats-standby"))
        let s = await ready(api)
        XCTAssertEqual(s.power, .standby)
        await s.togglePower()
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn])
    }

    /// The standby fixture as the G4 reports it while it shows LG's Always Ready screen.
    private var alwaysReady: Data {
        let text = String(decoding: Fixture.data("stats-standby"), as: UTF8.self)
        return Data(text.replacingOccurrences(of: #""raw": "Active Standby""#, with: #""raw": "Always Ready""#).utf8)
    }

    func testTogglePowerFromAlwaysReadyLeavesItThenPowersOn() async {
        let api = FakeAPI()
        await api.serve("/api/stats", alwaysReady)
        // The TV reaches Active Standby while the session waits after powerOff.
        let standby = Fixture.data("stats-standby")
        let s = makeSession(api, sleep: { _ in await api.serve("/api/stats", standby) })
        await s.loadCapsAndTabs()
        await s.refreshStats()
        XCTAssertEqual(s.power, .standby)
        await s.togglePower()
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOff, .powerOn], "powerOn does nothing in Always Ready")
    }

    func testTogglePowerFromAlwaysReadyWaitsForActiveStandby() async {
        let api = FakeAPI()
        await api.serve("/api/stats", alwaysReady)
        let pauses = SleepLog()
        let s = makeSession(api, sleep: { await pauses.record($0) })
        await s.loadCapsAndTabs()
        await s.refreshStats()
        await s.togglePower()
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOff, .powerOn], "powerOn still goes once the wait runs out")
        let durations = await pauses.durations
        XCTAssertEqual(durations.filter { $0 == .seconds(1) }.count, 10)
    }

    func testTogglePowerFromAlwaysReadyStopsWhenPowerOffFails() async {
        let api = FakeAPI()
        await api.serve("/api/stats", alwaysReady)
        await api.failSend(.unreachable)
        let s = makeSession(api, sleep: { _ in })
        await s.loadCapsAndTabs()
        await s.refreshStats()
        await s.togglePower()
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOff])
    }

    func testTogglePowerFromOnPowersOff() async {
        let api = FakeAPI()
        let s = await ready(api)
        await s.togglePower()
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOff])
    }

    func testTogglePowerWhenUnreachableWakesTheTVsMAC() async {
        let api = FakeAPI()
        let woken = SentMACs()
        let s = await ready(api, mac: "aa:bb:cc:dd:ee:ff", wake: { await woken.add($0) })
        await api.fail("/api/stats", .unreachable)
        await s.refreshStats()
        XCTAssertFalse(s.canControl)
        await s.togglePower()
        let macs = await woken.macs
        XCTAssertEqual(macs, ["00:11:22:33:44:55"], "the MAC the TV reported wins over the stored one")
        let commands = await api.commands
        XCTAssertEqual(commands, [])
    }

    func testTogglePowerWhenUnreachableUsesStoredMAC() async {
        let api = FakeAPI()
        await api.fail("/api/stats", .unreachable)
        let woken = SentMACs()
        let s = session(api, mac: "aa:bb:cc:dd:ee:ff", wake: { await woken.add($0) })
        await s.refreshStats()
        await s.togglePower()
        let macs = await woken.macs
        XCTAssertEqual(macs, ["aa:bb:cc:dd:ee:ff"])
    }

    func testReportedMACIsPassedOnOnceForStorage() async {
        var learned: [String] = []
        let s = TVSession(api: FakeAPI(), mac: nil, sleep: parked, learnedMAC: { learned.append($0) })
        await s.refreshStats()
        await s.refreshStats()
        XCTAssertEqual(learned, ["00:11:22:33:44:55"])
    }

    func testKnownMACIsNotPassedOnAgain() async {
        let s = TVSession(api: FakeAPI(), mac: "00:11:22:33:44:55", sleep: parked,
                          learnedMAC: { _ in XCTFail("the stored MAC is the reported one") })
        await s.refreshStats()
    }

    func testTogglePowerWithoutMACExplains() async {
        let api = FakeAPI()
        await api.fail("/api/stats", .unreachable)
        let s = session(api)
        await s.refreshStats()
        await s.togglePower()
        XCTAssertEqual(s.transientMessage, SessionText.noWakeOnLAN())
    }

    func testRefreshPictureFillsPayload() async {
        let api = FakeAPI()
        let s = session(api)
        await s.refresh(.picture)
        XCTAssertEqual(s.picture?.rows.count, 54)
        let paths = await api.paths
        XCTAssertEqual(paths, ["/api/picture"])
    }

    func testAllTabsAvailableAtFirst() {
        XCTAssertEqual(session(FakeAPI()).availableTabs, PaneTab.allCases)
    }

    func testUnavailablePictureHidesTab() async {
        let api = FakeAPI()
        await api.serve("/api/picture", Data(#"{"available":false}"#.utf8))
        let s = session(api)
        await s.refresh(.picture)
        XCTAssertEqual(s.availableTabs, [.remote, .audio, .game, .hdmi, .stats])
    }

    func testNotFoundHidesTabAndLaterSuccessRestoresIt() async {
        let api = FakeAPI()
        await api.fail("/api/game", .http(404))
        let s = session(api)
        await s.refresh(.game)
        XCTAssertEqual(s.availableTabs, [.remote, .picture, .audio, .hdmi, .stats])
        await api.serve("/api/game", Fixture.data("game"))
        await s.refresh(.game)
        XCTAssertEqual(s.availableTabs, PaneTab.allCases)
    }

    func testLoadingCapsLearnsWhichTabsExistAndRestoresThem() async {
        let api = FakeAPI()
        await api.serve("/api/game", Data(#"{"available":false}"#.utf8))
        await api.fail("/api/audio?with=settings", .http(404))
        let s = session(api)
        await s.loadCapsAndTabs()
        XCTAssertEqual(s.availableTabs, [.remote, .picture, .hdmi, .stats])
        await api.serve("/api/game", Fixture.data("game"))
        await api.serve("/api/audio?with=settings", Fixture.data("audio"))
        await s.loadCapsAndTabs()
        XCTAssertEqual(s.availableTabs, PaneTab.allCases)
    }

    func testHDMINotFoundHidesTabAndLaterSuccessRestoresIt() async {
        let api = FakeAPI()
        await api.fail("/api/hdmi", .http(404))
        let s = session(api)
        await s.refresh(.hdmi)
        XCTAssertEqual(s.availableTabs, [.remote, .picture, .audio, .game, .stats])
        await api.serve("/api/hdmi", Fixture.data("hdmi"))
        await s.refresh(.hdmi)
        XCTAssertEqual(s.availableTabs, PaneTab.allCases)
    }

    func testOpeningProbesHDMIOnlyWhileHidden() async {
        let api = FakeAPI()
        let s = session(api)
        await s.loadCapsAndTabs()
        var hdmiReads = await api.paths.filter { $0 == "/api/hdmi" }.count
        XCTAssertEqual(hdmiReads, 0, "a visible HDMI tab reads when shown")
        await api.fail("/api/hdmi", .http(404))
        await s.refresh(.hdmi)
        await api.serve("/api/hdmi", Fixture.data("hdmi"))
        await s.loadCapsAndTabs()
        XCTAssertEqual(s.availableTabs, PaneTab.allCases, "the hidden tab came back")
        hdmiReads = await api.paths.filter { $0 == "/api/hdmi" }.count
        XCTAssertEqual(hdmiReads, 2)
    }

    func testNetworkFailureKeepsTab() async {
        let api = FakeAPI()
        await api.fail("/api/audio?with=settings", .unreachable)
        let s = session(api)
        await s.refresh(.audio)
        XCTAssertEqual(s.availableTabs, PaneTab.allCases)
    }

    func testRefreshGameAndAudio() async {
        let api = FakeAPI()
        let s = session(api)
        await s.refresh(.game)
        await s.refresh(.audio)
        XCTAssertNotNil(s.game)
        XCTAssertNotNil(s.audio)
        let paths = await api.paths
        XCTAssertEqual(paths, ["/api/game", "/api/audio?with=settings"])
    }

    func testRefreshHDMIBuildsOverview() async throws {
        let api = FakeAPI()
        let s = await ready(api)
        await s.refresh(.hdmi)
        let hdmi = try XCTUnwrap(s.hdmi)
        let expected = HDMIOverview(
            hdmi: try JSONDecoder().decode(HDMIPayload.self, from: Fixture.data("hdmi")),
            stats: s.stats,
            audio: try JSONDecoder().decode(AudioPayload.self, from: Fixture.data("audio")),
            lgSettings: try JSONDecoder().decode(LGSettingsPayload.self, from: Fixture.data("lgsettings-hdmi-devices")))
        XCTAssertEqual(hdmi, expected)
        XCTAssertNotNil(s.audio)
        let paths = Set(await api.paths)
        XCTAssertTrue(paths.isSuperset(of: ["/api/hdmi", "/api/audio?with=settings", "/api/lgsettings?section=hdmi,devices"]))
    }

    func testRefreshHDMISurvivesMissingAudioAndSettings() async throws {
        let api = FakeAPI()
        let s = await ready(api)
        await api.fail("/api/audio?with=settings", .http(500))
        await api.fail("/api/lgsettings?section=hdmi,devices", .http(404))
        await s.refresh(.hdmi)
        let hdmi = try XCTUnwrap(s.hdmi)
        let expected = HDMIOverview(hdmi: try JSONDecoder().decode(HDMIPayload.self, from: Fixture.data("hdmi")),
                                    stats: s.stats, audio: nil, lgSettings: nil)
        XCTAssertEqual(hdmi, expected)
        XCTAssertNotNil(s.lastError)
    }

    func testWebTabsFromPage() async {
        let s = session(FakeAPI())
        await s.loadCapsAndTabs()
        XCTAssertEqual(s.webTabs.first?.id, "control")
        XCTAssertEqual(s.caps?.allowControl, true)
    }

    func testWebTabsFallBack() async {
        let api = FakeAPI()
        await api.fail("/", .http(404))
        let s = session(api)
        await s.loadCapsAndTabs()
        XCTAssertEqual(s.webTabs, DashboardTabs.fallback)

        await api.serve("/", Data("<html></html>".utf8))
        await s.loadCapsAndTabs()
        XCTAssertEqual(s.webTabs, DashboardTabs.fallback)
    }

    func testRunPollsFastWhenOpenAndSlowWhenClosed() async {
        let api = FakeAPI()
        let log = SleepLog()
        let s = TVSession(api: api, mac: nil, sleep: { d in
            await log.record(d)
            if await log.durations.count == 3 { withUnsafeCurrentTask { $0?.cancel() } }
        })
        var opens = [true, false, true]
        await s.run(open: { opens.removeFirst() })
        let durations = await log.durations
        XCTAssertEqual(durations, [.seconds(2), .seconds(30), .seconds(2)])
        XCTAssertEqual(s.power, .on)
        let statsReads = await api.paths.filter { $0 == "/api/stats" }.count
        XCTAssertEqual(statsReads, 3)
    }

    func testRunReadsStatsWithoutWaitingForThePage() async {
        let api = FakeAPI()
        await api.hold("/")
        let s = session(api, sleep: { _ in withUnsafeCurrentTask { $0?.cancel() } })
        let run = Task { await s.run(open: { true }) }
        await waitHeld(api, "/")
        for _ in 0..<1000 where s.power != .on { await Task.yield() }
        XCTAssertEqual(s.power, .on, "the stats land while the 638 KB page is still on its way")
        await api.release("/")
        await run.value
    }

    func testCancelledRunDoesNotFlashUnreachable() async {
        let api = FakeAPI()
        let s = await ready(api)
        XCTAssertEqual(s.power, .on)
        await api.cancelCallerOnStats()
        await s.run(open: { true })
        XCTAssertEqual(s.power, .on)
        XCTAssertNil(s.lastError)
        XCTAssertEqual(s.stats?.volume, 31)
    }

    func testMessagesInBothLanguages() {
        XCTAssertEqual(SessionText.controlsOff(lproj("en")), "Controls are turned off on this TV")
        XCTAssertEqual(SessionText.controlsOff(lproj("fr")), "Les commandes sont désactivées sur cette TV")
        XCTAssertEqual(SessionText.unreachable(lproj("en")), "TV unreachable")
        XCTAssertEqual(SessionText.unreachable(lproj("fr")), "TV injoignable")
        XCTAssertEqual(SessionText.noWakeOnLAN(lproj("en")), "Wake-on-LAN isn't available for this TV")
        XCTAssertEqual(SessionText.noWakeOnLAN(lproj("fr")), "Le Wake-on-LAN n’est pas disponible pour cette TV")
        XCTAssertEqual(SessionText.wakeFailed(lproj("en")), "Couldn't send Wake-on-LAN")
        XCTAssertEqual(SessionText.wakeFailed(lproj("fr")), "Impossible d’envoyer le Wake-on-LAN")
        XCTAssertEqual(SessionText.rejected(lproj("en")), "The TV refused the command")
        XCTAssertEqual(SessionText.rejected(lproj("fr")), "La TV a refusé la commande")
        XCTAssertEqual(SessionText.badToken(lproj("en")), "Wrong or missing token")
        XCTAssertEqual(SessionText.badToken(lproj("fr")), "Jeton erroné ou absent")
        XCTAssertEqual(SessionText.wakeOnLANOff(lproj("en")), "Wake-on-LAN is turned off on this TV")
        XCTAssertEqual(SessionText.wakeOnLANOff(lproj("fr")), "Le Wake-on-LAN est désactivé sur cette TV")
        XCTAssertEqual(SessionText.powerOff(lproj("en")), "Power control is turned off on this TV")
        XCTAssertEqual(SessionText.powerOff(lproj("fr")), "Le contrôle de l’alimentation est désactivé sur cette TV")
        XCTAssertEqual(SessionText.sendFailed(lproj("en")), "Couldn't send the command")
        XCTAssertEqual(SessionText.sendFailed(lproj("fr")), "Impossible d’envoyer la commande")
        XCTAssertEqual(SessionText.capsUnknown(lproj("en")), "Couldn't read this TV's permissions")
        XCTAssertEqual(SessionText.capsUnknown(lproj("fr")), "Impossible de lire les autorisations de cette TV")
        XCTAssertEqual(SessionText.standby(lproj("en")), "TV is in standby")
        XCTAssertEqual(SessionText.standby(lproj("fr")), "La TV est en veille")
    }

    // MARK: Blocked reasons

    func testBlockedReasonIsNilWhenControllable() async {
        let s = await ready()
        XCTAssertTrue(s.canControl)
        XCTAssertNil(s.blockedReason)
    }

    func testBadTokenBlocksWithTokenReasonAndNoWake() async {
        let api = FakeAPI()
        let s = await ready(api, mac: "aa:bb:cc:dd:ee:ff")
        await api.fail("/api/stats", .badToken)
        await s.refreshStats()
        XCTAssertEqual(s.power, .unreachable)
        XCTAssertEqual(s.blockedReason, SessionText.badToken())
        await s.send(.mute(true))
        XCTAssertEqual(s.transientMessage, SessionText.badToken())
        await s.togglePower()   // the default wake fails the test if called
        XCTAssertEqual(s.transientMessage, SessionText.badToken())
        let commands = await api.commands
        XCTAssertEqual(commands, [])
    }

    func testBlockedReasonPrefersControlsOff() async {
        let api = FakeAPI()
        await api.serve("/api/caps", Data(#"{"allowControl":false,"allowPower":true,"version":"0.132.0"}"#.utf8))
        let s = await ready(api)
        await api.fail("/api/stats", .badToken)
        await s.refreshStats()
        XCTAssertEqual(s.blockedReason, SessionText.controlsOff())
    }

    func testUnreachableReason() async {
        let api = FakeAPI()
        let s = await ready(api)
        await api.fail("/api/stats", .unreachable)
        await s.refreshStats()
        XCTAssertEqual(s.blockedReason, SessionText.unreachable())
    }

    func testWakeOnLANTurnedOffExplains() async {
        let api = FakeAPI()
        await api.serve("/api/stats", stats(#""wakeOnLan": true"#, #""wakeOnLan": false"#))
        let s = await ready(api, mac: "aa:bb:cc:dd:ee:ff")
        await api.fail("/api/stats", .unreachable)
        await s.refreshStats()
        await s.togglePower()   // the default wake fails the test if called
        XCTAssertEqual(s.transientMessage, SessionText.wakeOnLANOff())
    }

    func testPowerDisallowedBlocksTogglePower() async {
        let api = FakeAPI()
        await api.serve("/api/caps", Data(#"{"allowControl":true,"allowPower":false,"version":"0.132.0"}"#.utf8))
        let s = await ready(api, mac: "aa:bb:cc:dd:ee:ff")
        XCTAssertTrue(s.canControl)
        XCTAssertFalse(s.canPower)
        await s.togglePower()
        XCTAssertEqual(s.transientMessage, SessionText.powerOff())
        await api.fail("/api/stats", .unreachable)
        await s.refreshStats()
        await s.togglePower()   // no Wake-on-LAN either: the default wake fails the test if called
        XCTAssertEqual(s.transientMessage, SessionText.powerOff())
        let commands = await api.commands
        XCTAssertEqual(commands, [])
    }

    func testStandbyGreysCommandsButNotPower() async {
        let api = FakeAPI()
        await api.serve("/api/stats", Fixture.data("stats-standby"))
        let s = await ready(api)
        XCTAssertEqual(s.power, .standby)
        XCTAssertFalse(s.canControl)
        XCTAssertTrue(s.canPower)
        XCTAssertEqual(s.blockedReason, SessionText.standby())
        await s.send(.mute(true))
        XCTAssertEqual(s.transientMessage, SessionText.standby())
        await s.togglePower()
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn])
    }

    func testMaintenanceGreysCommandsAndScreenOffDoesNot() async {
        let api = FakeAPI()
        await api.serve("/api/stats", stats(#""comp_status": "Idle""#, #""comp_status": "Running""#))
        let s = await ready(api)
        XCTAssertEqual(s.power, .maintenance)
        XCTAssertFalse(s.canControl)
        XCTAssertEqual(s.blockedReason, SessionText.standby())
        await api.serve("/api/stats", stats(#""screenOn": true"#, #""screenOn": false"#))
        await s.refreshStats()
        XCTAssertEqual(s.power, .screenOff)
        XCTAssertTrue(s.canControl)
        XCTAssertNil(s.blockedReason)
    }

    func testCanPowerWithoutCaps() {
        XCTAssertTrue(session(FakeAPI()).canPower)
    }

    func testFailedSendShowsGenericMessage() async {
        let api = FakeAPI()
        let s = await ready(api)
        await api.failSend(.http(500))
        await s.send(.rcu(.ok))
        XCTAssertEqual(s.transientMessage, SessionText.sendFailed())
        XCTAssertEqual(s.lastError, .http(500))
        await api.failSend(.badToken)
        await s.send(.rcu(.ok))
        XCTAssertEqual(s.transientMessage, SessionText.badToken())
    }

    // MARK: Caps

    func testCapsDecodeLeniently() throws {
        let empty = try JSONDecoder().decode(Caps.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.allowControl)
        XCTAssertTrue(empty.allowPower)
        XCTAssertEqual(empty.version, "")
        let drifted = try JSONDecoder().decode(Caps.self, from: Data(#"{"allowControl":"yes","allowPower":false,"version":133}"#.utf8))
        XCTAssertTrue(drifted.allowControl)
        XCTAssertFalse(drifted.allowPower)
        XCTAssertEqual(drifted.version, "")
    }

    func testCapsOK() throws {
        XCTAssertTrue(try JSONDecoder().decode(Caps.self, from: Fixture.data("caps")).ok)
        XCTAssertFalse(try JSONDecoder().decode(Caps.self, from: Data(#"{"allowControl":true}"#.utf8)).ok)
        XCTAssertTrue(Caps.permissive.ok)
    }

    func testCapsNotFoundAllowsEverything() async {
        let api = FakeAPI()
        await api.fail("/api/caps", .http(404))
        let s = await ready(api)
        XCTAssertTrue(s.canControl)
        XCTAssertTrue(s.canPower)
        XCTAssertNil(s.blockedReason)
        XCTAssertNil(s.lastError)
    }

    func testCapsFailureIsNotCalledUnreachable() async {
        let api = FakeAPI()
        await api.fail("/api/caps", .http(500))
        let s = await ready(api)
        XCTAssertEqual(s.power, .on)
        XCTAssertFalse(s.canControl)
        XCTAssertEqual(s.blockedReason, SessionText.capsUnknown())
    }

    func testPageFailureLeavesLastErrorAlone() async {
        let api = FakeAPI()
        await api.fail("/", .http(500))
        let s = session(api)
        await s.loadCapsAndTabs()
        XCTAssertNil(s.lastError)
        XCTAssertEqual(s.webTabs, DashboardTabs.fallback)
    }

    func testRunRetriesCapsAloneWithBackoff() async {
        let api = FakeAPI()
        await api.fail("/api/caps", .http(500))
        let log = SleepLog()
        let s = TVSession(api: api, mac: nil, sleep: { d in
            await log.record(d)
            if await log.durations.count == 7 { withUnsafeCurrentTask { $0?.cancel() } }
        })
        await s.run(open: { true })
        let paths = await api.paths
        // Stats at 0, 2, …, 12 s; the caps at 0 s (with the page), then 2 s and 6 s.
        XCTAssertEqual(paths.filter { $0 == "/api/stats" }.count, 7)
        XCTAssertEqual(paths.filter { $0 == "/api/caps" }.count, 3)
        XCTAssertEqual(paths.filter { $0 == "/" }.count, 1)
        XCTAssertEqual(paths.filter { $0 == "/api/picture" }.count, 1)
    }

    func testRunStopsRetryingOnceCapsAnswer() async {
        let api = FakeAPI()
        await api.fail("/api/caps", .http(500))
        let log = SleepLog()
        let s = TVSession(api: api, mac: nil, sleep: { d in
            await log.record(d)
            let n = await log.durations.count
            if n == 1 { await api.serve("/api/caps", Fixture.data("caps")) }
            if n == 5 { withUnsafeCurrentTask { $0?.cancel() } }
        })
        await s.run(open: { true })
        XCTAssertTrue(s.canControl)
        let capsReads = await api.paths.filter { $0 == "/api/caps" }.count
        XCTAssertEqual(capsReads, 2)
    }

    func testRetryBackoffDoublesUpToAMinute() {
        var backoff = RetryBackoff()
        var due: [Int] = []
        for t in stride(from: 0, through: 300, by: 2) {
            if backoff.due() { due.append(t) }
            backoff.wait(.seconds(2))
        }
        XCTAssertEqual(due, [2, 6, 14, 30, 62, 122, 182, 242])
    }

    // MARK: Read ordering

    private func waitHeld(_ api: FakeAPI, _ path: String) async {
        while await api.heldCount(path) == 0 { await Task.yield() }
    }

    func testOlderStatsReadLandingLastIsDropped() async {
        let api = FakeAPI()
        let s = await ready(api)
        await api.hold("/api/stats")
        let older = Task { await s.refreshStats() }      // answers volume 31, late
        await waitHeld(api, "/api/stats")
        await api.serve("/api/stats", stats(#""volume": 31"#, #""volume": 40"#))
        await s.refreshStats()
        XCTAssertEqual(s.stats?.volume, 40)
        await api.release("/api/stats")
        await older.value
        XCTAssertEqual(s.stats?.volume, 40)
    }

    func testOlderFailureLandingLastIsDropped() async {
        let api = FakeAPI()
        let s = await ready(api)
        await api.fail("/api/stats", .unreachable)
        await api.hold("/api/stats")
        let older = Task { await s.refreshStats() }      // times out, late
        await waitHeld(api, "/api/stats")
        await api.serve("/api/stats", Fixture.data("stats"))
        await s.refreshStats()
        await api.release("/api/stats")
        await older.value
        XCTAssertEqual(s.power, .on)
        XCTAssertNil(s.lastError)
    }

    func testStatsReadAskedBeforeCommandDoesNotClobberOptimism() async {
        let api = FakeAPI()
        let s = await ready(api)
        await api.hold("/api/stats")
        let older = Task { await s.refreshStats() }      // answers volume 31
        await waitHeld(api, "/api/stats")
        await s.send(.volumeStep(1))
        XCTAssertEqual(s.stats?.volume, 32)
        await api.release("/api/stats")
        await older.value
        XCTAssertEqual(s.stats?.volume, 32)
        await api.serve("/api/stats", stats(#""volume": 31"#, #""volume": 32"#))
        await s.refreshStats()
        XCTAssertEqual(s.stats?.volume, 32)
    }

    func testPictureReadAskedBeforeSettingDoesNotClobberOptimism() async throws {
        let api = FakeAPI()
        let s = await ready(api)
        await s.refresh(.picture)
        let row = try XCTUnwrap(s.picture?.rows.first { if case .toggle = $0.kind { true } else { false } })
        guard case .toggle(let was) = row.kind else { return XCTFail() }
        await api.hold("/api/picture")
        let older = Task { await s.refresh(.picture) }
        await waitHeld(api, "/api/picture")
        await s.send(.lgSetting(id: row.id, .bool(!was)))
        await api.release("/api/picture")
        await older.value
        XCTAssertEqual(s.picture?.rows.first { $0.id == row.id }?.kind, .toggle(on: !was))
    }

    // MARK: Connecting, local network, version, lost contact

    func testConnectingUntilStatsAndCapsLanded() async {
        let api = FakeAPI()
        await api.hold("/api/caps")
        let s = session(api)
        XCTAssertTrue(s.connecting)
        let load = Task { await s.loadCapsAndTabs() }
        await s.refreshStats()
        XCTAssertTrue(s.connecting)
        XCTAssertEqual(s.blockedReason, "Connecting…")
        await waitHeld(api, "/api/caps")
        await api.release("/api/caps")
        await load.value
        XCTAssertFalse(s.connecting)
        XCTAssertNil(s.blockedReason)
    }

    func testConnectingNeverShowsCapsUnknown() async {
        let api = FakeAPI()
        await api.fail("/api/caps", .http(500))
        let s = session(api)
        await s.refreshStats()
        XCTAssertEqual(s.blockedReason, "Connecting…")
        XCTAssertNotEqual(s.blockedReason, SessionText.capsUnknown())
        await s.loadCapsAndTabs()
        XCTAssertFalse(s.connecting)
    }

    func testConnectingEndsWhenFirstStatsFails() async {
        let api = FakeAPI()
        await api.fail("/api/stats", .unreachable)
        let s = session(api)
        await s.loadCapsAndTabs()
        XCTAssertTrue(s.connecting)
        await s.refreshStats()
        XCTAssertFalse(s.connecting)
        XCTAssertEqual(s.blockedReason, SessionText.unreachable())
    }

    func testDeniedSaysSoAndSkipsWakeOnLAN() async {
        let api = FakeAPI()
        await api.fail("/api/stats", .localNetworkDenied)
        let s = session(api, mac: "00:11:22:33:44:55")
        await s.loadCapsAndTabs()
        await s.refreshStats()
        XCTAssertTrue(s.localNetworkDenied)
        XCTAssertEqual(s.blockedReason, SessionText.localNetworkDenied())
        await s.togglePower()
        XCTAssertEqual(s.transientMessage, SessionText.localNetworkDenied())
    }

    func testOutdatedVersion() async {
        for (version, expected) in [("0.125.0", "0.125.0"), ("0.132.0", nil), ("", nil)] as [(String, String?)] {
            let api = FakeAPI()
            let caps = String(decoding: Fixture.data("caps"), as: UTF8.self)
                .replacingOccurrences(of: "\"0.132.0\"", with: "\"\(version)\"")
            await api.serve("/api/caps", Data(caps.utf8))
            let s = session(api)
            XCTAssertNil(s.outdatedVersion)
            await s.loadCapsAndTabs()
            XCTAssertEqual(s.outdatedVersion, expected, version)
        }
    }

    func testLostContactAfterThreeUnreachableReads() async {
        let api = FakeAPI()
        let calls = Counter()
        let s = makeSession(api, lostContact: { calls.add() })
        await api.fail("/api/stats", .unreachable)
        for _ in 0..<3 { await s.refreshStats() }
        XCTAssertEqual(calls.value, 1)
        for _ in 0..<3 { await s.refreshStats() }
        XCTAssertEqual(calls.value, 2)
        await api.serve("/api/stats", Fixture.data("stats"))
        await s.refreshStats()
        await api.fail("/api/stats", .unreachable)
        for _ in 0..<2 { await s.refreshStats() }
        XCTAssertEqual(calls.value, 2)
        await s.refreshStats()
        XCTAssertEqual(calls.value, 3)
    }

    func testNoLostContactOnBadTokenOrDenial() async {
        let api = FakeAPI()
        let calls = Counter()
        let s = makeSession(api, lostContact: { calls.add() })
        await api.fail("/api/stats", .badToken)
        for _ in 0..<6 { await s.refreshStats() }
        await api.fail("/api/stats", .localNetworkDenied)
        for _ in 0..<6 { await s.refreshStats() }
        XCTAssertEqual(calls.value, 0)
    }

    func testAnsweredOnEveryStatsReadThatLands() async {
        let api = FakeAPI()
        let calls = Counter()
        let s = makeSession(api, answered: { calls.add() })
        await api.fail("/api/stats", .unreachable)
        await s.refreshStats()
        XCTAssertEqual(calls.value, 0)
        await api.serve("/api/stats", Fixture.data("stats"))
        await s.refreshStats()
        await s.refreshStats()
        XCTAssertEqual(calls.value, 2)
    }
}

actor SentMACs {
    private(set) var macs: [String] = []
    func add(_ mac: String) { macs.append(mac) }
}

@MainActor private final class Counter {
    private(set) var value = 0
    func add() { value += 1 }
}
