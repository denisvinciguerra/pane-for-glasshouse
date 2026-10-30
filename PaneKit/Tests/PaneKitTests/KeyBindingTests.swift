import XCTest
@testable import PaneKit

final class KeyBindingTests: XCTestCase {
    func testRecordsSpecialKeysByPosition() {
        XCTAssertEqual(KeyBinding.recorded(KeyEvent(keyCode: 126, characters: "\u{F700}"))?.trigger, .keyCode(126))
        XCTAssertEqual(KeyBinding.recorded(KeyEvent(keyCode: 53, characters: "\u{1B}"))?.trigger, .keyCode(53))
        XCTAssertEqual(KeyBinding.recorded(KeyEvent(keyCode: 36, characters: "\r"))?.trigger, .keyCode(36))
    }

    func testRecordsOtherKeysByLowercasedCharacterWithoutShift() {
        XCTAssertEqual(KeyBinding.recorded(KeyEvent(keyCode: 4, characters: "H", modifiers: .shift)), KeyBinding(.character("h")))
        XCTAssertEqual(KeyBinding.recorded(KeyEvent(keyCode: 18, characters: "1", modifiers: .command)),
                       KeyBinding(.character("1"), modifiers: .command))
    }

    func testModifierKeyAloneRecordsNothing() {
        XCTAssertNil(KeyBinding.recorded(KeyEvent(keyCode: 58, characters: "", modifiers: .option)))
    }

    func testKeyCodeBindingNeedsExactModifiers() {
        let up = KeyBinding(.keyCode(126))
        XCTAssertTrue(up.matches(KeyEvent(keyCode: 126, characters: nil)))
        XCTAssertFalse(up.matches(KeyEvent(keyCode: 126, characters: nil, modifiers: .command)))
    }

    func testCharacterMatchesWhateverKeyCode() {
        let h = KeyBinding(.character("h"))
        XCTAssertTrue(h.matches(KeyEvent(keyCode: 4, characters: "h")))
        XCTAssertTrue(h.matches(KeyEvent(keyCode: 38, characters: "h")))
        XCTAssertTrue(KeyBinding(.character("+")).matches(KeyEvent(keyCode: 24, characters: "+", modifiers: .shift)))
        XCTAssertFalse(KeyBinding(.character("h"), modifiers: .command).matches(KeyEvent(keyCode: 4, characters: "h")))
    }

    func testCodableShape() throws {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        let a = KeyBinding(.keyCode(13)), b = KeyBinding(.character("h"), modifiers: .command)
        XCTAssertEqual(String(decoding: try enc.encode(a), as: UTF8.self), #"{"code":13,"mods":0}"#)
        XCTAssertEqual(String(decoding: try enc.encode(b), as: UTF8.self), #"{"char":"h","mods":1}"#)
        XCTAssertEqual(try JSONDecoder().decode(KeyBinding.self, from: enc.encode(a)), a)
        XCTAssertEqual(try JSONDecoder().decode(KeyBinding.self, from: enc.encode(b)), b)
    }

    func testButtonIDRoundTrip() throws {
        let u = UUID()
        XCTAssertEqual(ButtonID.action(u).actionID, u)
        XCTAssertEqual(ButtonID.source("hdmi4").rawValue, "source.hdmi4")
        XCTAssertEqual(ButtonID.source("hdmi4").sourceID, "hdmi4")
        XCTAssertNil(ButtonID.mute.actionID)
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(ButtonID.rcu(.up)), as: UTF8.self), "\"rcu.up\"")
        XCTAssertEqual(try JSONDecoder().decode(ButtonID.self, from: Data("\"mute\"".utf8)), .mute)
    }

    func testFixedTitlesAreLocalized() {
        XCTAssertEqual(ButtonID.rcu(.up).fixedTitle(bundle: lproj("fr")), "Haut")
        XCTAssertEqual(ButtonID.rcu(.home).fixedTitle(bundle: lproj("fr")), "Accueil")
        XCTAssertEqual(ButtonID.rcu(.home).fixedTitle(bundle: lproj("en")), "Home")
        XCTAssertEqual(ButtonID.volumeDown.fixedTitle(bundle: lproj("fr")), "Volume −")
        XCTAssertEqual(ButtonID.media(.playPause).fixedTitle(bundle: lproj("en")), "Play/Pause")
        XCTAssertNil(ButtonID.source("hdmi1").fixedTitle)
        XCTAssertEqual(ButtonID.remote.count, 15)
        for id in ButtonID.remote {
            XCTAssertNotNil(id.fixedTitle(bundle: lproj("fr")), id.rawValue)
        }
    }

    /// The amber bar, the conflict line, the Preferences row, the editor's menu and a pin's default
    /// title all name Home as the D-pad does.
    func testHomeIsNamedHomeEverywhere() {
        for (code, name) in [("en", "Home"), ("fr", "Accueil")] {
            XCTAssertEqual(ButtonID.rcu(.home).title(sources: [], actions: [], bundle: lproj(code)), name)
            XCTAssertEqual(ActionStep.button(.rcu(.home)).defaultTitle(sources: [], bundle: lproj(code)), name)
        }
        // Even where the catalogue cannot be read, not its key.
        XCTAssertEqual(ButtonID.rcu(.home).fixedTitle(bundle: Bundle(for: Self.self)), "Home")
    }
}
