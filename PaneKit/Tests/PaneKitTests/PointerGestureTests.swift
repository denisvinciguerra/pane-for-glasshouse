import XCTest
@testable import PaneKit

final class PointerGestureTests: XCTestCase {
    func testStoredGesture() {
        XCTAssertEqual(PointerMoveGesture(stored: nil), .drag)
        XCTAssertEqual(PointerMoveGesture(stored: "control"), .drag)
        XCTAssertEqual(PointerMoveGesture(stored: "option"), .option)
        XCTAssertEqual(PointerMoveGesture(stored: "drag"), .drag)
        XCTAssertEqual(PointerMoveGesture.defaultsKey, "pointerMoveGesture")
    }

    func testOptionAloneDoesNothing() {
        var g = PointerGesture(mode: .option)
        XCTAssertEqual(g.optionChanged(held: true), [])
        XCTAssertFalse(g.isDriving)
        XCTAssertEqual(g.optionChanged(held: false), [])
    }

    func testOptionMoveFreezesThenMoves() {
        var g = PointerGesture(mode: .option)
        XCTAssertEqual(g.moved(dx: 2, dy: -2, optionHeld: true, onPad: false), [.freeze(centreOnPad: true), .move(dx: 3, dy: -3)])
        XCTAssertTrue(g.isDriving)
        XCTAssertEqual(g.moved(dx: 1, dy: 0, optionHeld: true, onPad: false), [.move(dx: 1, dy: 0)])
        XCTAssertEqual(g.moved(dx: 1, dy: 0, optionHeld: true, onPad: false), [.move(dx: 2, dy: 0)]) // 0.5 carried
        XCTAssertEqual(g.optionChanged(held: false), [.thaw])
        XCTAssertFalse(g.isDriving)
    }

    func testOptionMoveOnPadDoesNotCentre() {
        var g = PointerGesture(mode: .option)
        XCTAssertEqual(g.moved(dx: 0.2, dy: 0, optionHeld: true, onPad: true), [.freeze(centreOnPad: false)])
    }

    func testMoveWithoutOptionDoesNothing() {
        var g = PointerGesture(mode: .option)
        XCTAssertEqual(g.moved(dx: 10, dy: 10, optionHeld: false, onPad: true), [])
    }

    func testMoveWithoutOptionWhileDrivingThaws() {
        var g = PointerGesture(mode: .option)
        _ = g.moved(dx: 2, dy: 0, optionHeld: true, onPad: true)
        XCTAssertEqual(g.moved(dx: 2, dy: 0, optionHeld: false, onPad: true), [.thaw])
        XCTAssertFalse(g.isDriving)
    }

    func testClickWhileDrivingKeepsDriving() {
        var g = PointerGesture(mode: .option)
        _ = g.moved(dx: 2, dy: 0, optionHeld: true, onPad: true)
        XCTAssertEqual(g.pressed(), [.click])
        XCTAssertEqual(g.dragged(dx: 2, dy: 0, optionHeld: true), [.move(dx: 3, dy: 0)])
        XCTAssertEqual(g.released(), [])
        XCTAssertTrue(g.isDriving)
    }

    func testOptionModeDragWithoutOptionIsIgnored() {
        var g = PointerGesture(mode: .option)
        XCTAssertEqual(g.pressed(), [.click])
        XCTAssertEqual(g.dragged(dx: 10, dy: 0, optionHeld: false), [])
        XCTAssertEqual(g.dragged(dx: 10, dy: 0, optionHeld: true), []) // never starts with a button held
        XCTAssertEqual(g.released(), [])
        XCTAssertFalse(g.isDriving)
    }

    func testOptionModeDragWithoutOptionWhileDrivingThaws() {
        var g = PointerGesture(mode: .option)
        _ = g.moved(dx: 2, dy: 0, optionHeld: true, onPad: true)
        _ = g.pressed()
        XCTAssertEqual(g.dragged(dx: 2, dy: 0, optionHeld: false), [.thaw])
        XCTAssertFalse(g.isDriving)
    }

    func testOptionModeReleaseWhileDrivingKeepsDriving() {
        var g = PointerGesture(mode: .option)
        _ = g.moved(dx: 2, dy: 0, optionHeld: true, onPad: true)
        XCTAssertEqual(g.released(), [])
        XCTAssertTrue(g.isDriving)
    }

    func testDragFreezesOnFirstMoveAndThawsOnRelease() {
        var g = PointerGesture(mode: .drag)
        XCTAssertEqual(g.pressed(), [])
        XCTAssertEqual(g.dragged(dx: 2, dy: 2, optionHeld: false), [.freeze(centreOnPad: false), .move(dx: 3, dy: 3)])
        XCTAssertEqual(g.dragged(dx: 2, dy: 0, optionHeld: false), [.move(dx: 3, dy: 0)])
        XCTAssertEqual(g.released(), [.thaw])
        XCTAssertFalse(g.isDriving)
    }

    func testDragShortPressClicks() {
        var g = PointerGesture(mode: .drag)
        _ = g.pressed()
        XCTAssertEqual(g.released(), [.click])
    }

    func testDragSubPixelStillClicks() {
        var g = PointerGesture(mode: .drag)
        _ = g.pressed()
        XCTAssertEqual(g.dragged(dx: 0.3, dy: 0.3, optionHeld: false), [])
        XCTAssertFalse(g.isDriving)
        XCTAssertEqual(g.released(), [.click])
    }

    func testDragMoveWithoutButtonWhileDrivingThaws() {
        var g = PointerGesture(mode: .drag)
        _ = g.pressed()
        _ = g.dragged(dx: 2, dy: 0, optionHeld: false)
        // The mouseUp was missed.
        XCTAssertEqual(g.moved(dx: 1, dy: 0, optionHeld: false, onPad: true), [.thaw])
        XCTAssertFalse(g.isDriving)
        XCTAssertEqual(g.released(), []) // the press was forgotten: no click
    }

    func testDragModeIgnoresOption() {
        var g = PointerGesture(mode: .drag)
        XCTAssertEqual(g.moved(dx: 10, dy: 0, optionHeld: true, onPad: false), [])
        XCTAssertEqual(g.optionChanged(held: true), [])
    }

    func testEndThawsWhileDriving() {
        var g = PointerGesture(mode: .drag)
        _ = g.pressed()
        _ = g.dragged(dx: 2, dy: 0, optionHeld: false)
        XCTAssertEqual(g.end(), [.thaw])
        XCTAssertEqual(g.end(), [])
        XCTAssertEqual(g.released(), []) // the press was forgotten: no click
    }
}
