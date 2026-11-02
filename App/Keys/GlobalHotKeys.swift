import Carbon.HIToolbox
import Observation
import PaneKit

/// The global shortcuts, registered with the system by `RegisterEventHotKey`: they work whatever
/// app is in front, with no accessibility permission and no watch on the keyboard. Holding a
/// combination presses its button once.
@MainActor @Observable final class GlobalHotKeys {
    /// The combinations wanted that the system refused: another app holds them, or another of
    /// Pane's shortcuts (a shared button's, before an action's).
    var inactive: Set<ButtonID> { Set(refused.keys) }
    @ObservationIgnored var onPress: (ButtonID) -> Void = { _ in }

    private struct Registration {
        let binding: KeyBinding
        let number: UInt32
        let ref: EventHotKeyRef
    }

    /// 'PANE', in every `EventHotKeyID` Pane registers.
    nonisolated fileprivate static let signature: OSType = 0x50414E45
    /// The number `isFree` registers under for an instant; the buttons' start at 1.
    private static let probeNumber: UInt32 = 0

    /// Refused combinations stand while they are wanted, and are not tried again until they
    /// change, Pane drops one of its own, or the shortcuts come back from a suspension.
    private var refused: [ButtonID: KeyBinding] = [:]
    // Read by `deinit`, which is not on the main actor.
    @ObservationIgnored nonisolated(unsafe) private var registered: [ButtonID: Registration] = [:]
    @ObservationIgnored nonisolated(unsafe) private var handler: EventHandlerRef?
    @ObservationIgnored private var nextNumber: UInt32 = 1
    /// The buttons whose combination is down: its repeats press nothing.
    @ObservationIgnored private var held: Set<ButtonID> = []
    @ObservationIgnored private var suspended = false

    init() {
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, events.count, &events,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        for registration in registered.values { UnregisterEventHotKey(registration.ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Registers the combinations wanted (by key position only: the others are ignored), and drops
    /// those no longer wanted. Only what changed is registered again. `suspended`: none is kept,
    /// and all come back when it turns false.
    func update(_ wanted: [ButtonID: KeyBinding], suspended: Bool) {
        let wanted = wanted.filter { $0.value.keyCode != nil }
        let resuming = self.suspended && !suspended
        self.suspended = suspended
        // A combination Pane drops may be one it refused to another of its ids: those are tried again.
        var dropped = false
        for (id, registration) in registered where suspended || wanted[id] != registration.binding {
            unregister(id)
            dropped = true
        }
        var refused = self.refused.filter { wanted[$0.key] == $0.value }
        if !suspended {
            // Buttons and sources before actions: a combination left on a shared button and on an
            // action (of another TV) is the button's, and the action's is refused.
            func rank(_ id: ButtonID) -> Int { id.actionID == nil ? 0 : 1 }
            let ids = wanted.keys.sorted { (rank($0), $0.rawValue) < (rank($1), $1.rawValue) }
            for id in ids {
                guard let binding = wanted[id], registered[id] == nil, resuming || dropped || refused[id] != binding else { continue }
                refused[id] = register(binding, for: id) ? nil : binding
            }
        }
        if refused != self.refused { self.refused = refused }
    }

    /// Whether the system would let Pane register the combination now: it is registered, then
    /// dropped at once. Pane's own registered combinations count as taken.
    func isFree(_ binding: KeyBinding) -> Bool {
        guard let ref = Self.register(binding, number: Self.probeNumber) else { return false }
        UnregisterEventHotKey(ref)
        return true
    }

    private func register(_ binding: KeyBinding, for id: ButtonID) -> Bool {
        guard let ref = Self.register(binding, number: nextNumber) else { return false }
        registered[id] = Registration(binding: binding, number: nextNumber, ref: ref)
        nextNumber += 1
        return true
    }

    /// Exclusive: a non-exclusive registration succeeds beside another app's, and both receive the
    /// combination. An exclusive one is refused while another is registered, and once made, it
    /// is the only one that fires.
    private static func register(_ binding: KeyBinding, number: UInt32) -> EventHotKeyRef? {
        guard let keyCode = binding.keyCode else { return nil }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), binding.modifiers.carbon,
                                         EventHotKeyID(signature: signature, id: number),
                                         GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &ref)
        return status == noErr ? ref : nil
    }

    private func unregister(_ id: ButtonID) {
        guard let registration = registered.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(registration.ref)
        // Its release will not come any more.
        held.remove(id)
    }

    // MARK: Events

    fileprivate func received(_ number: UInt32, pressed: Bool) {
        guard let id = registered.first(where: { $0.value.number == number })?.key else { return }
        if pressed {
            guard held.insert(id).inserted else { return }
            onPress(id)
        } else {
            held.remove(id)
        }
    }
}

/// The handler of the hot-key events, a C function: `userData` is the `GlobalHotKeys`. The
/// application's event target calls it on the main thread.
private func hotKeyHandler(_ call: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKey = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
    guard status == noErr, hotKey.signature == GlobalHotKeys.signature else { return OSStatus(eventNotHandledErr) }
    let number = hotKey.id
    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let keys = UInt(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: keys) else { return }
        Unmanaged<GlobalHotKeys>.fromOpaque(pointer).takeUnretainedValue().received(number, pressed: pressed)
    }
    return noErr
}

private extension KeyBinding {
    var keyCode: UInt16? {
        if case .keyCode(let code) = trigger { code } else { nil }
    }
}

private extension KeyModifiers {
    /// ⌘ ⌥ ⌃ ⇧ as `RegisterEventHotKey` takes them.
    var carbon: UInt32 {
        var flags = 0
        if contains(.command) { flags |= cmdKey }
        if contains(.option) { flags |= optionKey }
        if contains(.control) { flags |= controlKey }
        if contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}
