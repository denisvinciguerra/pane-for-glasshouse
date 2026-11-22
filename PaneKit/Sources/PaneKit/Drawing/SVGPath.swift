import CoreGraphics
import Foundation

public enum SVGPathError: Error, Equatable {
    case unsupported(Character)
    case malformed
}

/// Reads SVG path data (M, L, H, V, A, Z, absolute and relative) into a `CGPath`.
public enum SVGPath {
    public static func path(_ d: String) throws -> CGPath {
        var scanner = Scanner(Array(d))
        let path = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var command: Character?

        // Path data must open with a moveto.
        scanner.skipSeparators()
        guard let first = scanner.peekLetter(), first == "M" || first == "m" else {
            if scanner.atEnd { return path }
            throw SVGPathError.malformed
        }

        while true {
            scanner.skipSeparators()
            if scanner.atEnd { break }
            if let c = scanner.peekLetter() {
                scanner.advance()
                guard "MLHVAZmlhvaz".contains(c) else { throw SVGPathError.unsupported(c) }
                command = c
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    current = start
                    command = nil
                    continue
                }
            } else if command == nil {
                throw SVGPathError.malformed
            }
            guard let c = command else { throw SVGPathError.malformed }
            let relative = c.isLowercase
            let base = relative ? current : .zero

            switch c.uppercased() {
            case "M":
                let p = CGPoint(x: try scanner.number() + base.x, y: try scanner.number() + base.y)
                path.move(to: p)
                current = p; start = p
                command = relative ? "l" : "L"  // further pairs are implicit lines
            case "L":
                let p = CGPoint(x: try scanner.number() + base.x, y: try scanner.number() + base.y)
                path.addLine(to: p)
                current = p
            case "H":
                let p = CGPoint(x: try scanner.number() + base.x, y: current.y)
                path.addLine(to: p)
                current = p
            case "V":
                let p = CGPoint(x: current.x, y: try scanner.number() + base.y)
                path.addLine(to: p)
                current = p
            default:  // "A"
                let rx = try scanner.number(), ry = try scanner.number()
                let rotation = try scanner.number()
                let large = try scanner.flag(), sweep = try scanner.flag()
                let end = CGPoint(x: try scanner.number() + base.x, y: try scanner.number() + base.y)
                addArc(to: path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = end
            }
        }
        return path
    }

    /// SVG 1.1 implementation notes F.6.5: endpoint to centre parameterization, then cubic Béziers.
    private static func addArc(to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint,
                               rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        // Step 1: (x1', y1').
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        // Scale the radii up if they cannot span the two points.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { let s = lambda.squareRoot(); rx *= s; ry *= s }
        // Step 2: (cx', cy').
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den == 0 ? 0 : (max(0, num / den)).squareRoot()
        if large == sweep { coef = -coef }
        let cxp = coef * rx * y1 / ry
        let cyp = -coef * ry * x1 / rx
        // Step 3: centre.
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2
        // Step 4: start angle and sweep extent, on the unit circle.
        let theta1 = atan2((y1 - cyp) / ry, (x1 - cxp) / rx)
        let theta2 = atan2((-y1 - cyp) / ry, (-x1 - cxp) / rx)
        var delta = theta2 - theta1
        if sweep && delta < 0 { delta += 2 * .pi }
        if !sweep && delta > 0 { delta -= 2 * .pi }

        // Map a unit-circle point back to the arc's ellipse.
        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cx + cosPhi * rx * x - sinPhi * ry * y,
                    y: cy + sinPhi * rx * x + cosPhi * ry * y)
        }
        let pieces = max(1, Int((abs(delta) / (.pi / 2) - 1e-9).rounded(.up)))
        let step = delta / CGFloat(pieces)
        let k = 4.0 / 3.0 * tan(step / 4)
        var a = theta1
        for i in 0..<pieces {
            let b = a + step
            let c1 = map(cos(a) - k * sin(a), sin(a) + k * cos(a))
            let c2 = map(cos(b) + k * sin(b), sin(b) - k * cos(b))
            let end = i == pieces - 1 ? p1 : map(cos(b), sin(b))
            path.addCurve(to: end, control1: c1, control2: c2)
            a = b
        }
    }

    private struct Scanner {
        private let chars: [Character]
        private var i = 0
        init(_ chars: [Character]) { self.chars = chars }

        var atEnd: Bool { i >= chars.count }
        mutating func advance() { i += 1 }

        mutating func skipSeparators() {
            while i < chars.count, chars[i] == "," || chars[i].isWhitespace { i += 1 }
        }
        func peekLetter() -> Character? {
            i < chars.count && chars[i].isLetter ? chars[i] : nil
        }

        /// An arc flag is a single 0 or 1 and may be glued to what follows.
        mutating func flag() throws -> Bool {
            skipSeparators()
            guard i < chars.count, chars[i] == "0" || chars[i] == "1" else { throw SVGPathError.malformed }
            defer { i += 1 }
            return chars[i] == "1"
        }

        mutating func number() throws -> CGFloat {
            skipSeparators()
            let begin = i
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
            var digits = 0
            while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1; digits += 1 }
            if i < chars.count, chars[i] == "." {
                i += 1
                while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1; digits += 1 }
            }
            guard digits > 0 else { throw SVGPathError.malformed }
            if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                var j = i + 1
                if j < chars.count, chars[j] == "-" || chars[j] == "+" { j += 1 }
                if j < chars.count, chars[j].isASCII, chars[j].isNumber {
                    while j < chars.count, chars[j].isASCII, chars[j].isNumber { j += 1 }
                    i = j
                }
            }
            guard let v = Double(String(chars[begin..<i])), v.isFinite else { throw SVGPathError.malformed }
            return CGFloat(v)
        }
    }
}
