import XCTest
@testable import PaneKit

final class ReorderGridTests: XCTestCase {
    /// Six 50 × 54 cells a row, 6 apart, rows 12 apart: 330 wide.
    private let grid = ReorderGrid(columns: 6, width: 330, cellHeight: 54, columnSpacing: 6, rowSpacing: 12)

    func testCellsShareTheWidth() {
        XCTAssertEqual(grid.cellWidth, 50)
        XCTAssertEqual(ReorderGrid(columns: 6, width: 0, cellHeight: 54, columnSpacing: 6, rowSpacing: 12).cellWidth, 0)
    }

    func testOriginsGoAcrossThenDown() {
        XCTAssertEqual(grid.origin(of: 0), CGPoint(x: 0, y: 0))
        XCTAssertEqual(grid.origin(of: 5), CGPoint(x: 280, y: 0))
        XCTAssertEqual(grid.origin(of: 6), CGPoint(x: 0, y: 66))
        XCTAssertEqual(grid.origin(of: 8), CGPoint(x: 112, y: 66))
    }

    func testHeightCountsTheRows() {
        XCTAssertEqual(grid.height(for: 0), 0)
        XCTAssertEqual(grid.height(for: 1), 54)
        XCTAssertEqual(grid.height(for: 6), 54)
        XCTAssertEqual(grid.height(for: 7), 120)
    }

    func testSlotNearestAPoint() {
        // Cell centres: x 25, 81, 137…; y 27, 93.
        XCTAssertEqual(grid.slot(nearest: CGPoint(x: 25, y: 27), count: 10), 0)
        XCTAssertEqual(grid.slot(nearest: CGPoint(x: 60, y: 20), count: 10), 1)
        XCTAssertEqual(grid.slot(nearest: CGPoint(x: 50, y: 20), count: 10), 0)
        XCTAssertEqual(grid.slot(nearest: CGPoint(x: 137, y: 95), count: 10), 8)
    }

    func testSlotStaysWithinTheItems() {
        XCTAssertEqual(grid.slot(nearest: CGPoint(x: -80, y: -80), count: 10), 0)
        XCTAssertEqual(grid.slot(nearest: CGPoint(x: 900, y: 10), count: 10), 5)
        // Past the last item, on its row or below: the last one.
        XCTAssertEqual(grid.slot(nearest: CGPoint(x: 300, y: 93), count: 10), 9)
        XCTAssertEqual(grid.slot(nearest: CGPoint(x: 25, y: 500), count: 10), 9)
        XCTAssertEqual(grid.slot(nearest: CGPoint(x: 25, y: 27), count: 0), 0)
    }

    func testMovingAnItem() {
        XCTAssertEqual(["a", "b", "c", "d"].moving(from: 0, to: 2), ["b", "c", "a", "d"])
        XCTAssertEqual(["a", "b", "c", "d"].moving(from: 3, to: 0), ["d", "a", "b", "c"])
        XCTAssertEqual(["a", "b", "c", "d"].moving(from: 1, to: 1), ["a", "b", "c", "d"])
        XCTAssertEqual(["a", "b"].moving(from: 5, to: 0), ["a", "b"])
        XCTAssertEqual(["a", "b"].moving(from: 0, to: 9), ["b", "a"])
    }
}
