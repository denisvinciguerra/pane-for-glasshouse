import Foundation

/// The text typed for the TV, as the pointer pad shows it: letters that light up as they arrive and go
/// out ten seconds after the last key (mockups/2026-11-05-touchpad/pane-integre.html, "Lumière").
///
/// Pure timing: the time is always a parameter, and nothing here draws. The view asks `look(ofLetter:at:)`
/// for each letter, redraws while `isAnimating(at:)`, and wakes up on `nextWake(after:)`.
public struct TypingEcho: Sendable {
    /// Seconds from the last change to the start of the fade.
    public static let fadeAfter: TimeInterval = 10
    /// A letter lights up over this long.
    public static let arrival: TimeInterval = 0.55
    /// A letter goes out over this long.
    public static let departure: TimeInterval = 1.0
    /// The most a letter waits for the one before it when they go out.
    public static let maxStep: TimeInterval = 0.03
    /// The most the whole line waits.
    public static let maxSpread: TimeInterval = 0.65
    /// A deleted letter goes out over this long.
    public static let removal: TimeInterval = 0.22
    /// The one fade of every letter at once, with reduced motion.
    private static let reducedDeparture: TimeInterval = 0.4
    /// Floating point: 100.55 - 100 is a hair under 0.55, and that letter is settled.
    private static let epsilon: TimeInterval = 1e-9

    public struct Look: Equatable, Sendable {
        public var opacity: Double
        public var glow: Double

        public init(opacity: Double, glow: Double) {
            self.opacity = opacity
            self.glow = glow
        }
    }

    /// A letter deleted with the delete key, going out where it stood.
    public struct Departure: Equatable, Sendable {
        public let letter: Character
        public let index: Int
        public let start: TimeInterval

        public init(letter: Character, index: Int, start: TimeInterval) {
            self.letter = letter
            self.index = index
            self.start = start
        }
    }

    public enum Phase: Equatable, Sendable { case hidden, showing, leaving }

    private let reducedMotion: Bool
    /// Deleted letters still going out; the finished ones are dropped at the next change.
    public private(set) var departures: [Departure] = []
    public private(set) var letters: [Character] = []
    /// When each letter began to light up.
    private var arrivals: [TimeInterval] = []
    private var lastChange: TimeInterval = 0
    /// Return or Esc: when the letters were told to go out.
    private var explicitLeave: TimeInterval?
    /// A leave happened: the next change starts a new text instead of adding to the old one.
    private var startsAfresh = false

    public init(reducedMotion: Bool = false) {
        self.reducedMotion = reducedMotion
    }

    // MARK: Changes

    /// The text changed: only what follows the common prefix is new. Characters, not UTF-16.
    public mutating func textChanged(_ text: String, at time: TimeInterval) {
        let new = Array(text)
        departures.removeAll { time - $0.start >= Self.removal }
        if startsAfresh {
            // The field is emptied after a leave; that must not cut the leave short.
            if new.isEmpty { return }
            reset()
            light(new, keeping: 0, at: time)
            return
        }
        if new.isEmpty {
            // Emptied by deleting: hidden at once, but the removed letters still go out.
            let going = reducedMotion ? [] : letters.indices.map {
                Departure(letter: letters[$0], index: $0, start: time)
            }
            let running = departures
            reset()
            departures = running + going
            return
        }
        guard new != letters else { return }
        var common = 0
        while common < min(new.count, letters.count), new[common] == letters[common] { common += 1 }
        if !reducedMotion {
            departures += letters.indices.dropFirst(common).map {
                Departure(letter: letters[$0], index: $0, start: time)
            }
        }
        light(new, keeping: common, at: time)
    }

    /// Return or Esc: the letters on screen go out now, and the next change starts afresh.
    public mutating func leave(at time: TimeInterval) {
        guard !letters.isEmpty else { return }
        departures = []
        startsAfresh = true
        if time < leaveStart { explicitLeave = time }
    }

    /// A click or a move on the TV: gone at once.
    public mutating func reset() {
        letters = []
        arrivals = []
        departures = []
        explicitLeave = nil
        startsAfresh = false
    }

    private mutating func light(_ new: [Character], keeping common: Int, at time: TimeInterval) {
        arrivals = Array(arrivals.prefix(common)) + Array(repeating: time, count: new.count - common)
        letters = new
        lastChange = time
        explicitLeave = nil
        startsAfresh = false
    }

    // MARK: Reading

    private var leaveStart: TimeInterval { explicitLeave ?? lastChange + Self.fadeAfter }

    private var step: TimeInterval {
        reducedMotion ? 0 : min(Self.maxStep, Self.maxSpread / Double(max(1, letters.count)))
    }

    private var letterDeparture: TimeInterval { reducedMotion ? Self.reducedDeparture : Self.departure }

    /// When the last letter is gone.
    private var leaveEnd: TimeInterval {
        leaveStart + Double(max(0, letters.count - 1)) * step + letterDeparture
    }

    /// How far a deleted letter is into its departure, 0 to 1.
    public func removalProgress(of departure: Departure, at time: TimeInterval) -> Double {
        min(1, max(0, (time - departure.start) / Self.removal))
    }

    public func phase(at time: TimeInterval) -> Phase {
        if letters.isEmpty || time >= leaveEnd { return .hidden }
        return time >= leaveStart ? .leaving : .showing
    }

    public func look(ofLetter index: Int, at time: TimeInterval) -> Look {
        guard letters.indices.contains(index) else { return Look(opacity: 0, glow: 0) }
        let gone = (time - leaveStart - Double(index) * step) / letterDeparture
        if gone > 0 { return Self.departing(gone, reduced: reducedMotion) }
        return reducedMotion ? Look(opacity: 1, glow: 0) : Self.arriving(time - arrivals[index])
    }

    /// `elapsed` is the time since the letter began to light up.
    private static func arriving(_ elapsed: TimeInterval) -> Look {
        if elapsed >= arrival - epsilon { return Look(opacity: 1, glow: 0) }
        let p = max(0, elapsed) / arrival
        if p <= 0.25 { return Look(opacity: 0.2 + 0.8 * (p / 0.25), glow: 0.6 - 0.1 * (p / 0.25)) }
        return Look(opacity: 1, glow: 0.5 * (1 - (p - 0.25) / 0.75))
    }

    /// `p` is how far the letter is into its departure, 0 to 1.
    private static func departing(_ p: Double, reduced: Bool) -> Look {
        if p >= 1 { return Look(opacity: 0, glow: 0) }
        if reduced { return Look(opacity: 1 - p, glow: 0) }
        if p <= 0.35 { return Look(opacity: 1 - 0.4 * (p / 0.35), glow: 0.22 * (p / 0.35)) }
        let rest = (p - 0.35) / 0.65
        return Look(opacity: 0.6 * (1 - rest), glow: 0.22 * (1 - rest))
    }

    /// Whether the letters are changing now: nothing needs redrawing when this is false.
    public func isAnimating(at time: TimeInterval) -> Bool {
        if departures.contains(where: { time - $0.start < Self.removal }) { return true }
        return switch phase(at: time) {
        case .hidden: false
        case .leaving: true
        case .showing: !reducedMotion && arrivals.contains { time < $0 + Self.arrival - Self.epsilon }
        }
    }

    /// When the phase next changes by itself, nil if never.
    public func nextChange(after time: TimeInterval) -> TimeInterval? {
        if letters.isEmpty { return nil }
        if time < leaveStart { return leaveStart }
        return time < leaveEnd ? leaveEnd : nil
    }

    /// When something next needs a redraw by itself: a letter settles, or the phase changes.
    public func nextWake(after time: TimeInterval) -> TimeInterval? {
        let settling = reducedMotion ? [] : arrivals.map { $0 + Self.arrival }.filter { $0 > time && $0 < leaveStart }
        let leaving = departures.map { $0.start + Self.removal }.filter { $0 > time }
        return (settling + leaving + [nextChange(after: time)].compactMap { $0 }).min()
    }

    /// The font size in points for a text of `count` characters.
    public static func textSize(forCount count: Int) -> Double {
        count <= 12 ? 28 : count <= 22 ? 23 : 19
    }
}
