import XCTest
@testable import PaneKit

final class TypingEchoTests: XCTestCase {
    func testALetterLightsUpThenHasNoGlow() {
        var echo = TypingEcho()
        echo.textChanged("a", at: 100)
        XCTAssertEqual(echo.look(ofLetter: 0, at: 100).opacity, 0.2, accuracy: 0.001)
        XCTAssertEqual(echo.look(ofLetter: 0, at: 100).glow, 0.6, accuracy: 0.001)
        XCTAssertEqual(echo.look(ofLetter: 0, at: 100.55), TypingEcho.Look(opacity: 1, glow: 0))
    }
    func testOnlyTheNewLettersLightUp() {
        var echo = TypingEcho()
        echo.textChanged("ab", at: 100)
        echo.textChanged("abc", at: 105)
        XCTAssertEqual(echo.look(ofLetter: 0, at: 105), TypingEcho.Look(opacity: 1, glow: 0))
        XCTAssertEqual(echo.look(ofLetter: 2, at: 105).opacity, 0.2, accuracy: 0.001)
    }
    func testItLeavesTenSecondsAfterTheLastChangeThenHides() {
        var echo = TypingEcho()
        echo.textChanged("ab", at: 100)
        XCTAssertEqual(echo.phase(at: 109.9), .showing)
        XCTAssertEqual(echo.phase(at: 110.1), .leaving)
        XCTAssertEqual(echo.phase(at: 112), .hidden)
        XCTAssertEqual(echo.letters, ["a", "b"])
        XCTAssertEqual(echo.nextChange(after: 100), 110)
    }
    func testAKeyAfterTheFadeBringsTheWholeTextBackWithoutRelightingIt() {
        var echo = TypingEcho()
        echo.textChanged("ab", at: 100)
        echo.textChanged("abc", at: 120)
        XCTAssertEqual(echo.phase(at: 120), .showing)
        XCTAssertEqual(echo.look(ofLetter: 0, at: 120), TypingEcho.Look(opacity: 1, glow: 0))
    }
    func testLettersGoOutLeftToRight() {
        var echo = TypingEcho()
        echo.textChanged("abc", at: 100)
        echo.leave(at: 105)
        let first = echo.look(ofLetter: 0, at: 105.5).opacity
        let last = echo.look(ofLetter: 2, at: 105.5).opacity
        XCTAssertLessThan(first, last)
    }
    func testLeaveKeepsTheLettersAndTheEmptyFieldDoesNotCutItShort() {
        var echo = TypingEcho()
        echo.textChanged("ab", at: 100)
        echo.leave(at: 101)
        echo.textChanged("", at: 101)
        XCTAssertEqual(echo.phase(at: 101.1), .leaving)
        XCTAssertEqual(echo.letters, ["a", "b"])
    }
    func testTypingDuringALeaveStartsAfresh() {
        var echo = TypingEcho()
        echo.textChanged("ab", at: 100)
        echo.leave(at: 101)
        echo.textChanged("n", at: 101.2)
        XCTAssertEqual(echo.letters, ["n"])
        XCTAssertEqual(echo.phase(at: 101.2), .showing)
    }
    func testDeletingTheLastLetterHidesAtOnce() {
        var echo = TypingEcho()
        echo.textChanged("a", at: 100)
        echo.textChanged("", at: 101)
        XCTAssertEqual(echo.phase(at: 101), .hidden)
    }
    func testAnEmojiAndAComposedLetterStayWhole() {
        var echo = TypingEcho()
        echo.textChanged("👍🏽^", at: 100)
        echo.textChanged("👍🏽ê", at: 101)
        XCTAssertEqual(echo.letters, ["👍🏽", "ê"])
        XCTAssertEqual(echo.look(ofLetter: 0, at: 101), TypingEcho.Look(opacity: 1, glow: 0))
        XCTAssertEqual(echo.look(ofLetter: 1, at: 101).opacity, 0.2, accuracy: 0.001)
    }
    func testAPasteLightsAllItsLetters() {
        var echo = TypingEcho()
        echo.textChanged("hello", at: 100)
        XCTAssertEqual(echo.look(ofLetter: 4, at: 100).opacity, 0.2, accuracy: 0.001)
    }
    func testResetHidesAtOnce() {
        var echo = TypingEcho()
        echo.textChanged("a", at: 100)
        echo.reset()
        XCTAssertEqual(echo.phase(at: 100), .hidden)
        XCTAssertEqual(echo.letters, [])
    }
    func testNothingAnimatesOnceItIsSettled() {
        var echo = TypingEcho()
        echo.textChanged("a", at: 100)
        XCTAssertTrue(echo.isAnimating(at: 100.2))
        XCTAssertFalse(echo.isAnimating(at: 101))
    }
    func testReducedMotionHasNoGlowAndNoLetterByLetter() {
        var echo = TypingEcho(reducedMotion: true)
        echo.textChanged("ab", at: 100)
        XCTAssertEqual(echo.look(ofLetter: 0, at: 100), TypingEcho.Look(opacity: 1, glow: 0))
        echo.leave(at: 101)
        let first = echo.look(ofLetter: 0, at: 101.2)
        XCTAssertEqual(first, echo.look(ofLetter: 1, at: 101.2))
        XCTAssertEqual(first.glow, 0)
    }
    func testTextSizes() {
        XCTAssertEqual(TypingEcho.textSize(forCount: 12), 28)
        XCTAssertEqual(TypingEcho.textSize(forCount: 13), 23)
        XCTAssertEqual(TypingEcho.textSize(forCount: 22), 23)
        XCTAssertEqual(TypingEcho.textSize(forCount: 23), 19)
    }

    // Beyond the plan's tests.

    func testItWakesWhenTheLastLetterSettlesThenAtTheFade() {
        var echo = TypingEcho()
        echo.textChanged("a", at: 100)
        echo.textChanged("ab", at: 100.2)
        XCTAssertEqual(echo.nextWake(after: 100.6) ?? 0, 100.75, accuracy: 1e-9)
        XCTAssertEqual(echo.nextWake(after: 101), 110.2)
        XCTAssertNil(echo.nextWake(after: 200))
    }
    func testAnEarlyLeaveWinsOverTheTimedOne() {
        var echo = TypingEcho()
        echo.textChanged("ab", at: 100)
        echo.leave(at: 103)
        XCTAssertEqual(echo.phase(at: 103.1), .leaving)
        XCTAssertEqual(echo.nextChange(after: 103.1) ?? 0, 104.03, accuracy: 1e-9)
    }
    func testALeaveOnceTheFadeIsOverStillStartsTheNextTextAfresh() {
        var echo = TypingEcho()
        echo.textChanged("ab", at: 100)
        echo.leave(at: 120)
        echo.textChanged("c", at: 121)
        XCTAssertEqual(echo.letters, ["c"])
    }
    func testEditingInTheMiddleKeepsTheCommonPrefixOnly() {
        var echo = TypingEcho()
        echo.textChanged("abc", at: 100)
        echo.textChanged("abxy", at: 105)
        XCTAssertEqual(echo.look(ofLetter: 1, at: 105), TypingEcho.Look(opacity: 1, glow: 0))
        XCTAssertEqual(echo.look(ofLetter: 2, at: 105).opacity, 0.2, accuracy: 0.001)
        XCTAssertEqual(echo.look(ofLetter: 3, at: 105).opacity, 0.2, accuracy: 0.001)
    }

    func testDeletingLastLetterStartsItsDeparture() {
        var echo = TypingEcho()
        echo.textChanged("dune", at: 0)
        echo.textChanged("dun", at: 1)
        XCTAssertEqual(echo.departures, [.init(letter: "e", index: 3, start: 1)])
        XCTAssertEqual(echo.removalProgress(of: echo.departures[0], at: 1.11), 0.5, accuracy: 0.01)
        XCTAssertTrue(echo.isAnimating(at: 1.1))
    }

    func testDepartureEndsAfterRemovalTime() {
        var echo = TypingEcho()
        echo.textChanged("ab", at: 0)
        echo.textChanged("a", at: 5)
        XCTAssertFalse(echo.isAnimating(at: 5 + TypingEcho.removal + 0.01))
        echo.textChanged("ac", at: 6)
        XCTAssertEqual(echo.departures, [])   // finished ones are dropped at the next change
    }

    func testNoDepartureWithReducedMotion() {
        var echo = TypingEcho(reducedMotion: true)
        echo.textChanged("ab", at: 0)
        echo.textChanged("a", at: 1)
        XCTAssertEqual(echo.departures, [])
    }

    func testResetAndLeaveDropDepartures() {
        var echo = TypingEcho()
        echo.textChanged("ab", at: 0)
        echo.textChanged("a", at: 1)
        echo.reset()
        XCTAssertEqual(echo.departures, [])
        echo.textChanged("ab", at: 2)
        echo.textChanged("a", at: 3)
        echo.leave(at: 3.05)
        XCTAssertEqual(echo.departures, [])
    }

    func testDeletingTheOnlyLetterStillGetsItsDeparture() {
        var echo = TypingEcho()
        echo.textChanged("a", at: 0)
        echo.textChanged("", at: 1)
        XCTAssertEqual(echo.phase(at: 1), .hidden)
        XCTAssertEqual(echo.departures, [.init(letter: "a", index: 0, start: 1)])
        XCTAssertTrue(echo.isAnimating(at: 1.1))
        XCTAssertFalse(echo.isAnimating(at: 1.25))
    }
}
