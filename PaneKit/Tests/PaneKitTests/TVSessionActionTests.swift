import XCTest
@testable import PaneKit

@MainActor
final class TVSessionActionTests: XCTestCase {
    /// Returns at once for a step pause, records it, and parks for anything else (the 4 s message).
    private func ready(_ api: FakeAPI, log: SleepLog = SleepLog()) async -> TVSession {
        let s = makeSession(api, sleep: { d in
            if d == .milliseconds(1500) { await log.record(d) } else { await parked(d) }
        })
        await s.loadCapsAndTabs()
        await s.refreshStats()
        return s
    }

    private let gameOn = ActionStep.setting(id: "gameOptimization", section: "game", title: "VRR", value: .bool(true), valueLabel: "ON")

    func testSequenceSendsStepsInOrderWithPause() async {
        let api = FakeAPI(), log = SleepLog()
        let s = await ready(api, log: log)
        await s.trigger(CustomAction(title: "A", steps: [.button(.source("hdmi4")), gameOn]))
        let sent = await api.commands
        XCTAssertEqual(sent, [.input("hdmi4"), .lgSetting(id: "gameOptimization", .bool(true))])
        let pauses = await log.durations
        XCTAssertEqual(pauses, [.milliseconds(1500)])
    }

    func testFailedStepStopsTheSequence() async {
        let api = FakeAPI()
        let s = await ready(api)
        await api.failSend(.rejected("no"))
        await s.trigger(CustomAction(title: "A", steps: [.button(.source("hdmi4")), gameOn]))
        let sent = await api.commands
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(s.transientMessage, "no")
    }

    func testUnavailableActionSaysWhyAndSendsNothing() async {
        let api = FakeAPI()
        let s = await ready(api)
        let action = CustomAction(title: "A", steps: [.launchApp(id: "gone.app", title: "G")])
        XCTAssertEqual(s.unavailableReason(action), "App not installed on this TV")
        await s.trigger(action)
        let sent = await api.commands
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(s.transientMessage, "App not installed on this TV")
    }

    func testUnknownButtonIsNeverSent() async {
        let api = FakeAPI()
        let s = await ready(api)
        await s.trigger(CustomAction(title: "A", steps: [.button(ButtonID(rawValue: "future.thing"))]))
        let sent = await api.commands
        XCTAssertTrue(sent.isEmpty)
        XCTAssertNotNil(s.transientMessage)
    }

    func testBlockedTVSaysWhy() async {
        let api = FakeAPI()
        await api.serve("/api/stats", Fixture.data("stats-standby"))
        let s = await ready(api)
        await s.trigger(CustomAction(title: "A", steps: [.button(.source("hdmi4"))]))
        let sent = await api.commands
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(s.transientMessage, "TV is in standby")
    }

    func testMuteStepUsesCurrentState() async {
        let api = FakeAPI()
        let s = await ready(api)
        XCTAssertEqual(s.stats?.muted, false)
        await s.trigger(CustomAction(title: "M", steps: [.button(.mute), .button(.mute)]))
        let sent = await api.commands
        XCTAssertEqual(sent, [.mute(true), .mute(false)])
    }

    func testSendReturnsFalseOnRejection() async {
        let api = FakeAPI()
        let s = await ready(api)
        let ok = await s.send(.rcu(.home))
        XCTAssertTrue(ok)
        await api.failSend(.rejected("no"))
        let failed = await s.send(.rcu(.home))
        XCTAssertFalse(failed)
    }

    func testSendReturnsFalseWhenBlocked() async {
        let s = makeSession(FakeAPI())
        let sent = await s.send(.rcu(.home))
        XCTAssertFalse(sent)
    }

    func testSayShowsOneMessage() {
        let s = makeSession(FakeAPI())
        s.say("hello")
        XCTAssertEqual(s.transientMessage, "hello")
    }

    func testAppIconAsksTheTVForTheApp() async {
        let api = FakeAPI()
        await api.serve("/api/apps/icon?id=com.example.app", Fixture.data("app-icon.png"))
        let s = makeSession(api)
        let icon = await s.appIcon("com.example.app")
        XCTAssertEqual(icon, Fixture.data("app-icon.png"))
    }

    func testAppIconIsNilWhenTheTVHasNone() async {
        let icon = await makeSession(FakeAPI()).appIcon("com.example.app")
        XCTAssertNil(icon)
    }
}
