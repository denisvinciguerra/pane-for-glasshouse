import XCTest
@testable import PaneKit

final class LearnedKeyboardLayoutTests: XCTestCase {
    func testANSIUntilLearned() {
        let layout = LearnedKeyboardLayout()
        XCTAssertEqual(layout.character(for: 0x00), "a")
        XCTAssertEqual(layout.character(for: 0x0D), "w")
        XCTAssertEqual(layout.character(for: 0x12), "1")
        XCTAssertEqual(layout.character(for: 0x31), " ")
        XCTAssertNil(layout.character(for: KeyCode.returnKey))
    }

    func testLearnedCharacterWins() {
        let layout = LearnedKeyboardLayout()
        layout.learn(keyCode: 0x00, characters: "q")   // AZERTY
        XCTAssertEqual(layout.character(for: 0x00), "q")
        XCTAssertEqual(layout.character(for: 0x0D), "w", "a key not pressed yet keeps the ANSI character")
    }

    func testGamingLabelsFollowTheKeysPressed() {
        let layout = LearnedKeyboardLayout()
        for (code, c) in [(UInt16(0x0D), "z"), (0x00, "q"), (0x01, "s"), (0x02, "d")] { layout.learn(keyCode: code, characters: c) }
        let s = KeyProfile.gaming.slots
        let labels = [ButtonID.rcu(.up), .rcu(.left), .rcu(.down), .rcu(.right)].map { KeyLabel.text(s[$0]!.primary!, layout: layout) }
        XCTAssertEqual(labels, ["Z", "Q", "S", "D"])
    }

    /// Only the one character a key types on its own is kept: not the name iOS gives a special
    /// key (« UIKeyInputUpArrow »), no control or private-use character, nothing empty; a change
    /// says so.
    func testLearnReportsChangesAndIgnoresNonCharacters() {
        let layout = LearnedKeyboardLayout()
        XCTAssertTrue(layout.learn(keyCode: 0x00, characters: "q"))
        XCTAssertFalse(layout.learn(keyCode: 0x00, characters: "q"))
        XCTAssertFalse(layout.learn(keyCode: 0x0D, characters: ""))
        XCTAssertFalse(layout.learn(keyCode: 0x24, characters: "\r"))
        XCTAssertFalse(layout.learn(keyCode: 0x7E, characters: "UIKeyInputUpArrow"))
        XCTAssertFalse(layout.learn(keyCode: 0x72, characters: "UIKeyInputHelp"))
        XCTAssertFalse(layout.learn(keyCode: 0x7A, characters: "\u{F704}"))
        XCTAssertEqual(layout.character(for: 0x0D), "w")
        XCTAssertNil(layout.character(for: 0x24))
        XCTAssertNil(layout.character(for: 0x7E))
        XCTAssertNil(layout.character(for: 0x72))
    }

    /// One character may be several scalars: an accented letter typed as one.
    func testLearnsOneGraphemeOfSeveralScalars() {
        let layout = LearnedKeyboardLayout()
        XCTAssertTrue(layout.learn(keyCode: 0x13, characters: "e\u{301}"))
        XCTAssertEqual(layout.character(for: 0x13), "e\u{301}")
    }

    func testIsSafeAcrossThreads() {
        let layout = LearnedKeyboardLayout()
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            layout.learn(keyCode: UInt16(i % 50), characters: i.isMultiple(of: 2) ? "x" : "y")
            _ = layout.character(for: UInt16(i % 50))
        }
        XCTAssertNotNil(layout.character(for: 0))
    }
}
