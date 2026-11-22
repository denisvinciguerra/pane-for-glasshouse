import Foundation

/// What moves the TV's pointer on the Mac pad: holding ⌥ while the mouse moves, or dragging with the
/// button held.
public enum PointerMoveGesture: String, CaseIterable, Sendable {
    case drag, option

    public static let defaultsKey = "pointerMoveGesture"

    /// The stored choice; a missing or unknown value is dragging.
    public init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .drag
    }
}

/// Decides when the Mac cursor freezes and thaws and when moves and clicks go to the TV. Pure: the
/// pad feeds it events and carries out the effects it returns.
public struct PointerGesture {
    public enum Effect: Equatable {
        /// Stop the cursor where it is, or first put it at the pad's centre.
        case freeze(centreOnPad: Bool)
        case thaw
        case move(dx: Int, dy: Int)
        case click
    }

    /// The Mac's mouse deltas are scaled by this before they reach the TV.
    static let speed = 1.5

    public let mode: PointerMoveGesture
    /// The cursor is frozen and the mouse drives the TV's pointer.
    public private(set) var isDriving = false

    private var buttonDown = false
    private var carry = (x: 0.0, y: 0.0)

    public init(mode: PointerMoveGesture) {
        self.mode = mode
    }

    public mutating func optionChanged(held: Bool) -> [Effect] {
        guard mode == .option, !held, isDriving else { return [] }
        return stop()
    }

    /// The mouse moved with no button held, anywhere on screen.
    public mutating func moved(dx: Double, dy: Double, optionHeld: Bool, onPad: Bool) -> [Effect] {
        guard mode == .option else {
            // A drag's release that was missed: the press is forgotten, no click comes after.
            guard isDriving else { return [] }
            buttonDown = false
            return stop()
        }
        if isDriving {
            // A ⌥ release that was missed.
            return optionHeld ? scaled(dx, dy) : stop()
        }
        guard optionHeld else { return [] }
        isDriving = true
        carry = (0, 0)
        return [.freeze(centreOnPad: !onPad)] + scaled(dx, dy)
    }

    /// The left button went down on the pad.
    public mutating func pressed() -> [Effect] {
        switch mode {
        case .option:
            return [.click]
        case .drag:
            buttonDown = true
            carry = (0, 0)
            return []
        }
    }

    /// The mouse moved with the button held, the press having started on the pad.
    public mutating func dragged(dx: Double, dy: Double, optionHeld: Bool) -> [Effect] {
        switch mode {
        case .option:
            guard isDriving else { return [] }
            return optionHeld ? scaled(dx, dy) : stop()
        case .drag:
            guard buttonDown else { return [] }
            let moves = scaled(dx, dy)
            guard !moves.isEmpty, !isDriving else { return moves }
            isDriving = true
            return [.freeze(centreOnPad: false)] + moves
        }
    }

    public mutating func released() -> [Effect] {
        guard mode == .drag, buttonDown else { return [] }
        buttonDown = false
        return isDriving ? stop() : [.click]
    }

    /// Any forced end (focus lost, popover closed): back to rest, the press forgotten.
    public mutating func end() -> [Effect] {
        buttonDown = false
        carry = (0, 0)
        return isDriving ? stop() : []
    }

    private mutating func stop() -> [Effect] {
        isDriving = false
        return [.thaw]
    }

    /// The move for a mouse delta, the rounding remainder carried to the next one.
    private mutating func scaled(_ dx: Double, _ dy: Double) -> [Effect] {
        carry.x += dx * Self.speed
        carry.y += dy * Self.speed
        let x = Int(carry.x)
        let y = Int(carry.y)
        carry.x -= Double(x)
        carry.y -= Double(y)
        return x != 0 || y != 0 ? [.move(dx: x, dy: y)] : []
    }
}
