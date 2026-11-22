import CoreGraphics
import XCTest
@testable import PaneKit

final class KeyIconTests: XCTestCase {
    func testEveryIconParsesInsideItsGrid() {
        for icon in KeyIcon.allCases {
            // A single line has a zero-height box, so test for elements, not for an empty rect.
            XCTAssertFalse(icon.path.isEmpty, "\(icon)")
            let box = icon.path.boundingBoxOfPath
            XCTAssertGreaterThan(box.width + box.height, 0, "\(icon)")
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 24, height: 24).contains(box), "\(icon) \(box)")
        }
    }

    func testArrowsFollowTheirKey() {
        XCTAssertEqual(KeyIcon(arrow: .up), .up)
        XCTAssertEqual(KeyIcon(arrow: .down), .down)
        XCTAssertEqual(KeyIcon(arrow: .left), .left)
        XCTAssertEqual(KeyIcon(arrow: .right), .right)
    }

    func testMuteCrossIsSmallerThanGlasshouses() {
        // Pane's ✕ spans 4 × 4 at x 17…21, not Glasshouse's 4 × 6.
        XCTAssertEqual(KeyIcon.mute.path.boundingBoxOfPath, CGRect(x: 5, y: 5, width: 16, height: 14))
    }
}
