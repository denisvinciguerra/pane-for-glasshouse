import Foundation

public struct KeySlot: Hashable, Codable, Sendable {
    public var primary: KeyBinding?
    public var alternate: KeyBinding?
    public enum Role: Sendable { case primary, alternate }
    public init(primary: KeyBinding? = nil, alternate: KeyBinding? = nil) { self.primary = primary; self.alternate = alternate }
}

public enum KeyProfile: String, CaseIterable, Codable, Sendable {
    case arrows, gaming

    public var slots: [ButtonID: KeySlot] {
        func pos(_ code: UInt16) -> KeyBinding { KeyBinding(.keyCode(code)) }
        func ch(_ c: String) -> KeyBinding { KeyBinding(.character(c)) }
        var s: [ButtonID: KeySlot] = [
            .rcu(.home): KeySlot(primary: ch("h")), .rcu(.settings): KeySlot(primary: ch("m")),
            .mute: KeySlot(primary: ch("k")), .media(.playPause): KeySlot(primary: ch(" ")),
            .volumeUp: KeySlot(primary: ch("+")), .volumeDown: KeySlot(primary: ch("-")),
        ]
        switch self {
        case .arrows:
            s[.rcu(.up)] = KeySlot(primary: pos(KeyCode.up)); s[.rcu(.down)] = KeySlot(primary: pos(KeyCode.down))
            s[.rcu(.left)] = KeySlot(primary: pos(KeyCode.left)); s[.rcu(.right)] = KeySlot(primary: pos(KeyCode.right))
            s[.rcu(.ok)] = KeySlot(primary: pos(KeyCode.returnKey), alternate: pos(KeyCode.keypadEnter))
            s[.rcu(.back)] = KeySlot(primary: pos(KeyCode.escape))
        case .gaming:   // W A S D, E, Q by position
            s[.rcu(.up)] = KeySlot(primary: pos(13), alternate: pos(KeyCode.up))
            s[.rcu(.left)] = KeySlot(primary: pos(0), alternate: pos(KeyCode.left))
            s[.rcu(.down)] = KeySlot(primary: pos(1), alternate: pos(KeyCode.down))
            s[.rcu(.right)] = KeySlot(primary: pos(2), alternate: pos(KeyCode.right))
            s[.rcu(.ok)] = KeySlot(primary: pos(14), alternate: pos(KeyCode.returnKey))
            s[.rcu(.back)] = KeySlot(primary: pos(12), alternate: pos(KeyCode.escape))
        }
        return s
    }
}
