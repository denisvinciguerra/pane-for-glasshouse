import XCTest
@testable import PaneKit

/// Counts the power-on polls and serves `turnedOn` from the `at`th one.
actor PollClock {
    private(set) var polls = 0
    private(set) var pauses: [Duration] = []
    func tick(_ d: Duration, api: FakeAPI, turnedOn: Data?, at: Int) async {
        pauses.append(d)
        guard d == TVSession.powerOnPoll else { return }
        polls += 1
        if let turnedOn, polls == at { await api.serve("/api/stats", turnedOn) }
    }
}

/// Parks every pause it is given until the test opens it; later pauses pass.
actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var open = false
    /// The pauses parked so far, released or not.
    private(set) var parkedCount = 0
    /// Every pause given, parked or not.
    private(set) var calls = 0
    func park() async {
        calls += 1
        guard !open else { return }
        parkedCount += 1
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        open = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// What a trigger returned, once it has.
@MainActor final class ResultBox {
    var result: ActionResult?
}

@MainActor
final class TVSessionPowerOnTests: XCTestCase {
    /// Returns at once for the polls, the settle pause, the step pauses and Always Ready's 1 s waits;
    /// parks for the 4 s message.
    private func session(_ api: FakeAPI, clock: PollClock, turnedOn: Data? = Fixture.data("stats"), at: Int = 1,
                         mac: String? = nil,
                         wake: @escaping @Sendable (String) async throws -> Void = { _ in XCTFail("no Wake-on-LAN expected") }) -> TVSession {
        makeSession(api, mac: mac, sleep: { d in
            if d == .seconds(4) { await parked(d) } else { await clock.tick(d, api: api, turnedOn: turnedOn, at: at) }
        }, wake: wake)
    }

    /// The session above, with its caps and its first stats read.
    private func ready(_ api: FakeAPI, clock: PollClock = PollClock(), turnedOn: Data? = Fixture.data("stats"), at: Int = 1,
                       mac: String? = nil,
                       wake: @escaping @Sendable (String) async throws -> Void = { _ in XCTFail("no Wake-on-LAN expected") }) async -> TVSession {
        let s = session(api, clock: clock, turnedOn: turnedOn, at: at, mac: mac, wake: wake)
        await s.loadCapsAndTabs()
        await s.refreshStats()
        return s
    }

    private let netflix = CustomAction(title: "Netflix", steps: [.launchApp(id: "netflix", title: "Netflix")])
    private let youtube = CustomAction(title: "YouTube", steps: [.launchApp(id: "youtube.leanback.v4", title: "YouTube")])

    /// The standby fixture as the G4 reports it while it shows LG's Always Ready screen.
    private var alwaysReady: Data {
        let text = String(decoding: Fixture.data("stats-standby"), as: UTF8.self)
        return Data(text.replacingOccurrences(of: #""raw": "Active Standby""#, with: #""raw": "Always Ready""#).utf8)
    }

    private var maintenance: Data { stats(#""comp_status": "Idle""#, #""comp_status": "Running""#) }

    func testTriggerFromStandbyPowersOnThenRuns() async {
        let api = FakeAPI(), clock = PollClock()
        await api.serve("/api/stats", Fixture.data("stats-standby"))
        let s = await ready(api, clock: clock)
        let result = await s.trigger(netflix)
        XCTAssertEqual(result, .sent)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn, .launchApp("netflix")])
        let pauses = await clock.pauses
        let firstPoll = pauses.firstIndex(of: TVSession.powerOnPoll)
        XCTAssertNotNil(firstPoll)
        XCTAssertTrue(pauses[(firstPoll ?? pauses.endIndex)...].contains(TVSession.settlePause))
        XCTAssertNil(s.pendingAction)
    }

    func testTriggerFromAlwaysReadyLeavesItFirst() async {
        let api = FakeAPI()
        await api.serve("/api/stats", alwaysReady)
        let s = await ready(api)
        let result = await s.trigger(netflix)
        XCTAssertEqual(result, .sent)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOff, .powerOn, .launchApp("netflix")])
    }

    func testTriggerWhenUnreachableWakesThenRuns() async {
        let api = FakeAPI(), woken = SentMACs()
        await api.fail("/api/stats", .unreachable)
        let on = Fixture.data("stats")
        let s = await ready(api, mac: "00:11:22:33:44:55", wake: { mac in
            await woken.add(mac)
            await api.serve("/api/stats", on)
        })
        let result = await s.trigger(netflix)
        XCTAssertEqual(result, .sent)
        let macs = await woken.macs
        XCTAssertEqual(macs, ["00:11:22:33:44:55"])
        let commands = await api.commands
        XCTAssertEqual(commands, [.launchApp("netflix")])
    }

    func testWakeThenStandbySendsPowerOnOnce() async {
        let api = FakeAPI()
        await api.fail("/api/stats", .unreachable)
        let standby = Fixture.data("stats-standby")
        let s = await ready(api, at: 3, mac: "00:11:22:33:44:55", wake: { _ in await api.serve("/api/stats", standby) })
        let result = await s.trigger(netflix)
        XCTAssertEqual(result, .sent)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn, .launchApp("netflix")], "one powerOn although two polls see standby")
    }

    func testTriggerGivesUpAfterTheTimeout() async {
        let api = FakeAPI(), clock = PollClock()
        await api.serve("/api/stats", Fixture.data("stats-standby"))
        let s = await ready(api, clock: clock, turnedOn: nil)
        let result = await s.trigger(netflix)
        XCTAssertEqual(result, .failed("The TV didn't turn on"))
        let polls = await clock.polls
        XCTAssertEqual(polls, 40)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn])
        XCTAssertEqual(s.transientMessage, SessionText.didNotTurnOn())
    }

    func testTriggerDuringMaintenanceSaysSoWhenTheSettingIsOff() async {
        let api = FakeAPI()
        await api.serve("/api/stats", maintenance)
        let s = await ready(api)
        XCTAssertEqual(s.power, .maintenance)
        let result = await s.trigger(netflix)
        XCTAssertEqual(result, .failed(SessionText.maintenance()))
        let commands = await api.commands
        XCTAssertEqual(commands, [])
    }

    func testTriggerDuringMaintenancePowersOnWhenTheSettingIsOn() async {
        let api = FakeAPI()
        await api.serve("/api/stats", maintenance)
        let s = await ready(api)
        s.powersOnDuringMaintenance = true
        let result = await s.trigger(netflix)
        XCTAssertEqual(result, .sent)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn, .launchApp("netflix")])
    }

    func testScreenOffOnlyActionDoesNotPowerOn() async {
        let api = FakeAPI()
        await api.serve("/api/stats", Fixture.data("stats-standby"))
        let s = await ready(api)
        let action = CustomAction(title: "Night", steps: [.screenOff, .sleepTimer("30")])
        XCTAssertFalse(s.canTrigger(action))
        let result = await s.trigger(action)
        XCTAssertEqual(result, .failed(SessionText.standby()))
        let commands = await api.commands
        XCTAssertEqual(commands, [])
    }

    func testTriggerWhileConnectingSendsNothing() async {
        let api = FakeAPI()
        let s = session(api, clock: PollClock())   // the default wake fails the test if called
        XCTAssertFalse(s.canTrigger(netflix))
        let result = await s.trigger(netflix)
        XCTAssertEqual(result, .failed(SessionText.connecting()))
        let commands = await api.commands
        XCTAssertEqual(commands, [])
    }

    func testTriggerOnTVWithUnknownCapsDoesNotPowerOn() async {
        let api = FakeAPI()
        await api.fail("/api/caps", .http(500))
        let s = await ready(api)
        XCTAssertEqual(s.power, .on)
        let result = await s.trigger(netflix)
        XCTAssertEqual(result, .failed(SessionText.capsUnknown()))
        let commands = await api.commands
        XCTAssertEqual(commands, [])
    }

    func testControlsOffWhileUnreachableSendsNothing() async {
        let api = FakeAPI()
        await api.serve("/api/caps", Data(#"{"allowControl":false,"allowPower":true,"version":"0.132.0"}"#.utf8))
        let s = await ready(api, mac: "aa:bb:cc:dd:ee:ff")
        await api.fail("/api/stats", .unreachable)
        await s.refreshStats()
        XCTAssertFalse(s.canTrigger(netflix))
        let result = await s.trigger(netflix)   // the default wake fails the test if called
        XCTAssertEqual(result, .failed(SessionText.controlsOff()))
        let commands = await api.commands
        XCTAssertEqual(commands, [])
    }

    func testControlsOffLearnedAfterWakeStopsTheWait() async {
        let api = FakeAPI(), clock = PollClock()
        await api.fail("/api/caps", .http(500))
        await api.fail("/api/stats", .unreachable)
        let controlsOff = Data(#"{"allowControl":false,"allowPower":true,"version":"0.132.0"}"#.utf8)
        let s = await ready(api, clock: clock, turnedOn: nil, mac: "00:11:22:33:44:55", wake: { _ in
            await api.serve("/api/caps", controlsOff)
            await api.serve("/api/stats", Fixture.data("stats"))
        })
        XCTAssertNil(s.caps)
        let result = await s.trigger(netflix)
        XCTAssertEqual(result, .failed(SessionText.controlsOff()))
        let polls = await clock.polls
        XCTAssertEqual(polls, 1, "stops at the first read that says controls are off")
        let commands = await api.commands
        XCTAssertEqual(commands, [])
    }

    func testTriggerRechecksTheActionOnceTheTVIsOn() async {
        let api = FakeAPI()
        await api.fail("/api/stats", .unreachable)
        let on = Fixture.data("stats")
        let s = await ready(api, mac: "00:11:22:33:44:55", wake: { _ in await api.serve("/api/stats", on) })
        let gone = CustomAction(title: "Gone", steps: [.launchApp(id: "gone.app", title: "Gone")])
        let result = await s.trigger(gone)
        XCTAssertEqual(result, .failed("App not installed on this TV"))
        let commands = await api.commands
        XCTAssertEqual(commands, [])
    }

    func testPowerRefusalsKeepTheirMessage() async {
        // Power turned off on the server.
        do {
            let api = FakeAPI()
            await api.serve("/api/caps", Data(#"{"allowControl":true,"allowPower":false,"version":"0.132.0"}"#.utf8))
            let s = await ready(api, mac: "aa:bb:cc:dd:ee:ff")
            await api.fail("/api/stats", .unreachable)
            await s.refreshStats()
            XCTAssertFalse(s.canTrigger(netflix))
            let result = await s.trigger(netflix)   // the default wake fails the test if called
            XCTAssertEqual(result, .failed(SessionText.powerOff()))
            let commands = await api.commands
            XCTAssertEqual(commands, [])
        }
        // Wake-on-LAN turned off on the TV, read before it went away.
        do {
            let api = FakeAPI()
            await api.serve("/api/stats", stats(#""wakeOnLan": true"#, #""wakeOnLan": false"#))
            let s = await ready(api, mac: "aa:bb:cc:dd:ee:ff")
            await api.fail("/api/stats", .unreachable)
            await s.refreshStats()
            XCTAssertFalse(s.canTrigger(netflix))
            let result = await s.trigger(netflix)
            XCTAssertEqual(result, .failed(SessionText.wakeOnLANOff()))
            let commands = await api.commands
            XCTAssertEqual(commands, [])
        }
        // Unreachable, no MAC known.
        do {
            let api = FakeAPI()
            await api.fail("/api/stats", .unreachable)
            let s = await ready(api)
            XCTAssertFalse(s.canTrigger(netflix))
            let result = await s.trigger(netflix)
            XCTAssertEqual(result, .failed(SessionText.noWakeOnLAN()))
            let commands = await api.commands
            XCTAssertEqual(commands, [])
        }
    }

    func testStatusLineSaysTurningOnWhileWaiting() async {
        let api = FakeAPI()
        await api.serve("/api/stats", Fixture.data("stats-standby"))
        // Parks at the first poll, so the wait lasts until the task is cancelled.
        let s = makeSession(api, sleep: { d in
            if d == .seconds(4) || d == TVSession.powerOnPoll { await parked(d) }
        })
        await s.loadCapsAndTabs()
        await s.refreshStats()
        let netflix = netflix
        let task = Task { await s.trigger(netflix) }
        for _ in 0..<1000 where s.pendingAction == nil { await Task.yield() }
        XCTAssertEqual(s.pendingAction?.id, netflix.id)
        XCTAssertEqual(s.blockedReason, SessionText.turningOn())
        task.cancel()
        _ = await task.value
    }

    func testCanTriggerDuringMaintenance() async {
        let api = FakeAPI()
        await api.serve("/api/stats", maintenance)
        let s = await ready(api)
        XCTAssertFalse(s.powersOnDuringMaintenance)
        XCTAssertTrue(s.canTrigger(netflix), "the tile stays clickable and the click explains")
    }

    // MARK: One power-on at a time

    /// A session in standby whose power-on polls park on `gate`, and its settle pause on `settle`
    /// when given; parks for the 4 s message.
    private func gated(_ api: FakeAPI, gate: Gate, settle: Gate? = nil) async -> TVSession {
        await api.serve("/api/stats", Fixture.data("stats-standby"))
        let s = makeSession(api, sleep: { d in
            if d == .seconds(4) { await parked(d) }
            else if d == TVSession.powerOnPoll { await gate.park() }
            else if d == TVSession.settlePause, let settle { await settle.park() }
        })
        await s.loadCapsAndTabs()
        await s.refreshStats()
        return s
    }

    /// Waits until `condition` holds, for 2 s at most; fails rather than hangs.
    private func waitUntil(_ condition: () async -> Bool, _ what: String,
                           file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("timed out waiting for \(what)", file: file, line: line)
    }

    /// Waits until a pause is parked on `gate`.
    private func waitParked(_ gate: Gate, file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil({ await gate.parkedCount > 0 }, "a parked pause", file: file, line: line)
    }

    /// The TV answers turned on, then the parked poll goes on.
    private func turnOn(_ api: FakeAPI, _ gate: Gate) async {
        await api.serve("/api/stats", Fixture.data("stats"))
        await gate.release()
    }

    func testSecondTriggerReplacesThePendingAction() async {
        let api = FakeAPI(), gate = Gate()
        let s = await gated(api, gate: gate)
        let (netflix, youtube) = (netflix, youtube)
        let t1 = Task { await s.trigger(netflix) }
        await waitUntil({ s.pendingAction?.id == netflix.id }, "the first pending action")
        await waitParked(gate)
        let t2 = Task { await s.trigger(youtube) }
        await waitUntil({ s.pendingAction?.id == youtube.id }, "the second pending action")
        await turnOn(api, gate)
        let r1 = await t1.value, r2 = await t2.value
        XCTAssertEqual(r1, .replaced)
        XCTAssertEqual(r2, .sent)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn, .launchApp("youtube.leanback.v4")], "a single powerOn")
        XCTAssertNil(s.pendingAction)
    }

    func testSameActionAgainChangesNothing() async {
        let api = FakeAPI(), gate = Gate()
        let s = await gated(api, gate: gate)
        let netflix = netflix
        let t1 = Task { await s.trigger(netflix) }
        await waitUntil({ s.pendingAction?.id == netflix.id }, "the pending action")
        await waitParked(gate)
        let second = ResultBox()
        let t2 = Task {
            let result = await s.trigger(netflix)
            second.result = result
            return result
        }
        await waitUntil({ second.result != nil }, "the second trigger to return without waiting")
        XCTAssertEqual(s.pendingAction?.id, netflix.id, "the first trigger still waits")
        await turnOn(api, gate)
        let r1 = await t1.value, r2 = await t2.value
        XCTAssertEqual(r2, .replaced)
        XCTAssertEqual(r1, .sent)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn, .launchApp("netflix")])
        XCTAssertNil(s.pendingAction)
    }

    func testPowerDuringTheWaitCancelsTheAction() async {
        let api = FakeAPI(), gate = Gate()
        let s = await gated(api, gate: gate)
        let netflix = netflix
        let t1 = Task { await s.trigger(netflix) }
        await waitUntil({ s.pendingAction?.id == netflix.id }, "the pending action")
        await waitParked(gate)
        await s.togglePower()
        XCTAssertNil(s.pendingAction)
        await turnOn(api, gate)
        let r1 = await t1.value
        XCTAssertEqual(r1, .cancelled)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn], "no second power command, no step")
        XCTAssertEqual(s.power, .on, "the TV finished turning on")
    }

    func testEndAbandonsTheWaitAndSendsNothing() async {
        let api = FakeAPI(), gate = Gate()
        let s = await gated(api, gate: gate)
        let netflix = netflix
        let t1 = Task { await s.trigger(netflix) }
        await waitUntil({ s.pendingAction?.id == netflix.id }, "the pending action")
        await waitParked(gate)
        s.end()
        XCTAssertNil(s.pendingAction)
        await turnOn(api, gate)
        let r1 = await t1.value
        XCTAssertEqual(r1, .cancelled)
        let again = await s.trigger(netflix)
        XCTAssertEqual(again, .cancelled)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn])
    }

    func testPowerDuringTheSettlePauseCancelsTheAction() async {
        let api = FakeAPI(), gate = Gate(), settle = Gate()
        let s = await gated(api, gate: gate, settle: settle)
        let netflix = netflix
        let t1 = Task { await s.trigger(netflix) }
        await waitParked(gate)
        await turnOn(api, gate)
        await waitParked(settle)
        XCTAssertEqual(s.pendingAction?.id, netflix.id, "the settle pause is part of the wait")
        await s.togglePower()
        XCTAssertNil(s.pendingAction)
        await settle.release()
        let r1 = await t1.value
        XCTAssertEqual(r1, .cancelled)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn])
    }

    func testSecondTriggerDuringTheSettlePauseReplaces() async {
        let api = FakeAPI(), gate = Gate(), settle = Gate()
        let s = await gated(api, gate: gate, settle: settle)
        let (netflix, youtube) = (netflix, youtube)
        let t1 = Task { await s.trigger(netflix) }
        await waitParked(gate)
        await turnOn(api, gate)
        await waitParked(settle)
        let t2 = Task { await s.trigger(youtube) }
        await waitUntil({ s.pendingAction?.id == youtube.id }, "the second pending action")
        await settle.release()
        let r1 = await t1.value, r2 = await t2.value
        XCTAssertEqual(r1, .replaced)
        XCTAssertEqual(r2, .sent)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn, .launchApp("youtube.leanback.v4")])
    }

    func testTriggerJoinsTheWaitWhileTheCapsAreUnknown() async {
        let api = FakeAPI(), gate = Gate()
        await api.fail("/api/caps", .http(500))
        let s = await gated(api, gate: gate)
        XCTAssertNil(s.caps)
        let (netflix, youtube) = (netflix, youtube)
        let t1 = Task { await s.trigger(netflix) }
        await waitParked(gate)
        // The TV reads on while its caps are still unknown, mid-wait.
        await api.serve("/api/stats", Fixture.data("stats"))
        await s.refreshStats()
        XCTAssertEqual(s.power, .on)
        let t2 = Task { await s.trigger(youtube) }
        await waitUntil({ s.pendingAction?.id == youtube.id }, "the second pending action")
        await api.serve("/api/caps", Fixture.data("caps"))
        await gate.release()
        let r1 = await t1.value, r2 = await t2.value
        XCTAssertEqual(r1, .replaced)
        XCTAssertEqual(r2, .sent)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn, .launchApp("youtube.leanback.v4")])
    }

    func testSecondPowerDuringTheWaitSendsNothing() async {
        let api = FakeAPI(), gate = Gate()
        let s = await gated(api, gate: gate)
        let netflix = netflix
        let t1 = Task { await s.trigger(netflix) }
        await waitParked(gate)
        await s.togglePower()
        await s.togglePower()
        await turnOn(api, gate)
        let r1 = await t1.value
        XCTAssertEqual(r1, .cancelled)
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn], "the TV is turning on: no power command either way")
    }

    func testEndStopsThePolling() async {
        let api = FakeAPI(), gate = Gate()
        let s = await gated(api, gate: gate)
        let netflix = netflix
        let t1 = Task { await s.trigger(netflix) }
        await waitParked(gate)
        s.end()
        await gate.release()   // the TV still reads standby
        let r1 = await t1.value
        XCTAssertEqual(r1, .cancelled)
        try? await Task.sleep(for: .milliseconds(100))
        let calls = await gate.calls
        XCTAssertEqual(calls, 1, "no poll after end()")
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn])
    }

    func testTimeoutWithTheCapsUnknownSaysSo() async {
        let api = FakeAPI()
        await api.fail("/api/caps", .http(500))
        await api.serve("/api/stats", Fixture.data("stats-standby"))
        let s = await ready(api)
        XCTAssertNil(s.caps)
        let result = await s.trigger(netflix)
        XCTAssertEqual(s.power, .on)
        XCTAssertEqual(result, .failed(SessionText.capsUnknown()))
        let commands = await api.commands
        XCTAssertEqual(commands, [.powerOn])
    }
}
