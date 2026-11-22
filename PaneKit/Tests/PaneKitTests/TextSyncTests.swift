import XCTest
@testable import PaneKit

final class TextSyncTests: XCTestCase {
    func testSendsOnlyWhatChanged() {
        var s = TextSync()
        XCTAssertEqual(s.edited(to: "abc"), .sendText(text: "abc", replace: 0, full: "abc"))
        _ = s.acknowledged(ok: true, sent: nil)
        XCTAssertEqual(s.edited(to: "abx"), .sendText(text: "x", replace: 1, full: "abx"))
    }
    func testOneRequestAtATimeThenTheLatestText() {
        var s = TextSync()
        _ = s.edited(to: "a")
        XCTAssertNil(s.edited(to: "ab"))
        XCTAssertNil(s.edited(to: "abc"))
        XCTAssertEqual(s.acknowledged(ok: true, sent: nil).next, .sendText(text: "bc", replace: 0, full: "abc"))
    }
    func testEmptyingTheFieldDeletesOnTheTV() {
        var s = TextSync()
        _ = s.edited(to: "abc"); _ = s.acknowledged(ok: true, sent: nil)
        XCTAssertEqual(s.edited(to: ""), .sendText(text: "", replace: 3, full: ""))
    }
    func testForgetSendsNothingAndStartsAgain() {
        var s = TextSync()
        _ = s.edited(to: "abc"); _ = s.acknowledged(ok: true, sent: nil)
        s.forget()
        XCTAssertEqual(s.edited(to: "d"), .sendText(text: "d", replace: 0, full: "d"))
    }
    func testLateAnswerAfterForgetIsIgnored() {
        var s = TextSync()
        _ = s.edited(to: "abc")
        s.forget()
        XCTAssertNil(s.acknowledged(ok: true, sent: nil).next)
        XCTAssertEqual(s.edited(to: "d"), .sendText(text: "d", replace: 0, full: "d"))
    }
    func testTextTypedBeforeALateAnswerIsHeldThenSentFromEmpty() {
        var s = TextSync()
        _ = s.edited(to: "abc")
        s.forget()
        XCTAssertNil(s.edited(to: "d"))
        let answer = s.acknowledged(ok: true, sent: nil)
        XCTAssertEqual(answer.next, .sendText(text: "d", replace: 0, full: "d"))
        XCTAssertFalse(answer.clearField)
    }
    func testStaleAnswerNeverClearsTheField() {
        var s = TextSync()
        _ = s.edited(to: "abc")
        s.forget()
        XCTAssertFalse(s.acknowledged(ok: false, sent: 1).clearField)
    }
    func testAnswerWithNothingOutIsHarmless() {
        var s = TextSync()
        let answer = s.acknowledged(ok: true, sent: nil)
        XCTAssertNil(answer.next)
        XCTAssertFalse(answer.clearField)
        XCTAssertEqual(s.edited(to: "a"), .sendText(text: "a", replace: 0, full: "a"))
    }
    func testDoesNotSplitAnEmoji() {
        var s = TextSync()
        _ = s.edited(to: "a😀"); _ = s.acknowledged(ok: true, sent: nil)
        XCTAssertEqual(s.edited(to: "a😁"), .sendText(text: "😁", replace: 2, full: "a😁"))
    }
    func testFailureKeepsTheLastConfirmedText() {
        var s = TextSync()
        _ = s.edited(to: "a")
        XCTAssertFalse(s.acknowledged(ok: false, sent: nil).clearField)
        XCTAssertEqual(s.edited(to: "ab"), .sendText(text: "ab", replace: 0, full: "ab"))
    }
    func testPartialSendClearsTheFieldRatherThanRetype() {
        var s = TextSync()
        _ = s.edited(to: "abc")
        XCTAssertTrue(s.acknowledged(ok: false, sent: 1).clearField)
        XCTAssertEqual(s.edited(to: "d"), .sendText(text: "d", replace: 0, full: "d"))
    }
    func testSubmitSendsTheWholeTextAndStartsAgain() {
        var s = TextSync()
        _ = s.edited(to: "abc"); _ = s.acknowledged(ok: true, sent: nil)
        XCTAssertEqual(s.submit(), .submitText(full: "abc"))
        XCTAssertEqual(s.edited(to: "d"), .sendText(text: "d", replace: 0, full: "d"))
    }
    func testFailureWithHeldEditSendsNothingThenResendsFromConfirmed() {
        var s = TextSync()
        _ = s.edited(to: "a"); _ = s.acknowledged(ok: true, sent: nil)
        _ = s.edited(to: "ab")
        XCTAssertNil(s.edited(to: "abc"))
        XCTAssertNil(s.acknowledged(ok: false, sent: nil).next)
        XCTAssertEqual(s.edited(to: "abcd"), .sendText(text: "bcd", replace: 0, full: "abcd"))
    }
    func testLimit() {
        XCTAssertEqual(TextSync.limited(String(repeating: "a", count: 501)).utf16.count, 500)
        XCTAssertEqual(TextSync.limited(String(repeating: "a", count: 499) + "😀").utf16.count, 499)
    }
}
