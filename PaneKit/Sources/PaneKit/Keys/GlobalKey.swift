import Foundation

/// What the recorder of a global shortcut does with a key press. A combination is kept by key
/// position (`KeyTrigger.keyCode`), not by character as the popover's keys are: the system
/// registers a key code, so the shortcut needs no re-registering when the keyboard layout changes,
/// and two combinations compare exactly. The label shown follows the layout in use.
public enum GlobalRecording: Equatable, Sendable {
    case record(KeyBinding)
    /// A key without ⌘, ⌃ or ⌥: a global shortcut needs one, so the recorder keeps waiting.
    case needsModifier
    case cancel, clear
    /// A key that records nothing (a modifier alone): the recorder keeps waiting.
    case ignore
}

public enum GlobalKey {
    private static let delete: UInt16 = 51

    /// ⎋ alone cancels, ⌫ alone clears the shortcut; any other key needs ⌘, ⌃ or ⌥ (⇧ counts too).
    public static func input(_ event: KeyEvent) -> GlobalRecording {
        if event.modifiers.isEmpty {
            if event.keyCode == KeyCode.escape { return .cancel }
            if event.keyCode == delete { return .clear }
        }
        guard KeyBinding.recorded(event) != nil else { return .ignore }
        guard !event.modifiers.intersection([.command, .control, .option]).isEmpty else { return .needsModifier }
        return .record(KeyBinding(.keyCode(event.keyCode), modifiers: event.modifiers))
    }
}
