import Foundation

/// What a key recorder of the preferences does with a key press: ⎋ alone cancels, ⌫ alone clears
/// the key, any other key is recorded as the profiles record it (`KeyBinding.recorded`).
public enum KeyRecording: Equatable, Sendable {
    case cancel, clear, record(KeyBinding)
    /// A key that records nothing (a modifier alone): the recorder keeps waiting.
    case ignore

    private static let delete: UInt16 = 51

    public static func input(_ event: KeyEvent) -> KeyRecording {
        if event.modifiers.isEmpty {
            if event.keyCode == KeyCode.escape { return .cancel }
            if event.keyCode == delete { return .clear }
        }
        return KeyBinding.recorded(event).map(KeyRecording.record) ?? .ignore
    }
}
