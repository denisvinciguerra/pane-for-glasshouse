import XCTest
@testable import PaneKit

@MainActor
final class TextTypingTests: XCTestCase {
    private var cleared = 0

    private func typing(_ api: FakeAPI) async -> TextTyping {
        let s = makeSession(api)
        await s.loadCapsAndTabs()
        await s.refreshStats()
        let t = TextTyping(session: s, now: { 100 })
        t.clearField = { [weak self] in self?.cleared += 1 }
        return t
    }

    /// Yields until the condition holds, within a bounded number of turns.
    private func until(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("condition never met", file: file, line: line)
    }

    /// Lets any request started by the last call reach the server.
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    func testTypingSendsDiffs() async {
        let api = FakeAPI()
        let t = await typing(api)
        t.fieldChanged("du")
        await until { await api.commands.count == 1 }
        await settle()
        t.fieldChanged("dune")
        await until { await api.commands.count == 2 }
        let commands = await api.commands
        XCTAssertEqual(commands, [.sendText(text: "du", replace: 0, full: "du"),
                                  .sendText(text: "ne", replace: 0, full: "dune")])
    }

    func testTypingDuringRequestSendsOneDiff() async {
        let api = FakeAPI()
        let t = await typing(api)
        await api.holdText()
        t.fieldChanged("d")
        await until { await api.heldTextCount() == 1 }
        t.fieldChanged("du")
        t.fieldChanged("dun")
        await api.releaseText()
        await until { await api.commands.count == 2 }
        await settle()
        let commands = await api.commands
        XCTAssertEqual(commands, [.sendText(text: "d", replace: 0, full: "d"),
                                  .sendText(text: "un", replace: 0, full: "dun")])
    }

    func testReturnSubmitsAndShowsSent() async {
        let api = FakeAPI()
        let t = await typing(api)
        t.fieldChanged("dune")
        t.returnPressed()
        XCTAssertEqual(t.echo.phase(at: 100), .leaving)
        await until { t.sentAt != nil }
        let commands = await api.commands
        XCTAssertEqual(commands.last, .submitText(full: "dune"))
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(cleared, 1)
        XCTAssertEqual(t.echo.phase(at: 100), .leaving)
    }

    func testReturnWithNothingTypedPressesOK() async {
        let api = FakeAPI()
        let t = await typing(api)
        t.returnPressed()
        await until { await api.commands.count == 1 }
        await settle()
        let commands = await api.commands
        XCTAssertEqual(commands, [.rcu(.ok)])
        XCTAssertNil(t.sentAt)
    }

    func testBackspaceOnEmptySendsKey() async {
        let api = FakeAPI()
        let t = await typing(api)
        t.backspaceOnEmpty()
        await until { await api.commands.count == 1 }
        let commands = await api.commands
        XCTAssertEqual(commands, [.keyboardKey("backspace")])
    }

    func testSpaceOnEmptyPlaysOrPauses() async {
        let api = FakeAPI()
        let t = await typing(api)
        t.spaceOnEmpty()
        await until { await api.commands.count == 1 }
        let commands = await api.commands
        XCTAssertEqual(commands, [.media(.playPause)])
    }

    func testArrowPressesTheKey() async {
        let api = FakeAPI()
        let t = await typing(api)
        t.arrow(.left)
        await until { await api.commands.count == 1 }
        let commands = await api.commands
        XCTAssertEqual(commands, [.rcu(.left)])
    }

    func testBackPressesBack() async {
        let api = FakeAPI()
        let t = await typing(api)
        t.back()
        await until { await api.commands.count == 1 }
        let commands = await api.commands
        XCTAssertEqual(commands, [.rcu(.back)])
    }

    func testEscapeClearsTextOnTV() async {
        let api = FakeAPI()
        let t = await typing(api)
        t.fieldChanged("dune")
        await until { await api.commands.count == 1 }
        await settle()
        XCTAssertTrue(t.escapePressed())
        XCTAssertEqual(cleared, 1)
        XCTAssertEqual(t.echo.phase(at: 100), .leaving)
        await until { await api.commands.count == 2 }
        await settle()
        var commands = await api.commands
        XCTAssertEqual(commands.last, .sendText(text: "", replace: 4, full: ""))
        XCTAssertFalse(t.escapePressed())
        await settle()
        commands = await api.commands
        XCTAssertEqual(commands.count, 2)
    }

    func testPartialKeysSendClearsField() async {
        let api = FakeAPI()
        await api.answerText([ControlResult(ok: false, method: "keys", sent: 2)])
        let t = await typing(api)
        t.fieldChanged("dune")
        await until { self.cleared == 1 }
        XCTAssertEqual(t.notice, .lowercase)
        // The view empties its field and reports it: nothing goes out for that.
        t.fieldChanged("")
        await settle()
        let commands = await api.commands
        XCTAssertEqual(commands, [.sendText(text: "dune", replace: 0, full: "dune")])
    }

    func testNoFieldNotice() async {
        let api = FakeAPI()
        await api.answerText([ControlResult(ok: false, method: "none")])
        let t = await typing(api)
        t.fieldChanged("d")
        await until { t.notice == .noField }
        await settle()
        t.fieldChanged("du")
        await until { await api.commands.count == 2 }
        await until { t.notice == nil }
        let commands = await api.commands
        XCTAssertEqual(commands.last, .sendText(text: "du", replace: 0, full: "du"))
    }

    func testFailedSendNotice() async {
        let api = FakeAPI()
        await api.failSend(.unreachable)
        let t = await typing(api)
        t.fieldChanged("d")
        await until { t.notice == .notSent }
        await settle()
        await api.failSend(nil)
        t.fieldChanged("du")
        await until { await api.commands.count == 2 }
        await until { t.notice == nil }
        let commands = await api.commands
        XCTAssertEqual(commands.last, .sendText(text: "du", replace: 0, full: "du"))
    }

    func testRefusedSendNotice() async {
        let api = FakeAPI()
        await api.answerText([ControlResult(ok: false, error: "x")])
        let t = await typing(api)
        t.fieldChanged("d")
        await until { t.notice == .notSent }
        await settle()
        t.fieldChanged("du")
        await until { await api.commands.count == 2 }
        await until { t.notice == nil }
    }

    func testReturnWaitsForEditsHeld() async {
        let api = FakeAPI()
        let t = await typing(api)
        await api.holdText()
        t.fieldChanged("dun")
        await until { await api.heldTextCount() == 1 }
        t.fieldChanged("dune")
        t.returnPressed()
        await api.releaseText()
        await until { t.sentAt != nil }
        let commands = await api.commands
        XCTAssertEqual(commands, [.sendText(text: "dun", replace: 0, full: "dun"),
                                  .sendText(text: "e", replace: 0, full: "dune"),
                                  .submitText(full: "dune")])
    }

    func testReturnAfterFailedEditSubmitsNothing() async {
        let api = FakeAPI()
        await api.failSend(.unreachable)
        let t = await typing(api)
        t.fieldChanged("dune")
        t.returnPressed()
        await until { t.notice == .notSent }
        await settle()
        let commands = await api.commands
        XCTAssertEqual(commands, [.sendText(text: "dune", replace: 0, full: "dune")])
    }

    func testForgetDropsStaleAnswerAndStartsFresh() async {
        let api = FakeAPI()
        let t = await typing(api)
        await api.holdText()
        t.fieldChanged("dune")
        await until { await api.heldTextCount() == 1 }
        t.forget()
        XCTAssertEqual(cleared, 1)
        XCTAssertTrue(t.echo.letters.isEmpty)
        await api.releaseText()
        await settle()
        t.fieldChanged("x")
        await until { await api.commands.count == 2 }
        let commands = await api.commands
        XCTAssertEqual(commands.last, .sendText(text: "x", replace: 0, full: "x"))
    }

    func testForgetDropsTheStaleAnswersNotice() async {
        let api = FakeAPI()
        await api.answerText([ControlResult(ok: false, method: "none")])
        let t = await typing(api)
        await api.holdText()
        t.fieldChanged("d")
        await until { await api.heldTextCount() == 1 }
        t.forget()
        await api.releaseText()
        await settle()
        XCTAssertNil(t.notice)
    }

    func testComposingUpdatesEchoWithoutSending() async {
        let api = FakeAPI()
        let t = await typing(api)
        t.fieldChanged("^", composing: true)
        await settle()
        let commands = await api.commands
        XCTAssertEqual(commands, [])
        XCTAssertEqual(t.echo.letters, ["^"])
    }

    func testLimitedTextIsReturned() async {
        let api = FakeAPI()
        let t = await typing(api)
        let kept = t.fieldChanged(String(repeating: "a", count: 600), composing: false)
        XCTAssertEqual(kept.utf16.count, 500)
    }
}
