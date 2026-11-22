import CoreGraphics

/// One part of the ring d-pad: four quarter rings and the OK disc.
public enum RingPart: CaseIterable, Sendable {
    case up, left, right, down, ok

    /// The part for a directional key, or `.ok` for `RemoteKey.ok`.
    public init(arrow: RemoteKey) {
        switch arrow {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .ok: self = .ok
        default: preconditionFailure("\(arrow) is not a ring key")
        }
    }
}

/// The geometry of the ring d-pad, in a `diameter` x `diameter` square.
/// The origin is the top left and y points down (SwiftUI's convention).
public struct DpadRing: Sendable {
    public let diameter: CGFloat

    /// The OK disc's diameter as a fraction of the ring's.
    public static let okFraction: CGFloat = 0.4

    public init(diameter: CGFloat) { self.diameter = diameter }

    public var outerRadius: CGFloat { diameter / 2 }
    public var okRadius: CGFloat { diameter * Self.okFraction / 2 }

    private var center: CGPoint { CGPoint(x: outerRadius, y: outerRadius) }

    /// Start angle of each quarter, in degrees (atan2 angles, y down); each spans 90 degrees.
    private func startDegrees(_ part: RingPart) -> CGFloat {
        switch part {
        case .up: -135
        case .right: -45
        case .down: 45
        case .left: 135
        case .ok: 0
        }
    }

    /// The part's outline: the OK disc, or a quarter ring bounded by the 45 degree diagonals.
    public func path(_ part: RingPart) -> CGPath {
        let path = CGMutablePath()
        if part == .ok {
            path.addEllipse(in: CGRect(x: center.x - okRadius, y: center.y - okRadius,
                                       width: okRadius * 2, height: okRadius * 2))
            return path
        }
        let start = startDegrees(part) * .pi / 180
        let end = start + .pi / 2
        // Angles increase toward y down, which CGPath calls the non-clockwise direction here.
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: okRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    /// The part under `point`, or nil outside the outer circle.
    public func part(at point: CGPoint) -> RingPart? {
        let dx = point.x - center.x, dy = point.y - center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance > outerRadius { return nil }
        if distance <= okRadius { return .ok }
        let angle = atan2(dy, dx) * 180 / .pi
        if angle >= -135 && angle < -45 { return .up }
        if angle >= -45 && angle < 45 { return .right }
        if angle >= 45 && angle < 135 { return .down }
        return .left
    }

    /// Where a part's icon sits: the centre, or halfway across the ring on the part's axis.
    public func iconCenter(_ part: RingPart) -> CGPoint {
        let middle = (okRadius + outerRadius) / 2
        switch part {
        case .ok: return center
        case .up: return CGPoint(x: center.x, y: center.y - middle)
        case .down: return CGPoint(x: center.x, y: center.y + middle)
        case .left: return CGPoint(x: center.x - middle, y: center.y)
        case .right: return CGPoint(x: center.x + middle, y: center.y)
        }
    }
}
