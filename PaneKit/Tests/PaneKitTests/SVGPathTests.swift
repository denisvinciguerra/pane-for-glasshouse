import CoreGraphics
import XCTest
@testable import PaneKit

final class SVGPathTests: XCTestCase {
    /// The move, line and curve end points of a path, in order.
    private func points(_ path: CGPath) -> [CGPoint] {
        var result: [CGPoint] = []
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint, .addLineToPoint: result.append(e.points[0])
            case .addQuadCurveToPoint: result.append(e.points[1])
            case .addCurveToPoint: result.append(e.points[2])
            case .closeSubpath: break
            @unknown default: break
            }
        }
        return result
    }

    func testRelativeLinesRepeatImplicitly() throws {
        XCTAssertEqual(points(try SVGPath.path("M6 15l6-6 6 6")),
                       [CGPoint(x: 6, y: 15), CGPoint(x: 12, y: 9), CGPoint(x: 18, y: 15)])
    }
    func testHorizontalVerticalAndClose() throws {
        // Glasshouse's Home body, then a new subpath after Z restarts from its own M.
        let p = try SVGPath.path("M6 10v10h12V10")
        XCTAssertEqual(points(p), [CGPoint(x: 6, y: 10), CGPoint(x: 6, y: 20), CGPoint(x: 18, y: 20), CGPoint(x: 18, y: 10)])
        let q = try SVGPath.path("M5 9h3l5-4v14l-5-4H5z")
        XCTAssertEqual(q.boundingBoxOfPath, CGRect(x: 5, y: 5, width: 8, height: 14))
    }
    func testSeveralSubpaths() throws {
        XCTAssertEqual(try SVGPath.path("M17 9l4 6M21 9l-4 6").boundingBoxOfPath, CGRect(x: 17, y: 9, width: 4, height: 6))
    }
    func testNumbersWithoutSeparators() throws {
        XCTAssertEqual(points(try SVGPath.path("M.5,1.5L-2.25-3")), [CGPoint(x: 0.5, y: 1.5), CGPoint(x: -2.25, y: -3)])
        // Pointer's "-5.2.4": two numbers, -5.2 and .4.
        XCTAssertEqual(points(try SVGPath.path("M0 0l-5.2.4")), [CGPoint(x: 0, y: 0), CGPoint(x: -5.2, y: 0.4)])
    }
    func testArcSweepsTheRightWay() throws {
        // Back: a half circle of radius 6 bulging to the right, from (14, 9) to (14, 21).
        let back = try SVGPath.path("M4 9h10a6 6 0 0 1 0 12h-3").boundingBoxOfPath
        XCTAssertEqual(back.minX, 4, accuracy: 0.01); XCTAssertEqual(back.maxX, 20, accuracy: 0.05)
        XCTAssertEqual(back.minY, 9, accuracy: 0.01); XCTAssertEqual(back.maxY, 21, accuracy: 0.01)
        // Power: the large arc of radius 8, open at the top, its centre at (12, 11.91).
        let power = try SVGPath.path("M6.3 6.3a8 8 0 1 0 11.4 0").boundingBoxOfPath
        XCTAssertEqual(power.minX, 4, accuracy: 0.05); XCTAssertEqual(power.maxX, 20, accuracy: 0.05)
        XCTAssertEqual(power.maxY, 19.91, accuracy: 0.05); XCTAssertEqual(power.minY, 6.3, accuracy: 0.01)
    }
    func testUnknownCommandThrows() {
        XCTAssertThrowsError(try SVGPath.path("M0 0Q1 1 2 2")) { XCTAssertEqual($0 as? SVGPathError, .unsupported("Q")) }
    }
    func testMalformedPathsThrow() {
        for d in ["L1 1 2 2", "M0 0L1e999 1", "M0 0 L", "M0 0z 3 3"] {
            XCTAssertThrowsError(try SVGPath.path(d), d) { XCTAssertEqual($0 as? SVGPathError, .malformed, d) }
        }
    }
}
