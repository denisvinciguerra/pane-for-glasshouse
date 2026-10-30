import PaneKit
import SwiftUI

extension View {
    /// A button that can carry a key: its tile while the keys show, and the right-click menu to set
    /// or remove it (and, for a pinned action, to unpin or edit it).
    func keyed(_ id: ButtonID, pinned: CustomAction? = nil) -> some View {
        modifier(Keyed(id: id, pinned: pinned))
    }
}

private struct Keyed: ViewModifier {
    let id: ButtonID
    let pinned: CustomAction?
    @Environment(\.keyboard) private var keyboard
    @Environment(\.appModel) private var model
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let label = keyboard?.label(for: id)
        let awaiting = keyboard?.awaitingKey == id
        content
            .environment(\.palette, awaiting ? palette.awaitingKey : palette)
            .background(awaiting ? palette.accent.opacity(0.08) : .clear)
            .overlay(alignment: .topTrailing) {
                if keyboard?.state.showsTiles == true {
                    KeyTile(text: awaiting ? "?" : label, amber: awaiting)
                        .offset(x: 5, y: -6)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contextMenu {
                Button("Set Key…") { keyboard?.setKey(for: id) }
                Button("Remove Key") { keyboard?.removeKey(of: id) }
                    .keyboardShortcut(keyboard.flatMap { $0.shortcut(for: id) })
                    .disabled(label == nil)
                if let pinned {
                    Divider()
                    Button("Unpin") { model?.unpin(pinned.id) }
                    Button("Edit Action…") {
                        keyboard?.leaveKeyModes()
                        model?.edit(pinned)
                    }
                }
            }
    }
}

/// The small inverted tile in a button's top right corner: its key, a dashed "·" without one,
/// an amber "?" while it awaits one.
private struct KeyTile: View {
    let text: String?
    let amber: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Text(verbatim: text ?? "·")
            .font(.manrope(8.5, .semibold))
            .textCase(nil)
            .tracking(0)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 3)
            .frame(minWidth: 14, minHeight: 14, maxHeight: 14)
            .foregroundStyle(text == nil ? palette.fg.opacity(0.5) : palette.bg)
            .background(amber ? palette.accent : text == nil ? palette.bg : palette.fg)
            .overlay {
                if text == nil {
                    Rectangle().strokeBorder(palette.fg.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
    }
}

extension KeyboardController {
    /// The button awaiting its key, in the edit mode or after "Set Key…".
    var awaitingKey: ButtonID? {
        switch state.mode {
        case .editing(let id): id
        case .capturing(let id): id
        case .normal, .showing: nil
        }
    }

    /// The main key as a menu shortcut, only to show it on the right of "Remove Key".
    func shortcut(for id: ButtonID) -> KeyboardShortcut? {
        guard let binding = key(of: id) else { return nil }
        let key: KeyEquivalent?
        switch binding.trigger {
        case .keyCode(let code): key = Self.equivalents[code] ?? layout.character(for: code).flatMap(Self.equivalent)
        case .character(let c): key = c == " " ? .space : Self.equivalent(c)
        }
        guard let key else { return nil }
        var modifiers: EventModifiers = []
        if binding.modifiers.contains(.command) { modifiers.insert(.command) }
        if binding.modifiers.contains(.option) { modifiers.insert(.option) }
        if binding.modifiers.contains(.control) { modifiers.insert(.control) }
        if binding.modifiers.contains(.shift) { modifiers.insert(.shift) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }

    private static func equivalent(_ s: String) -> KeyEquivalent? {
        s.count == 1 ? KeyEquivalent(Character(s.lowercased())) : nil
    }

    private static let equivalents: [UInt16: KeyEquivalent] = {
        var map: [UInt16: KeyEquivalent] = [
            KeyCode.up: .upArrow, KeyCode.down: .downArrow, KeyCode.left: .leftArrow, KeyCode.right: .rightArrow,
            KeyCode.returnKey: .return, KeyCode.keypadEnter: KeyEquivalent("\u{3}"), KeyCode.escape: .escape,
            48: .tab, 51: .delete, 117: .deleteForward, 115: .home, 119: .end, 116: .pageUp, 121: .pageDown,
        ]
        // F1–F12: NSF1FunctionKey (0xF704) onwards.
        for (n, code) in [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111].enumerated() {
            if let scalar = Unicode.Scalar(0xF704 + n) { map[UInt16(code)] = KeyEquivalent(Character(scalar)) }
        }
        return map
    }()
}
