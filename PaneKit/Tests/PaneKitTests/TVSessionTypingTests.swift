import XCTest
@testable import PaneKit

@MainActor
final class TVSessionTypingTests: XCTestCase {
    private func ready(_ api: FakeAPI, caps: Data? = nil) async -> TVSession {
        if let caps { await api.serve("/api/caps", caps) }
        let s = makeSession(api)
        await s.loadCapsAndTabs()
        await s.refreshStats()
        return s
    }

    func testSendTextReturnsServerAnswer() async {
        let api = FakeAPI()
        await api.answerText([ControlResult(ok: false, method: "none")])
        let s = await ready(api)
        let result = await s.sendText(.sendText(text: "a", replace: 0, full: "a"))
        XCTAssertEqual(result?.ok, false)
        XCTAssertEqual(result?.method, "none")
        let commands = await api.commands
        XCTAssertEqual(commands, [.sendText(text: "a", replace: 0, full: "a")])
    }

    func testSendTextBlockedSendsNothing() async {
        let api = FakeAPI()
        let s = await ready(api, caps: Data(#"{"allowControl":false,"allowPower":true,"version":"0.132.0"}"#.utf8))
        XCTAssertNotNil(s.blockedReason)
        let result = await s.sendText(.sendText(text: "a", replace: 0, full: "a"))
        XCTAssertNil(result)
        let commands = await api.commands
        XCTAssertEqual(commands, [])
    }

    func testFocusEpochCountsFocusCommandsOnly() async {
        let api = FakeAPI()
        let s = await ready(api)
        let e = s.focusEpoch
        await s.send(.volume(5))
        await s.send(.volumeStep(1))
        await s.send(.mute(true))
        await s.send(.media(.playPause))
        _ = await s.sendText(.sendText(text: "a", replace: 0, full: "a"))
        _ = await s.sendText(.submitText(full: "a"))
        await s.send(.keyboardKey("backspace"))
        XCTAssertEqual(s.focusEpoch, e)
        await s.send(.rcu(.home))
        XCTAssertEqual(s.focusEpoch, e + 1)
        await s.send(.launchApp("netflix"))
        XCTAssertEqual(s.focusEpoch, e + 2)
        await s.send(.input("HDMI_1"))
        XCTAssertEqual(s.focusEpoch, e + 3)
    }

    func testFocusEpochCountsFailedCommands() async {
        let api = FakeAPI()
        let s = await ready(api)
        let e = s.focusEpoch
        await api.failSend(.unreachable)
        await s.send(.rcu(.ok))
        XCTAssertEqual(s.focusEpoch, e + 1)
    }
}
