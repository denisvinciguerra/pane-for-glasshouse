import Foundation

public struct KeyModifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = KeyModifiers(rawValue: 1), option = KeyModifiers(rawValue: 2),
                      control = KeyModifiers(rawValue: 4), shift = KeyModifiers(rawValue: 8)
}

/// A key press, free of AppKit: the view layer converts `NSEvent` into it.
public struct KeyEvent: Equatable, Sendable {
    public let keyCode: UInt16
    public let characters: String?   // charactersIgnoringModifiers
    public let modifiers: KeyModifiers
    public let isRepeat: Bool
    public init(keyCode: UInt16, characters: String?, modifiers: KeyModifiers = [], isRepeat: Bool = false) {
        self.keyCode = keyCode; self.characters = characters; self.modifiers = modifiers; self.isRepeat = isRepeat
    }
}

public enum KeyTrigger: Hashable, Sendable { case keyCode(UInt16), character(String) }

public enum KeyCode {   // ANSI codes
    public static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    public static let returnKey: UInt16 = 36, keypadEnter: UInt16 = 76, escape: UInt16 = 53
    /// Kept by position: arrows, 36, 76, 53, Tab 48, ⌫ 51, ⌦ 117, Home 115, End 119, Page Up 116,
    /// Page Down 121, F1–F12.
    public static let positional: Set<UInt16> = [
        left, right, down, up, returnKey, keypadEnter, escape, 48, 51, 117, 115, 119, 116, 121,
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
    ]
}

public struct KeyBinding: Hashable, Codable, Sendable {
    public var trigger: KeyTrigger
    public var modifiers: KeyModifiers
    public init(_ trigger: KeyTrigger, modifiers: KeyModifiers = []) { self.trigger = trigger; self.modifiers = modifiers }

    /// Special keys are recorded by position, the others by lowercased character (Shift dropped);
    /// a modifier key alone records nothing.
    public static func recorded(_ event: KeyEvent) -> KeyBinding? {
        if KeyCode.positional.contains(event.keyCode) { return KeyBinding(.keyCode(event.keyCode), modifiers: event.modifiers) }
        guard let c = event.characters?.lowercased(), !c.isEmpty,
              !c.unicodeScalars.contains(where: { (0xF700...0xF8FF).contains($0.value) }) else { return nil }
        return KeyBinding(.character(c), modifiers: event.modifiers.subtracting(.shift))
    }

    /// A key code needs the exact modifiers; a character matches whatever the key code, Shift aside.
    public func matches(_ event: KeyEvent) -> Bool {
        switch trigger {
        case .keyCode(let code): return event.keyCode == code && event.modifiers == modifiers
        case .character(let c):
            return event.characters?.lowercased() == c && event.modifiers.subtracting(.shift) == modifiers.subtracting(.shift)
        }
    }

    private enum CodingKeys: String, CodingKey { case code, char, mods }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modifiers = KeyModifiers(rawValue: try c.decode(Int.self, forKey: .mods))
        if let code = try c.decodeIfPresent(UInt16.self, forKey: .code) { trigger = .keyCode(code) }
        else { trigger = .character(try c.decode(String.self, forKey: .char)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch trigger {
        case .keyCode(let code): try c.encode(code, forKey: .code)
        case .character(let s): try c.encode(s, forKey: .char)
        }
        try c.encode(modifiers.rawValue, forKey: .mods)
    }
}
