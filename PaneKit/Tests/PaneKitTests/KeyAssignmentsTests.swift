import XCTest
@testable import PaneKit

final class KeyAssignmentsTests: XCTestCase {
    private func pos(_ c: UInt16) -> KeyBinding { KeyBinding(.keyCode(c)) }
    private func ch(_ c: String) -> KeyBinding { KeyBinding(.character(c)) }
    private var arrows: KeyAssignments { KeyAssignments(slots: KeyProfile.arrows.slots) }
    private var gaming: KeyAssignments { KeyAssignments(slots: KeyProfile.gaming.slots) }

    func testButtonForEventPrefersKeyCodeThenPrimary() {
        let a = KeyAssignments(slots: [
            .rcu(.home): KeySlot(primary: ch("w")),
            .rcu(.up): KeySlot(primary: pos(13)),
            .rcu(.back): KeySlot(primary: ch("x"), alternate: ch("y")),
            .mute: KeySlot(primary: ch("z"), alternate: ch("x")),
        ])
        XCTAssertEqual(a.button(for: KeyEvent(keyCode: 13, characters: "w")), .rcu(.up))
        XCTAssertEqual(a.button(for: KeyEvent(keyCode: 99, characters: "x")), .rcu(.back))
        XCTAssertEqual(a.button(for: KeyEvent(keyCode: 99, characters: "Y", modifiers: .shift)), .rcu(.back))
        XCTAssertNil(a.button(for: KeyEvent(keyCode: 99, characters: "q")))
    }

    func testRepeatOnlyForArrowsAndVolume() {
        XCTAssertEqual(arrows.button(for: KeyEvent(keyCode: KeyCode.up, characters: nil, isRepeat: true)), .rcu(.up))
        XCTAssertNil(arrows.button(for: KeyEvent(keyCode: 4, characters: "h", isRepeat: true)))
        XCTAssertEqual(arrows.button(for: KeyEvent(keyCode: 24, characters: "+", isRepeat: true)), .volumeUp)
        XCTAssertEqual(arrows.button(for: KeyEvent(keyCode: 4, characters: "h")), .rcu(.home))
    }

    func testConflictAcrossTriggerKinds() {
        // AZERTY: key code 14 gives "e".
        XCTAssertEqual(gaming.assigning(ch("e"), to: .rcu(.home), layout: azerty), .conflict(owner: .rcu(.ok)))
    }

    func testSharedButtonWinsOverActionWithTheSameKeystroke() {
        // After Reset keys or a profile, an action can be left holding a key of a shared button.
        let u = UUID(), v = UUID()
        var slots = KeyProfile.arrows.slots
        slots[.action(u)] = KeySlot(primary: ch("h"))
        slots[.mute] = KeySlot(primary: ch("n"), alternate: ch("j"))
        slots[.action(v)] = KeySlot(primary: ch("j"))
        let a = KeyAssignments(slots: slots)
        XCTAssertEqual(a.button(for: KeyEvent(keyCode: 4, characters: "h")), .rcu(.home))
        XCTAssertEqual(a.button(for: KeyEvent(keyCode: 38, characters: "j")), .mute)
        XCTAssertEqual(a.owner(of: ch("h"), layout: qwerty), .rcu(.home))
        var gamingSlots = KeyProfile.gaming.slots
        gamingSlots[.action(u)] = KeySlot(primary: ch("e"))
        XCTAssertEqual(KeyAssignments(slots: gamingSlots).button(for: KeyEvent(keyCode: 14, characters: "e")), .rcu(.ok))
    }

    func testConflictWithActionKey() {
        let u = UUID()
        var slots = KeyProfile.arrows.slots
        slots[.action(u)] = KeySlot(primary: KeyBinding(.character("1"), modifiers: .command))
        let a = KeyAssignments(slots: slots)
        let b = KeyBinding(.character("1"), modifiers: .command)
        XCTAssertEqual(a.assigning(b, to: .media(.stop), layout: qwerty), .conflict(owner: .action(u)))
    }

    func testAssignWithoutConflictAndUnchanged() {
        guard case .assigned(let a) = arrows.assigning(ch("j"), to: .media(.stop), layout: qwerty) else { return XCTFail() }
        XCTAssertEqual(a.slots[.media(.stop)]?.primary, ch("j"))
        XCTAssertEqual(arrows.assigning(ch("h"), to: .rcu(.home), layout: qwerty), .assigned(arrows))
    }

    func testSwapGivesOwnerTheOldKey() {
        guard case .conflict(let owner) = arrows.assigning(ch("h"), to: .rcu(.back), layout: qwerty) else { return XCTFail() }
        XCTAssertEqual(owner, .rcu(.home))
        let a = arrows.swapping(ch("h"), to: .rcu(.back), from: owner, layout: qwerty)
        XCTAssertEqual(a.slots[.rcu(.back)]?.primary, ch("h"))
        XCTAssertEqual(a.slots[.rcu(.home)]?.primary, pos(KeyCode.escape))
    }

    func testSwapWithoutOldKeyLeavesOwnerEmpty() {
        let a = arrows.swapping(ch("h"), to: .media(.stop), from: .rcu(.home), layout: qwerty)
        XCTAssertEqual(a.slots[.media(.stop)]?.primary, ch("h"))
        XCTAssertNil(a.slots[.rcu(.home)]?.primary)
    }

    func testRemovePrimaryKeepsAlternate() {
        let a = arrows.removingPrimary(of: .rcu(.ok))
        XCTAssertNil(a.slots[.rcu(.ok)]?.primary)
        XCTAssertEqual(a.slots[.rcu(.ok)]?.alternate, pos(KeyCode.keypadEnter))
        let b = arrows.removing(.alternate, of: .rcu(.ok))
        XCTAssertEqual(b.slots[.rcu(.ok)]?.primary, pos(KeyCode.returnKey))
        XCTAssertNil(b.slots[.rcu(.ok)]?.alternate)
    }

    func testAlternateAssignmentConflict() {
        XCTAssertEqual(gaming.assigning(pos(KeyCode.escape), to: .rcu(.home), role: .alternate, layout: qwerty),
                       .conflict(owner: .rcu(.back)))
        guard case .assigned(let a) = gaming.assigning(ch("j"), to: .rcu(.home), role: .alternate, layout: qwerty) else { return XCTFail() }
        XCTAssertEqual(a.slots[.rcu(.home)]?.alternate, ch("j"))
        XCTAssertEqual(a.slots[.rcu(.home)]?.primary, ch("h"))
    }

    func testSwapWhereOwnerHeldKeyAsAlternate() {
        let a = gaming.swapping(pos(KeyCode.up), to: .rcu(.home), from: .rcu(.up), layout: qwerty)
        XCTAssertEqual(a.slots[.rcu(.home)]?.primary, pos(KeyCode.up))
        XCTAssertEqual(a.slots[.rcu(.up)]?.alternate, ch("h"))
        XCTAssertEqual(a.slots[.rcu(.up)]?.primary, pos(13))
    }

    func testAssigningKeyHeldInOtherRoleMovesIt() {
        guard case .assigned(let a) = gaming.assigning(pos(KeyCode.up), to: .rcu(.up), role: .primary, layout: qwerty)
        else { return XCTFail() }
        XCTAssertEqual(a.slots[.rcu(.up)]?.primary, pos(KeyCode.up))
        XCTAssertNil(a.slots[.rcu(.up)]?.alternate)
        guard case .assigned(let b) = gaming.assigning(pos(13), to: .rcu(.up), role: .alternate, layout: qwerty)
        else { return XCTFail() }
        XCTAssertEqual(b.slots[.rcu(.up)]?.alternate, pos(13))
        XCTAssertNil(b.slots[.rcu(.up)]?.primary)
    }

    func testSwapAcrossTriggerKindsRemovesOwnersKey() {
        let a = gaming.swapping(ch("e"), to: .rcu(.home), from: .rcu(.ok), layout: azerty)
        XCTAssertEqual(a.slots[.rcu(.home)]?.primary, ch("e"))
        XCTAssertEqual(a.slots[.rcu(.ok)]?.primary, ch("h"))
        XCTAssertNil(a.owner(of: ch("e"), layout: azerty, except: .rcu(.home)))
    }
}
