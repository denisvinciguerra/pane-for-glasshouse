import XCTest
@testable import PaneKit

final class KeyProfileTests: XCTestCase {
    func testGamingUsesPositions() {
        let s = KeyProfile.gaming.slots
        for (id, code, alt) in [(ButtonID.rcu(.up), 13, 126), (.rcu(.left), 0, 123), (.rcu(.down), 1, 125),
                                (.rcu(.right), 2, 124), (.rcu(.ok), 14, 36), (.rcu(.back), 12, 53)] as [(ButtonID, UInt16, UInt16)] {
            XCTAssertEqual(s[id]?.primary, KeyBinding(.keyCode(code)), id.rawValue)
            XCTAssertEqual(s[id]?.alternate, KeyBinding(.keyCode(alt)), id.rawValue)
        }
    }

    func testArrowsProfile() {
        let s = KeyProfile.arrows.slots
        XCTAssertEqual([ButtonID.rcu(.up), .rcu(.left), .rcu(.down), .rcu(.right)].map { s[$0]?.primary },
                       [126, 123, 125, 124].map { KeyBinding(.keyCode($0)) })
        XCTAssertEqual(s[.rcu(.ok)], KeySlot(primary: KeyBinding(.keyCode(36)), alternate: KeyBinding(.keyCode(76))))
        XCTAssertEqual(s[.rcu(.back)]?.primary, KeyBinding(.keyCode(53)))
    }

    func testInitialsInBothProfiles() {
        for p in KeyProfile.allCases {
            let s = p.slots
            for (id, c) in [(ButtonID.rcu(.home), "h"), (.rcu(.settings), "m"), (.mute, "k"), (.media(.playPause), " "),
                            (.volumeUp, "+"), (.volumeDown, "-")] {
                XCTAssertEqual(s[id]?.primary, KeyBinding(.character(c)), "\(p) \(id.rawValue)")
            }
        }
    }

    func testNoDuplicateBindingInAProfile() {
        for p in KeyProfile.allCases {
            let all = p.slots.values.flatMap { [$0.primary, $0.alternate].compactMap { $0 } }
            XCTAssertEqual(all.count, Set(all).count, "\(p)")
        }
    }
}
