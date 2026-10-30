import XCTest
@testable import PaneKit

final class KeyModeStateTests: XCTestCase {
    private var arrows: KeyAssignments { KeyAssignments(slots: KeyProfile.arrows.slots) }
    private func key(_ code: UInt16, _ chars: String?) -> KeyEvent { KeyEvent(keyCode: code, characters: chars) }
    private let esc = KeyEvent(keyCode: KeyCode.escape, characters: nil)

    private func send(_ s: inout KeyModeState, _ e: KeyEvent, _ a: KeyAssignments? = nil, text: Bool = false) -> KeyModeState.Effect {
        s.key(e, assignments: a ?? arrows, layout: qwerty, textInputActive: text)
    }

    func testIconTogglesShowing() {
        var s = KeyModeState()
        XCTAssertEqual(s.mode, .normal)
        XCTAssertFalse(s.showsTiles)
        s.iconClicked(option: false)
        XCTAssertEqual(s.mode, .showing)
        XCTAssertTrue(s.showsTiles)
        XCTAssertTrue(s.sendsCommands)
        s.iconClicked(option: false)
        XCTAssertEqual(s.mode, .normal)
    }

    func testOptionClickEntersEditingAndIconLeaves() {
        var s = KeyModeState()
        s.iconClicked(option: true)
        XCTAssertEqual(s.mode, .editing(awaiting: nil))
        XCTAssertFalse(s.sendsCommands)
        s.iconClicked(option: false)
        XCTAssertEqual(s.mode, .normal)
    }

    func testEditFromShowingThenEscapeLeaves() {
        var s = KeyModeState()
        s.iconClicked(option: false)
        s.editAll()
        XCTAssertEqual(s.mode, .editing(awaiting: nil))
        XCTAssertFalse(s.sendsCommands)
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .normal)
    }

    func testOptionHeldShowsTiles() {
        var s = KeyModeState()
        s.optionChanged(down: true)
        XCTAssertTrue(s.showsTiles)
        XCTAssertEqual(s.mode, .normal)
        s.optionChanged(down: false)
        XCTAssertFalse(s.showsTiles)
    }

    func testClicksInEditingSelectInsteadOfFiring() {
        var s = KeyModeState()
        s.iconClicked(option: true)
        XCTAssertEqual(s.buttonClicked(.rcu(.back)), .none)
        XCTAssertEqual(s.mode, .editing(awaiting: .rcu(.back)))
        XCTAssertFalse(s.sendsCommands)
    }

    func testClickFiresInNormalAndShowing() {
        var s = KeyModeState()
        XCTAssertEqual(s.buttonClicked(.mute), .fire(.mute))
        s.iconClicked(option: false)
        XCTAssertEqual(s.buttonClicked(.mute), .fire(.mute))
    }

    func testEditingAssignsThenWaitsForNextClick() {
        var s = KeyModeState()
        s.iconClicked(option: true)
        _ = s.buttonClicked(.mute)
        let k = KeyBinding(.character("j"))
        XCTAssertEqual(send(&s, key(38, "j")), .assign(k, to: .mute))
        XCTAssertEqual(s.mode, .editing(awaiting: nil))
        XCTAssertEqual(send(&s, key(38, "j")), .none)
    }

    func testUnrecordableKeyIsIgnoredWhileWaiting() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        XCTAssertEqual(send(&s, KeyEvent(keyCode: 55, characters: nil)), .none)
        XCTAssertEqual(s.mode, .capturing(.mute))
    }

    func testCaptureAssignsOnceThenNormal() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        XCTAssertEqual(s.mode, .capturing(.mute))
        XCTAssertEqual(send(&s, key(38, "j")), .assign(KeyBinding(.character("j")), to: .mute))
        XCTAssertEqual(s.mode, .normal)
    }

    func testOwnPrimaryIsNotAConflict() {
        var s = KeyModeState()
        s.setKey(for: .rcu(.home))
        XCTAssertEqual(send(&s, key(4, "h")), .assign(KeyBinding(.character("h")), to: .rcu(.home)))
        XCTAssertNil(s.conflict)
    }

    func testConflictThenSwap() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        XCTAssertEqual(send(&s, key(4, "h")), .none)
        let k = KeyBinding(.character("h"))
        XCTAssertEqual(s.conflict, KeyConflict(binding: k, target: .mute, owner: .rcu(.home)))
        XCTAssertEqual(send(&s, key(38, "j")), .none)   // ignored while a conflict waits
        XCTAssertEqual(s.resolveConflict(swap: true), .swap(k, to: .mute, from: .rcu(.home)))
        XCTAssertNil(s.conflict)
        XCTAssertEqual(s.mode, .normal)
    }

    func testConflictThenSwapInEditingWaitsForNextClick() {
        var s = KeyModeState()
        s.iconClicked(option: true)
        _ = s.buttonClicked(.mute)
        _ = send(&s, key(4, "h"))
        _ = s.resolveConflict(swap: true)
        XCTAssertEqual(s.mode, .editing(awaiting: nil))
    }

    func testConflictThenCancelKeepsWaiting() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        _ = send(&s, key(4, "h"))
        XCTAssertEqual(s.resolveConflict(swap: false), .none)
        XCTAssertNil(s.conflict)
        XCTAssertEqual(s.mode, .capturing(.mute))
    }

    func testResolveWithoutConflictDoesNothing() {
        var s = KeyModeState()
        XCTAssertEqual(s.resolveConflict(swap: true), .none)
    }

    func testEscapeAbandonsPendingConflictFirst() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        _ = send(&s, key(4, "h"))
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertNil(s.conflict)
        XCTAssertEqual(s.mode, .capturing(.mute))
    }

    func testEscapeLeavesEditingAndCapture() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .normal)
        s.iconClicked(option: true)
        _ = s.buttonClicked(.mute)
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .normal)
        s.iconClicked(option: true)
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .normal)
    }

    func testEscapeFiresBackInNormalMode() {
        var s = KeyModeState()
        XCTAssertEqual(send(&s, esc), .fire(.rcu(.back)))
        s.iconClicked(option: false)
        XCTAssertEqual(send(&s, esc), .fire(.rcu(.back)))
        XCTAssertEqual(s.mode, .showing)
    }

    func testTypingInTextFieldPasses() {
        var s = KeyModeState()
        XCTAssertEqual(send(&s, key(4, "h"), text: true), .pass)
    }

    func testUnboundKeyPasses() {
        var s = KeyModeState()
        XCTAssertEqual(send(&s, key(6, "z")), .pass)
        XCTAssertEqual(send(&s, key(4, "h")), .fire(.rcu(.home)))
    }

    private func held(_ e: KeyEvent) -> KeyEvent {
        KeyEvent(keyCode: e.keyCode, characters: e.characters, modifiers: e.modifiers, isRepeat: true)
    }

    func testHeldKeyAfterCaptureSendsNothing() {
        var s = KeyModeState()
        s.setKey(for: .rcu(.up))
        let up = key(KeyCode.up, nil)
        XCTAssertEqual(send(&s, up), .assign(KeyBinding(.keyCode(KeyCode.up)), to: .rcu(.up)))
        XCTAssertEqual(s.mode, .normal)
        XCTAssertEqual(send(&s, held(up)), .none)
        XCTAssertEqual(send(&s, held(up)), .none)
    }

    func testHeldEscapeAfterLeavingCaptureSendsNothing() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .normal)
        XCTAssertEqual(send(&s, held(esc)), .none)
    }

    func testRepeatsAreSwallowedWhileSettingKeys() {
        var s = KeyModeState()
        s.iconClicked(option: true)
        _ = s.buttonClicked(.mute)
        XCTAssertEqual(send(&s, held(key(38, "j"))), .none)
        XCTAssertEqual(s.mode, .editing(awaiting: .mute))
        XCTAssertEqual(send(&s, held(esc)), .none)
        XCTAssertEqual(s.mode, .editing(awaiting: .mute))
    }

    func testHeldKeyThatDoesNotRepeatIsSwallowed() {
        var s = KeyModeState()
        XCTAssertEqual(send(&s, key(4, "h")), .fire(.rcu(.home)))
        XCTAssertEqual(send(&s, held(key(4, "h"))), .none)
        XCTAssertEqual(send(&s, esc), .fire(.rcu(.back)))
        XCTAssertEqual(send(&s, held(esc)), .none)
        // Held from before the popover had the keys: still a bound key, swallowed.
        var t = KeyModeState()
        XCTAssertEqual(send(&t, held(esc)), .none)
        XCTAssertEqual(send(&t, held(key(4, "h"))), .none)
    }

    func testHeldArrowAfterFiringRepeats() {
        var s = KeyModeState()
        let up = key(KeyCode.up, nil)
        XCTAssertEqual(send(&s, up), .fire(.rcu(.up)))
        XCTAssertEqual(send(&s, held(up)), .fire(.rcu(.up)))
        XCTAssertEqual(send(&s, held(up)), .fire(.rcu(.up)))
    }

    func testHeldKeyInTextFieldPasses() {
        var s = KeyModeState()
        XCTAssertEqual(send(&s, key(4, "h"), text: true), .pass)
        XCTAssertEqual(send(&s, held(key(4, "h")), text: true), .pass)
        XCTAssertEqual(send(&s, held(key(KeyCode.up, nil)), text: true), .pass)
    }

    func testHeldUnboundKeyPasses() {
        var s = KeyModeState()
        XCTAssertEqual(send(&s, key(6, "z")), .pass)
        XCTAssertEqual(send(&s, held(key(6, "z"))), .pass)
    }

    func testClosedResetsEverything() {
        var s = KeyModeState()
        s.optionChanged(down: true)
        s.setKey(for: .mute)
        _ = send(&s, key(4, "h"))
        s.closed()
        XCTAssertEqual(s, KeyModeState())
    }

    func testDoneLeavesEditingAndCaptureWithWhatWaits() {
        var s = KeyModeState()
        s.iconClicked(option: true)
        _ = s.buttonClicked(.mute)
        _ = send(&s, key(4, "h"))
        XCTAssertNotNil(s.conflict)
        s.done()
        XCTAssertEqual(s.mode, .normal)
        XCTAssertNil(s.conflict)
        s.setKey(for: .mute)
        s.askToReplace(.remove(.mute))
        s.done()
        XCTAssertEqual(s.mode, .normal)
        XCTAssertNil(s.replacing)
    }

    // MARK: Replacing Custom

    func testReplaceGivesBackTheChange() {
        var s = KeyModeState()
        s.iconClicked(option: true)
        _ = s.buttonClicked(.mute)
        let k = KeyBinding(.character("j"))
        XCTAssertEqual(send(&s, key(38, "j")), .assign(k, to: .mute))
        s.askToReplace(.assign(k, to: .mute))
        XCTAssertEqual(s.replacing, .assign(k, to: .mute))
        XCTAssertEqual(s.resolveReplacement(replace: true), .assign(k, to: .mute))
        XCTAssertNil(s.replacing)
        XCTAssertEqual(s.mode, .editing(awaiting: nil))
    }

    func testCancelDropsTheChange() {
        var s = KeyModeState()
        s.askToReplace(.remove(.mute))
        XCTAssertEqual(s.resolveReplacement(replace: false), .none)
        XCTAssertNil(s.replacing)
        XCTAssertEqual(s.resolveReplacement(replace: true), .none)
    }

    func testKeysWaitWhileAskingAndEscapeCancels() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        _ = send(&s, key(38, "j"))
        s.askToReplace(.assign(KeyBinding(.character("j")), to: .mute))
        XCTAssertEqual(send(&s, key(4, "h")), .none, "Home is not pressed while asking")
        XCTAssertEqual(send(&s, esc), .none, "Esc is not Back while asking")
        XCTAssertNil(s.replacing)
        XCTAssertEqual(send(&s, esc), .fire(.rcu(.back)))
    }

    func testRepeatsAreSwallowedWhileAsking() {
        var s = KeyModeState()
        XCTAssertEqual(send(&s, key(KeyCode.up, nil)), .fire(.rcu(.up)))
        s.askToReplace(.remove(.mute))
        XCTAssertEqual(send(&s, KeyEvent(keyCode: KeyCode.up, characters: nil, isRepeat: true)), .none)
    }

    func testAClickOrTheIconDropsTheQuestion() {
        var s = KeyModeState()
        s.askToReplace(.remove(.mute))
        XCTAssertEqual(s.buttonClicked(.mute), .fire(.mute))
        XCTAssertNil(s.replacing)
        s.askToReplace(.remove(.mute))
        s.iconClicked(option: false)
        XCTAssertNil(s.replacing)
        s.askToReplace(.remove(.mute))
        s.setKey(for: .mute)
        XCTAssertNil(s.replacing)
    }
}
