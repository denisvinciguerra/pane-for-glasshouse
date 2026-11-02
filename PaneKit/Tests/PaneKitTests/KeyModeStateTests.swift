import XCTest
@testable import PaneKit

final class KeyModeStateTests: XCTestCase {
    private var arrows: KeyAssignments { KeyAssignments(slots: KeyProfile.arrows.slots) }
    private func key(_ code: UInt16, _ chars: String?) -> KeyEvent { KeyEvent(keyCode: code, characters: chars) }
    private let esc = KeyEvent(keyCode: KeyCode.escape, characters: nil)

    private func send(_ s: inout KeyModeState, _ e: KeyEvent, _ a: KeyAssignments? = nil, text: Bool = false,
                      globals: KeyAssignments = KeyAssignments(slots: [:])) -> KeyModeState.Effect {
        s.key(e, assignments: a ?? arrows, globalAssignments: globals, layout: qwerty, textInputActive: text)
    }

    func testIconTogglesShowing() {
        var s = KeyModeState()
        XCTAssertEqual(s.mode, .normal)
        XCTAssertFalse(s.showsTiles)
        XCTAssertNil(s.selected)
        s.iconClicked()
        XCTAssertEqual(s.mode, .showing(selected: nil))
        XCTAssertTrue(s.showsTiles)
        XCTAssertFalse(s.sendsCommands, "keys shown send nothing")
        s.iconClicked()
        XCTAssertEqual(s.mode, .normal)
        XCTAssertTrue(s.sendsCommands)
    }

    func testIconLeavesAnyModeForNormalAndDropsWhatWaits() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        _ = send(&s, key(4, "h"))
        XCTAssertNotNil(s.conflict)
        s.iconClicked()
        XCTAssertEqual(s.mode, .normal)
        XCTAssertNil(s.conflict)
        s.setGlobal(for: .mute)
        _ = send(&s, key(35, "p"))
        XCTAssertNotNil(s.globalNotice)
        s.iconClicked()
        XCTAssertEqual(s.mode, .normal)
        XCTAssertNil(s.globalNotice)
        s.select(.mute)
        s.askToReplace(.remove(.mute))
        s.iconClicked()
        XCTAssertEqual(s.mode, .normal)
        XCTAssertNil(s.replacing)
    }

    func testSelectChoosesAButtonAndDropsWhatWaits() {
        var s = KeyModeState()
        s.select(.mute)
        XCTAssertEqual(s.mode, .showing(selected: .mute))
        XCTAssertEqual(s.selected, .mute)
        XCTAssertTrue(s.showsTiles)
        s.setKey(for: .mute)
        _ = send(&s, key(4, "h"))
        XCTAssertNotNil(s.conflict)
        s.select(.volumeUp)
        XCTAssertEqual(s.mode, .showing(selected: .volumeUp))
        XCTAssertNil(s.conflict)
        s.setGlobal(for: .mute)
        _ = send(&s, key(35, "p"))
        s.select(.mute)
        XCTAssertEqual(s.mode, .showing(selected: .mute), "a capture in progress is abandoned")
        XCTAssertNil(s.globalNotice)
    }

    func testSelectedFollowsTheMode() {
        var s = KeyModeState()
        XCTAssertNil(s.selected)
        s.iconClicked()
        XCTAssertNil(s.selected)
        s.setKey(for: .mute)
        XCTAssertEqual(s.selected, .mute)
        s.setGlobal(for: .volumeUp)
        XCTAssertEqual(s.selected, .volumeUp)
    }

    func testKeysShownSendNothingAndSwallowEveryKey() {
        var s = KeyModeState()
        s.iconClicked()
        XCTAssertEqual(send(&s, key(4, "h")), .none)
        XCTAssertEqual(send(&s, held(key(4, "h"))), .none)
        XCTAssertEqual(send(&s, key(6, "z")), .none)
        XCTAssertEqual(send(&s, key(4, "h"), text: true), .none)
        XCTAssertEqual(send(&s, held(key(KeyCode.up, nil))), .none)
        XCTAssertEqual(s.mode, .showing(selected: nil))
    }

    func testEscapeLeavesKeysShownWithoutSendingBack() {
        var s = KeyModeState()
        s.select(.mute)
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .showing(selected: nil))
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .normal)
        XCTAssertEqual(send(&s, held(esc)), .none)
        // With a modifier, Esc is just another swallowed key.
        s.iconClicked()
        XCTAssertEqual(send(&s, KeyEvent(keyCode: KeyCode.escape, characters: nil, modifiers: [.command])), .none)
        XCTAssertEqual(s.mode, .showing(selected: nil))
    }

    func testOptionHeldShowsTiles() {
        var s = KeyModeState()
        s.optionChanged(down: true)
        XCTAssertTrue(s.showsTiles)
        XCTAssertEqual(s.mode, .normal)
        s.optionChanged(down: false)
        XCTAssertFalse(s.showsTiles)
    }

    func testClickFiresInNormalAndSelectsWhenKeysAreShown() {
        var s = KeyModeState()
        XCTAssertEqual(s.buttonClicked(.mute), .fire(.mute))
        XCTAssertEqual(s.mode, .normal)
        s.iconClicked()
        XCTAssertEqual(s.buttonClicked(.mute), .none)
        XCTAssertEqual(s.mode, .showing(selected: .mute))
        XCTAssertEqual(s.buttonClicked(.volumeUp), .none)
        XCTAssertEqual(s.mode, .showing(selected: .volumeUp))
    }

    func testUnrecordableKeyIsIgnoredWhileWaiting() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        XCTAssertEqual(send(&s, KeyEvent(keyCode: 55, characters: nil)), .none)
        XCTAssertEqual(s.mode, .capturing(.mute))
    }

    func testCaptureAssignsOnceThenBackToKeysShown() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        XCTAssertEqual(s.mode, .capturing(.mute))
        XCTAssertEqual(send(&s, key(38, "j")), .assign(KeyBinding(.character("j")), to: .mute))
        XCTAssertEqual(s.mode, .showing(selected: .mute))
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
        XCTAssertEqual(s.mode, .showing(selected: .mute))
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

    func testEscapeLeavesCaptureForKeysShown() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .showing(selected: .mute))
    }

    func testClickingAnotherButtonDuringCaptureSelectsIt() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        _ = send(&s, key(4, "h"))
        XCTAssertEqual(s.buttonClicked(.volumeUp), .none)
        XCTAssertEqual(s.mode, .showing(selected: .volumeUp))
        XCTAssertNil(s.conflict)
    }

    func testEscapeFiresBackInNormalModeOnly() {
        var s = KeyModeState()
        XCTAssertEqual(send(&s, esc), .fire(.rcu(.back)))
        s.iconClicked()
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .normal)
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
        XCTAssertEqual(s.mode, .showing(selected: .rcu(.up)))
        XCTAssertEqual(send(&s, held(up)), .none)
        XCTAssertEqual(send(&s, held(up)), .none)
    }

    func testHeldEscapeAfterLeavingCaptureSendsNothing() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .showing(selected: .mute))
        XCTAssertEqual(send(&s, held(esc)), .none)
    }

    func testRepeatsAreSwallowedWhileSettingKeys() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        XCTAssertEqual(send(&s, held(key(38, "j"))), .none)
        XCTAssertEqual(s.mode, .capturing(.mute))
        XCTAssertEqual(send(&s, held(esc)), .none)
        XCTAssertEqual(s.mode, .capturing(.mute))
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

    func testDoneLeavesCaptureForKeysShownWithWhatWaits() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        _ = send(&s, key(4, "h"))
        XCTAssertNotNil(s.conflict)
        s.done()
        XCTAssertEqual(s.mode, .showing(selected: .mute))
        XCTAssertNil(s.conflict)
        s.setKey(for: .mute)
        s.askToReplace(.remove(.mute))
        s.done()
        XCTAssertEqual(s.mode, .showing(selected: .mute))
        XCTAssertNil(s.replacing)
    }

    // MARK: Back one level

    func testEscapeClimbsOneLevelAtATime() {
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .showing(selected: .mute), "waiting -> bar open")
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .showing(selected: nil), "bar open -> keys shown")
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .normal, "keys shown -> normal")
        XCTAssertEqual(send(&s, esc), .fire(.rcu(.back)), "normal: Back")
    }

    func testClickingTheChosenButtonAgainClosesItsBar() {
        var s = KeyModeState()
        s.iconClicked()
        XCTAssertEqual(s.buttonClicked(.mute), .none)
        XCTAssertEqual(s.selected, .mute)
        XCTAssertEqual(s.buttonClicked(.mute), .none)
        XCTAssertNil(s.selected)
        XCTAssertEqual(s.mode, .showing(selected: nil))
        XCTAssertEqual(s.buttonClicked(.mute), .none, "a third click chooses it again")
        XCTAssertEqual(s.selected, .mute)
    }

    func testClickingTheButtonThatWaitsClosesItsBar() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        _ = send(&s, key(4, "h"))
        XCTAssertEqual(s.buttonClicked(.mute), .none)
        XCTAssertEqual(s.mode, .showing(selected: nil))
        XCTAssertNil(s.conflict)
        s.setGlobal(for: .mute)
        XCTAssertEqual(s.buttonClicked(.mute), .none)
        XCTAssertEqual(s.mode, .showing(selected: nil))
    }

    func testDeselectClosesTheBarAndDropsWhatWaits() {
        var s = KeyModeState()
        s.select(.mute)
        s.deselect()
        XCTAssertEqual(s.mode, .showing(selected: nil))
        s.setKey(for: .mute)
        s.askToReplace(.remove(.mute))
        s.deselect()
        XCTAssertEqual(s.mode, .showing(selected: nil))
        XCTAssertNil(s.replacing)
        s.setGlobal(for: .mute)
        _ = send(&s, key(pCode, "p"))
        XCTAssertNotNil(s.globalNotice)
        s.deselect()
        XCTAssertNil(s.globalNotice)
        s.setKey(for: .mute)
        _ = send(&s, key(4, "h"))
        XCTAssertNotNil(s.conflict)
        s.deselect()
        XCTAssertNil(s.conflict)
        XCTAssertEqual(s.mode, .showing(selected: nil))
    }

    func testDeselectDoesNothingInNormal() {
        var s = KeyModeState()
        s.deselect()
        XCTAssertEqual(s, KeyModeState())
    }

    // MARK: Replacing Custom

    func testReplaceGivesBackTheChange() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        let k = KeyBinding(.character("j"))
        XCTAssertEqual(send(&s, key(38, "j")), .assign(k, to: .mute))
        s.askToReplace(.assign(k, to: .mute))
        XCTAssertEqual(s.replacing, .assign(k, to: .mute))
        XCTAssertEqual(s.resolveReplacement(replace: true), .assign(k, to: .mute))
        XCTAssertNil(s.replacing)
        XCTAssertEqual(s.mode, .showing(selected: .mute), "keys stay shown after the change")
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
        XCTAssertEqual(s.mode, .showing(selected: .mute), "Esc only cancelled the question")
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .showing(selected: nil))
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .normal)
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
        s.iconClicked()
        XCTAssertNil(s.replacing)
        s.askToReplace(.remove(.mute))
        s.setKey(for: .mute)
        XCTAssertNil(s.replacing)
    }

    // MARK: Global shortcuts

    private func cmd(_ code: UInt16, _ chars: String? = nil) -> KeyEvent {
        KeyEvent(keyCode: code, characters: chars, modifiers: [.command])
    }
    private let pCode: UInt16 = 35
    private func global(_ code: UInt16, _ mods: KeyModifiers = [.command]) -> KeyBinding {
        KeyBinding(.keyCode(code), modifiers: mods)
    }

    func testOptionClickOnTheIconDoesNotEditAnymore() {
        var s = KeyModeState()
        s.optionChanged(down: true)
        s.iconClicked()
        XCTAssertEqual(s.mode, .showing(selected: nil))
        XCTAssertFalse(s.sendsCommands)
        XCTAssertEqual(s.buttonClicked(.mute), .none)
        XCTAssertEqual(s.mode, .showing(selected: .mute))
    }

    func testSetGlobalWaitsWithoutSendingCommands() {
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        XCTAssertEqual(s.mode, .capturingGlobal(.mute))
        XCTAssertFalse(s.sendsCommands)
        XCTAssertTrue(s.showsTiles)
    }

    func testCommandPRecordsAGlobalShortcutAndWaitsForTheCaller() {
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        XCTAssertEqual(send(&s, cmd(pCode, "p")), .assignGlobal(global(pCode), to: .mute))
        XCTAssertEqual(s.mode, .capturingGlobal(.mute), "the caller confirms with globalRecorded()")
        s.globalRecorded()
        XCTAssertEqual(s.mode, .showing(selected: .mute))
        XCTAssertNil(s.globalNotice)
    }

    func testBareKeyAndShiftOnlyNeedAModifier() {
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        XCTAssertEqual(send(&s, key(pCode, "p")), .none)
        XCTAssertEqual(s.globalNotice, .needsModifier(KeyBinding(.keyCode(pCode))))
        XCTAssertEqual(send(&s, KeyEvent(keyCode: pCode, characters: "P", modifiers: [.shift])), .none)
        XCTAssertEqual(s.globalNotice, .needsModifier(KeyBinding(.keyCode(pCode), modifiers: [.shift])))
        XCTAssertEqual(s.mode, .capturingGlobal(.mute))
    }

    func testTheNoticeGoesAtTheNextKeyAndWithTheCapture() {
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        _ = send(&s, key(pCode, "p"))
        XCTAssertEqual(send(&s, KeyEvent(keyCode: 55, characters: nil)), .none)   // a modifier alone
        XCTAssertNil(s.globalNotice)
        _ = send(&s, key(pCode, "p"))
        s.setGlobal(for: .mute)
        XCTAssertNil(s.globalNotice)
        _ = send(&s, key(pCode, "p"))
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .showing(selected: .mute))
        XCTAssertNil(s.globalNotice)
    }

    func testEscapeLeavesTheGlobalCaptureForKeysShown() {
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        XCTAssertEqual(send(&s, esc), .none)
        XCTAssertEqual(s.mode, .showing(selected: .mute))
    }

    func testDeleteAloneRemovesTheGlobalShortcutAndKeepsKeysShown() {
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        XCTAssertEqual(send(&s, key(51, nil)), .removeGlobal(.mute))
        XCTAssertEqual(s.mode, .showing(selected: .mute))
    }

    func testAnotherButtonsCombinationIsAGlobalConflictThenSwap() {
        let globals = KeyAssignments(slots: [.volumeUp: KeySlot(primary: global(pCode))])
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        XCTAssertEqual(send(&s, cmd(pCode, "p"), globals: globals), .none)
        XCTAssertEqual(s.conflict, KeyConflict(binding: global(pCode), target: .mute, owner: .volumeUp, global: true))
        XCTAssertEqual(send(&s, cmd(38, "j"), globals: globals), .none, "ignored while a conflict waits")
        XCTAssertEqual(s.resolveConflict(swap: true), .swapGlobal(global(pCode), to: .mute, from: .volumeUp))
        XCTAssertEqual(s.mode, .showing(selected: .mute))
        XCTAssertNil(s.conflict)
    }

    func testGlobalConflictCancelKeepsWaitingAndEscapeClearsItFirst() {
        let globals = KeyAssignments(slots: [.volumeUp: KeySlot(primary: global(pCode))])
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        _ = send(&s, cmd(pCode, "p"), globals: globals)
        XCTAssertEqual(s.resolveConflict(swap: false), .none)
        XCTAssertEqual(s.mode, .capturingGlobal(.mute))
        _ = send(&s, cmd(pCode, "p"), globals: globals)
        XCTAssertEqual(send(&s, esc, globals: globals), .none)
        XCTAssertNil(s.conflict)
        XCTAssertEqual(s.mode, .capturingGlobal(.mute))
    }

    func testAPopoverKeyConflictIsNotGlobal() {
        var s = KeyModeState()
        s.setKey(for: .mute)
        _ = send(&s, key(4, "h"))
        XCTAssertEqual(s.conflict?.global, false)
    }

    func testAnotherAppHoldingTheCombinationKeepsTheCaptureWaiting() {
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        XCTAssertEqual(send(&s, cmd(pCode, "p")), .assignGlobal(global(pCode), to: .mute))
        s.globalTaken(global(pCode))
        XCTAssertEqual(s.globalNotice, .takenByAnotherApp(global(pCode)))
        XCTAssertEqual(s.mode, .capturingGlobal(.mute))
        XCTAssertEqual(send(&s, cmd(38, "j")), .assignGlobal(global(38), to: .mute))
        XCTAssertNil(s.globalNotice)
    }

    func testRepeatsSendNothingDuringTheGlobalCapture() {
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        XCTAssertEqual(send(&s, held(cmd(pCode, "p"))), .none)
        XCTAssertEqual(send(&s, held(key(51, nil))), .none)
        XCTAssertEqual(send(&s, held(esc)), .none)
        XCTAssertEqual(s.mode, .capturingGlobal(.mute))
    }

    func testHeldKeyAfterTheGlobalCaptureSendsNothing() {
        var s = KeyModeState()
        s.setGlobal(for: .rcu(.up))
        XCTAssertEqual(send(&s, cmd(KeyCode.up)), .assignGlobal(global(KeyCode.up), to: .rcu(.up)))
        s.globalRecorded()
        XCTAssertEqual(send(&s, held(cmd(KeyCode.up))), .none)
    }

    func testClickingAnotherButtonAbandonsTheGlobalCapture() {
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        _ = send(&s, key(pCode, "p"))
        XCTAssertEqual(s.buttonClicked(.volumeUp), .none)
        XCTAssertEqual(s.mode, .showing(selected: .volumeUp), "the capture is abandoned, the button chosen")
        XCTAssertNil(s.globalNotice)
    }

    func testClosedAndDoneEndTheGlobalCapture() {
        var s = KeyModeState()
        s.setGlobal(for: .mute)
        _ = send(&s, key(pCode, "p"))
        s.done()
        XCTAssertEqual(s.mode, .showing(selected: .mute))
        XCTAssertNil(s.globalNotice)
        s.setGlobal(for: .mute)
        s.closed()
        XCTAssertEqual(s, KeyModeState())
    }
}
