import XCTest
@testable import PaneKit

final class KeyRecordingTests: XCTestCase {
    func testEscapeAloneCancels() {
        XCTAssertEqual(KeyRecording.input(KeyEvent(keyCode: KeyCode.escape, characters: "\u{1B}")), .cancel)
    }

    func testModifiedEscapeIsRecorded() {
        XCTAssertEqual(KeyRecording.input(KeyEvent(keyCode: KeyCode.escape, characters: "\u{1B}", modifiers: .shift)),
                       .record(KeyBinding(.keyCode(KeyCode.escape), modifiers: .shift)))
    }

    func testDeleteAloneClears() {
        XCTAssertEqual(KeyRecording.input(KeyEvent(keyCode: 51, characters: "\u{7F}")), .clear)
    }

    func testModifiedDeleteIsRecorded() {
        XCTAssertEqual(KeyRecording.input(KeyEvent(keyCode: 51, characters: "\u{7F}", modifiers: .command)),
                       .record(KeyBinding(.keyCode(51), modifiers: .command)))
    }

    func testOtherKeysAreRecordedAsTheProfilesDo() {
        XCTAssertEqual(KeyRecording.input(KeyEvent(keyCode: 4, characters: "H", modifiers: .shift)),
                       .record(KeyBinding(.character("h"))))
        XCTAssertEqual(KeyRecording.input(KeyEvent(keyCode: KeyCode.up, characters: "\u{F700}")),
                       .record(KeyBinding(.keyCode(KeyCode.up))))
    }

    func testKeyWithoutCharacterIsIgnored() {
        XCTAssertEqual(KeyRecording.input(KeyEvent(keyCode: 58, characters: "", modifiers: .option)), .ignore)
    }
}
