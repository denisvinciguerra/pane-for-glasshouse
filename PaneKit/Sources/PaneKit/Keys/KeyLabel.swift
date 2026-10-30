import Carbon.HIToolbox
import Foundation

public protocol KeyboardLayout: Sendable {
    /// Le caractère de la touche sans modificateur, nil si elle n'en produit pas.
    func character(for keyCode: UInt16) -> String?
}

/// La disposition active, lue une fois à l'init (à appeler sur le fil principal) : les données
/// `kTISPropertyUnicodeKeyLayoutData` sont copiées, `character(for:)` appelle `UCKeyTranslate`.
public struct CurrentKeyboardLayout: KeyboardLayout {
    private let layoutData: Data?
    private let keyboardType: UInt32

    public init() {
        var data: Data?
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        }
        layoutData = data
        keyboardType = UInt32(LMGetKbdType())
    }

    public func character(for keyCode: UInt16) -> String? {
        guard let layoutData else { return nil }
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, keyboardType,
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        return s.unicodeScalars.allSatisfy { $0.value < 0x20 || $0.value == 0x7F } ? nil : s
    }
}

public enum KeyLabel {
    private static let glyphs: [UInt16: String] = [
        KeyCode.up: "↑", KeyCode.down: "↓", KeyCode.left: "←", KeyCode.right: "→",
        KeyCode.returnKey: "↩", KeyCode.keypadEnter: "⌤", KeyCode.escape: "⎋", 48: "⇥", 51: "⌫", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12",
    ]

    /// « ⌘1 », « Z », « ↑ », « ␣ »… : modificateurs dans l'ordre ⌃⌥⇧⌘, puis la touche.
    public static func text(_ binding: KeyBinding, layout: some KeyboardLayout) -> String {
        var s = ""
        if binding.modifiers.contains(.control) { s += "⌃" }
        if binding.modifiers.contains(.option) { s += "⌥" }
        if binding.modifiers.contains(.shift) { s += "⇧" }
        if binding.modifiers.contains(.command) { s += "⌘" }
        switch binding.trigger {
        case .keyCode(let code):
            if let g = glyphs[code] { s += g }
            else if let c = layout.character(for: code), !c.isEmpty { s += c.uppercased() }
            else { s += "#\(code)" }
        case .character(let c):
            s += c == " " ? "␣" : c.uppercased()
        }
        return s
    }
}
