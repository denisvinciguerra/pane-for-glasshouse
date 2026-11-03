import Foundation
import os

/// The layout of an iPad's hardware keyboard, which iOS does not tell: each key pressed teaches
/// the character it types on its own, and a key not pressed yet falls back to US ANSI. The keys'
/// labels thus follow the real keyboard (AZERTY included) once its keys have been used.
public final class LearnedKeyboardLayout: KeyboardLayout {
    private let learned = OSAllocatedUnfairLock<[UInt16: String]>(initialState: [:])

    public init() {}

    /// Keeps what the key types without modifier, lowercased; whether that changed a label. Only
    /// one character teaches: not the name iOS gives a special key (« UIKeyInputUpArrow »), nor a
    /// control or private-use character, nor nothing.
    @discardableResult
    public func learn(keyCode: UInt16, characters: String) -> Bool {
        let c = characters.lowercased()
        guard c.count == 1, !c.unicodeScalars.contains(where: Self.isNotTyped) else { return false }
        return learned.withLock { learned in
            guard learned[keyCode] != c else { return false }
            learned[keyCode] = c
            return true
        }
    }

    public func character(for keyCode: UInt16) -> String? {
        learned.withLock { $0[keyCode] } ?? Self.ansi[keyCode]
    }

    private static func isNotTyped(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || scalar.value == 0x7F || (0xF700...0xF8FF).contains(scalar.value)
    }

    /// US ANSI, as `CurrentKeyboardLayout` reads it on a Mac set to U.S.
    private static let ansi: [UInt16: String] = [
        0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e", 0x03: "f", 0x05: "g", 0x04: "h", 0x22: "i",
        0x26: "j", 0x28: "k", 0x25: "l", 0x2E: "m", 0x2D: "n", 0x1F: "o", 0x23: "p", 0x0C: "q", 0x0F: "r",
        0x01: "s", 0x11: "t", 0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x", 0x10: "y", 0x06: "z",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
        0x1D: "0",
        0x31: " ", 0x1B: "-", 0x18: "=", 0x21: "[", 0x1E: "]", 0x2A: "\\", 0x29: ";", 0x27: "'", 0x32: "`",
        0x2B: ",", 0x2F: ".", 0x2C: "/", 0x0A: "§",
        0x4B: "/", 0x43: "*", 0x4E: "-", 0x45: "+", 0x41: ".", 0x51: "=",
        0x52: "0", 0x53: "1", 0x54: "2", 0x55: "3", 0x56: "4", 0x57: "5", 0x58: "6", 0x59: "7", 0x5B: "8",
        0x5C: "9",
    ]
}
