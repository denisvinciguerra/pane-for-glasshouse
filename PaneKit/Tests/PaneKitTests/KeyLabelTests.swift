import XCTest
@testable import PaneKit

final class KeyLabelTests: XCTestCase {
    func testGamingLabelsFollowLayout() {
        let s = KeyProfile.gaming.slots
        let ids: [ButtonID] = [.rcu(.up), .rcu(.left), .rcu(.down), .rcu(.right), .rcu(.ok), .rcu(.back)]
        func labels(_ l: FakeLayout) -> [String] { ids.map { KeyLabel.text(s[$0]!.primary!, layout: l) } }
        XCTAssertEqual(labels(azerty), ["Z", "Q", "S", "D", "E", "A"])
        XCTAssertEqual(labels(qwerty), ["W", "A", "S", "D", "E", "Q"])
    }

    func testSpecialKeysHaveGlyphs() {
        let expected: [(UInt16, String)] = [(126, "↑"), (123, "←"), (36, "↩"), (76, "⌤"), (53, "⎋"), (48, "⇥"),
                                            (51, "⌫"), (122, "F1"), (117, "⌦"), (115, "↖"), (119, "↘"),
                                            (116, "⇞"), (121, "⇟"), (120, "F2"), (111, "F12")]
        for (code, glyph) in expected {
            XCTAssertEqual(KeyLabel.text(KeyBinding(.keyCode(code)), layout: qwerty), glyph, "\(code)")
        }
    }

    func testCharactersAreUppercasedAndSpaceIsVisible() {
        XCTAssertEqual(KeyLabel.text(KeyBinding(.character("h")), layout: qwerty), "H")
        XCTAssertEqual(KeyLabel.text(KeyBinding(.character(" ")), layout: qwerty), "␣")
        XCTAssertEqual(KeyLabel.text(KeyBinding(.character("+")), layout: qwerty), "+")
    }

    func testModifiersInAppleOrder() {
        let b = KeyBinding(.character("1"), modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(KeyLabel.text(b, layout: qwerty), "⌃⌥⇧⌘1")
    }

    func testUnknownKeyCodeFallsBack() {
        XCTAssertEqual(KeyLabel.text(KeyBinding(.keyCode(42)), layout: qwerty), "#42")
    }

    @MainActor
    func testCurrentLayoutTranslatesSomething() {
        let c = CurrentKeyboardLayout().character(for: 0)
        XCTAssertFalse((c ?? "").isEmpty)
    }
}
