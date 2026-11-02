import XCTest
@testable import PaneKit

final class GlobalKeyTests: XCTestCase {
    func testGlobalKeyNeedsCommandControlOrOption() {
        XCTAssertEqual(GlobalKey.input(KeyEvent(keyCode: 45, characters: "n")), .needsModifier)
        XCTAssertEqual(GlobalKey.input(KeyEvent(keyCode: 45, characters: "N", modifiers: .shift)), .needsModifier)
        XCTAssertEqual(GlobalKey.input(KeyEvent(keyCode: 45, characters: "n", modifiers: [.control, .option])),
                       .record(KeyBinding(.keyCode(45), modifiers: [.control, .option])))
    }

    func testShiftCounts() {
        let plain = GlobalKey.input(KeyEvent(keyCode: 35, characters: "p", modifiers: [.control, .option]))
        let shifted = GlobalKey.input(KeyEvent(keyCode: 35, characters: "P", modifiers: [.control, .option, .shift]))
        XCTAssertNotEqual(plain, shifted)
        XCTAssertEqual(shifted, .record(KeyBinding(.keyCode(35), modifiers: [.control, .option, .shift])))
    }

    func testEscapeCancelsAndDeleteClears() {
        XCTAssertEqual(GlobalKey.input(KeyEvent(keyCode: KeyCode.escape, characters: "\u{1b}")), .cancel)
        XCTAssertEqual(GlobalKey.input(KeyEvent(keyCode: 51, characters: "\u{7f}")), .clear)
        XCTAssertEqual(GlobalKey.input(KeyEvent(keyCode: 51, characters: "\u{7f}", modifiers: .command)),
                       .record(KeyBinding(.keyCode(51), modifiers: .command)))
    }

    func testModifierAloneIsIgnored() {
        XCTAssertEqual(GlobalKey.input(KeyEvent(keyCode: 58, characters: "", modifiers: .option)), .ignore)
    }

    func testPowerIsAGlobalButtonButNotARemoteOne() {
        XCTAssertEqual(ButtonID.globalButtons.first, .power)
        XCTAssertFalse(ButtonID.remote.contains(.power))
        XCTAssertEqual(ButtonID.power.fixedTitle(bundle: lproj("fr")), "Marche/Arrêt")
    }
}
