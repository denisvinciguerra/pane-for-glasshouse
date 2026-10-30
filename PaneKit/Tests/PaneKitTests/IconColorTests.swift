import XCTest
@testable import PaneKit

final class IconColorTests: XCTestCase {
    private let black = IconColor(red: 0, green: 0, blue: 0)
    private let lightGrey = IconColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255)
    private let white = IconColor(red: 1, green: 1, blue: 1)

    func testEdgeIsTheColourNearTheCorner() {
        XCTAssertEqual(IconColor(edgeOf: Fixture.data("app-icon-red.png")), IconColor(red: 1, green: 0, blue: 0))
    }

    func testTransparentEdgeHasNoColour() {
        XCTAssertNil(IconColor(edgeOf: Fixture.data("app-icon-clear.png")))
    }

    func testDataThatIsNoImageHasNoColour() {
        XCTAssertNil(IconColor(edgeOf: Data("nope".utf8)))
    }

    func testIconSmallerThanTheCornerInsetIsRead() {
        XCTAssertEqual(IconColor(edgeOf: Fixture.data("app-icon-tiny.png")), IconColor(red: 1, green: 0, blue: 0))
    }

    func testColourCloseToTheBackgroundBlendsIntoIt() {
        XCTAssertTrue(black.blends(into: black))
        XCTAssertTrue(IconColor(red: 0.04, green: 0.06, blue: 0.12).blends(into: black))
        XCTAssertTrue(white.blends(into: lightGrey))
    }

    func testDistinctColourStandsOut() {
        XCTAssertFalse(IconColor(red: 1, green: 0, blue: 0).blends(into: black))
        XCTAssertFalse(IconColor(red: 0.04, green: 0.29, blue: 0.33).blends(into: black))
        XCTAssertFalse(IconColor(red: 0.04, green: 0.29, blue: 0.33).blends(into: lightGrey))
        XCTAssertFalse(white.blends(into: black))
    }
}
