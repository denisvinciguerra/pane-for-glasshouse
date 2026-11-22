import CoreGraphics
import XCTest
@testable import PaneKit

final class DpadRingTests: XCTestCase {
    let ring = DpadRing(diameter: 170)

    func testCentreAndAxes() {
        XCTAssertEqual(ring.part(at: CGPoint(x: 85, y: 85)), .ok)
        XCTAssertEqual(ring.part(at: CGPoint(x: 85, y: 5)), .up)
        XCTAssertEqual(ring.part(at: CGPoint(x: 85, y: 165)), .down)
        XCTAssertEqual(ring.part(at: CGPoint(x: 5, y: 85)), .left)
        XCTAssertEqual(ring.part(at: CGPoint(x: 165, y: 85)), .right)
    }

    func testCornersAreOutside() {
        // The bounding square's corners lie outside the circle.
        for p in [CGPoint(x: 3, y: 3), CGPoint(x: 167, y: 3), CGPoint(x: 3, y: 167), CGPoint(x: 167, y: 167),
                  CGPoint(x: 200, y: 85), CGPoint(x: 85, y: -1)] { XCTAssertNil(ring.part(at: p), "\(p)") }
    }

    func testOKBoundary() {
        XCTAssertEqual(ring.part(at: CGPoint(x: 85, y: 85 - 33)), .ok)
        XCTAssertEqual(ring.part(at: CGPoint(x: 85, y: 85 - 35)), .up)
        XCTAssertTrue(ring.path(.ok).contains(CGPoint(x: 85, y: 85)))
    }

    /// Just either side of each 45 degree diagonal, 30 pt across and 29 or 31 pt along from the
    /// centre: hit testing and the outlines agree on the part.
    func testEitherSideOfTheDiagonals() {
        let cases: [(CGPoint, RingPart)] = [
            (CGPoint(x: 85 + 30, y: 85 - 29), .right), (CGPoint(x: 85 + 30, y: 85 - 31), .up),
            (CGPoint(x: 85 - 30, y: 85 - 29), .left), (CGPoint(x: 85 - 30, y: 85 - 31), .up),
            (CGPoint(x: 85 + 30, y: 85 + 29), .right), (CGPoint(x: 85 + 30, y: 85 + 31), .down),
            (CGPoint(x: 85 - 30, y: 85 + 29), .left), (CGPoint(x: 85 - 30, y: 85 + 31), .down),
        ]
        for (point, part) in cases {
            XCTAssertEqual(ring.part(at: point), part, "\(point)")
            for other in RingPart.allCases {
                XCTAssertEqual(ring.path(other).contains(point), other == part, "\(other) at \(point)")
            }
        }
    }

    /// Every 5 pt over the square, skipping points within 1 pt of a boundary (a circle or a diagonal).
    private func gridPoints() -> [CGPoint] {
        var points: [CGPoint] = []
        for x in stride(from: 0.0, through: 170.0, by: 5.0) {
            for y in stride(from: 0.0, through: 170.0, by: 5.0) {
                let dx = x - 85, dy = y - 85
                let r = (dx * dx + dy * dy).squareRoot()
                if abs(r - ring.outerRadius) < 1 || abs(r - ring.okRadius) < 1 { continue }
                if abs(abs(dx) - abs(dy)) / 2.0.squareRoot() < 1 { continue }
                points.append(CGPoint(x: x, y: y))
            }
        }
        return points
    }

    func testPathsAgreeWithHitTesting() {
        for p in gridPoints() {
            let found = ring.part(at: p)
            if let found {
                XCTAssertTrue(ring.path(found).contains(p), "\(found) at \(p)")
            }
            for other in RingPart.allCases where other != found {
                XCTAssertFalse(ring.path(other).contains(p), "\(other) at \(p), expected \(String(describing: found))")
            }
        }
    }

    func testPartsDoNotOverlap() {
        for p in gridPoints() {
            let hits = RingPart.allCases.filter { ring.path($0).contains(p) }
            XCTAssertLessThanOrEqual(hits.count, 1, "\(hits) at \(p)")
        }
    }

    func testIconCentres() {
        XCTAssertEqual(ring.iconCenter(.ok), CGPoint(x: 85, y: 85))
        XCTAssertEqual(ring.iconCenter(.up), CGPoint(x: 85, y: 25.5))     // 85 - (34 + 85) / 2
        XCTAssertEqual(ring.iconCenter(.right), CGPoint(x: 144.5, y: 85))
    }

    func testPartsFollowTheirKey() {
        XCTAssertEqual(RingPart(arrow: .up), .up)
        XCTAssertEqual(RingPart(arrow: .down), .down)
        XCTAssertEqual(RingPart(arrow: .left), .left)
        XCTAssertEqual(RingPart(arrow: .right), .right)
        XCTAssertEqual(RingPart(arrow: .ok), .ok)
    }
}
