import GameController
import PaneKit
import SwiftUI
import UIKit

/// Whether a hardware keyboard is attached to the iPad: the settings show its keys only then. The
/// Game Controller framework says so; a key pressed proves it too, should it not.
@MainActor @Observable final class HardwareKeyboard {
    private(set) var connected = GCKeyboard.coalesced != nil

    /// Set once in `init`, read again only in `deinit`.
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.connected = true }
            },
            center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.connected = false }
            },
        ]
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// A key came from a hardware keyboard.
    func notePress() {
        if !connected { connected = true }
    }

    /// Back in front: a keyboard may have come or gone meanwhile.
    func refresh() {
        let now = GCKeyboard.coalesced != nil
        if connected != now { connected = now }
    }

    /// Whether the key is down, by the Game Controller framework: false without a keyboard.
    static func isHeld(_ usage: UIKeyboardHIDUsage) -> Bool {
        GCKeyboard.coalesced?.keyboardInput?.button(forKeyCode: GCKeyCode(rawValue: usage.rawValue))?.isPressed == true
    }
}

/// The iPad's hardware keyboard working the remote, as the Mac's keyboard does while the popover is
/// open: a hidden view takes the keys while `active` (Pane in front, no sheet over the remote) and
/// no text field has them, and hands each press to the keyboard controller. A key Pane does not
/// take goes back to the system.
struct HardwareKeys: UIViewRepresentable {
    let keyboard: KeyboardController
    let hardware: HardwareKeyboard
    let active: Bool
    /// Raised when something that held the keys closed (a sheet): the view takes them back.
    let claims: Int

    func makeCoordinator() -> KeyForwarder { KeyForwarder(keyboard: keyboard, hardware: hardware) }

    func makeUIView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        let forwarder = context.coordinator
        view.onPress = { forwarder.press($0) }
        view.onRelease = { forwarder.release($0) }
        view.onLost = { forwarder.lost() }
        view.setActive(active)
        return view
    }

    func updateUIView(_ view: KeyCatcherView, context: Context) {
        let forwarder = context.coordinator
        forwarder.keyboard = keyboard
        view.setActive(active)
        if forwarder.claims != claims {
            forwarder.claims = claims
            view.claimSoon()
        }
    }

    static func dismantleUIView(_ view: KeyCatcherView, coordinator: KeyForwarder) {
        coordinator.lost()
    }
}

/// Turns the presses of the iPad's keyboard into the controller's keys: Option held shows the keys'
/// tiles, each key teaches the layout its character, and a key that pressed a button repeats while
/// it is held (iOS sends no repeats of its own), as the Mac's do.
@MainActor final class KeyForwarder {
    var keyboard: KeyboardController
    /// The last `HardwareKeys.claims` seen.
    var claims = 0
    private let hardware: HardwareKeyboard
    /// The Option keys held, left and right.
    private var options: Set<UIKeyboardHIDUsage> = []
    private var repeating: (usage: UIKeyboardHIDUsage, task: Task<Void, Never>)?

    /// Close to iPadOS's own key repeat.
    private static let repeatDelay: Duration = .milliseconds(400)
    private static let repeatInterval: Duration = .milliseconds(100)
    /// The last resort, should neither the key's release nor the framework's state come: a key
    /// held this long stops repeating.
    private static let repeatLimit: Duration = .seconds(10)

    init(keyboard: KeyboardController, hardware: HardwareKeyboard) {
        self.keyboard = keyboard
        self.hardware = hardware
    }

    /// Whether Pane took the key.
    func press(_ key: UIKey) -> Bool {
        hardware.notePress()
        if key.keyCode == .keyboardLeftAlt || key.keyCode == .keyboardRightAlt {
            options.insert(key.keyCode)
            keyboard.optionChanged(down: true)
            return false
        }
        guard let event = KeyEvent(key) else { return false }
        keyboard.learn(keyCode: event.keyCode, characters: key.charactersIgnoringModifiers)
        stopRepeating()
        // This view has the keys only while no text field does.
        guard keyboard.handle(event, textInputActive: false) else { return false }
        repeatWhileHeld(event, usage: key.keyCode)
        return true
    }

    func release(_ key: UIKey) {
        if repeating?.usage == key.keyCode { stopRepeating() }
        if options.remove(key.keyCode) != nil, options.isEmpty { keyboard.optionChanged(down: false) }
    }

    /// The view lost the keys (a text field, a sheet, the app in the background): nothing stays held.
    func lost() {
        stopRepeating()
        options = []
        // Only when held: this may come during SwiftUI's update of the view.
        if keyboard.state.optionHeld { keyboard.optionChanged(down: false) }
    }

    /// The press again, as a repeat, until the key is let go: `KeyModeState` decides what repeats.
    /// Each turn asks the Game Controller framework whether the key is still down, so the repeat
    /// ends even if its release never reaches this view (the keys gone to another window, an
    /// overlay that swallowed it); a hard limit backs that up.
    private func repeatWhileHeld(_ event: KeyEvent, usage: UIKeyboardHIDUsage) {
        let again = KeyEvent(keyCode: event.keyCode, characters: event.characters, modifiers: event.modifiers, isRepeat: true)
        let clock = ContinuousClock()
        let end = clock.now + Self.repeatLimit
        let task = Task { [weak self] in
            try? await Task.sleep(for: Self.repeatDelay)
            while !Task.isCancelled, clock.now < end, HardwareKeyboard.isHeld(usage) {
                guard let self, self.keyboard.handle(again, textInputActive: false) else { return }
                try? await Task.sleep(for: Self.repeatInterval)
            }
        }
        repeating = (usage, task)
    }

    private func stopRepeating() {
        repeating?.task.cancel()
        repeating = nil
    }
}

/// A view with nothing to show that takes the hardware keyboard's presses while active and no
/// text field is being edited: it hands each press on, and gives the system those not taken.
final class KeyCatcherView: UIView {
    /// Whether the press was taken.
    var onPress: ((UIKey) -> Bool)?
    var onRelease: ((UIKey) -> Void)?
    /// The view no longer has the keys.
    var onLost: (() -> Void)?

    private var isActive = false
    /// A text field or a text view is being edited: the keys are its own.
    private var textEditing = false
    /// The presses taken, by key: their ends are not passed on either.
    private var taken: Set<UIKeyboardHIDUsage> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        let center = NotificationCenter.default
        for name in [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification] {
            center.addObserver(self, selector: #selector(textBegan), name: name, object: nil)
        }
        for name in [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification] {
            center.addObserver(self, selector: #selector(textEnded), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(windowResigned), name: UIWindow.didResignKeyNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var canBecomeFirstResponder: Bool { isActive }

    /// No touch is for it.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            claimSoon()
        } else if isFirstResponder {
            _ = resignFirstResponder()
        } else {
            lose()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        claimSoon()
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { lose() }
        return resigned
    }

    @objc private func textBegan() { textEditing = true }

    /// Its window no longer has the keyboard: a key held may never tell its release here.
    @objc private func windowResigned(_ notification: Notification) {
        if notification.object as? UIWindow === window { lose() }
    }

    @objc private func textEnded() {
        textEditing = false
        claimSoon()
    }

    /// Takes the keys on the next turn, out of SwiftUI's update, and once more a moment later, a
    /// fallback should a closing sheet hand them back to what had them before it.
    func claimSoon() {
        Task { @MainActor [weak self] in
            self?.claim()
            try? await Task.sleep(for: .milliseconds(350))
            self?.claim()
        }
    }

    private func claim() {
        guard isActive, !textEditing, window != nil, !isFirstResponder else { return }
        becomeFirstResponder()
    }

    private func lose() {
        taken = []
        onLost?()
    }

    // MARK: Presses

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passed = Set<UIPress>()
        for press in presses {
            if let key = press.key, onPress?(key) == true {
                taken.insert(key.keyCode)
            } else {
                passed.insert(press)
            }
        }
        if !passed.isEmpty { super.pressesBegan(passed, with: event) }
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let passed = presses.filter { press in press.key.map { !taken.contains($0.keyCode) } ?? true }
        if !passed.isEmpty { super.pressesChanged(passed, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let passed = released(presses)
        if !passed.isEmpty { super.pressesEnded(passed, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let passed = released(presses)
        if !passed.isEmpty { super.pressesCancelled(passed, with: event) }
    }

    /// Tells of each key let go; the presses that were not taken, to pass on.
    private func released(_ presses: Set<UIPress>) -> Set<UIPress> {
        presses.filter { press in
            guard let key = press.key else { return true }
            onRelease?(key)
            return taken.remove(key.keyCode) == nil
        }
    }
}

extension KeyEvent {
    /// A key of the hardware keyboard, by the Mac's key code for its position; nil for a modifier
    /// alone or a key the Mac has not. Its characters are those the Mac would give: Shift applied
    /// (« + » is ⇧= on a QWERTY keyboard), the other modifiers not.
    @MainActor init?(_ key: UIKey) {
        guard let code = HIDKeyCodes.macKeyCode(hidUsage: key.keyCode.rawValue) else { return nil }
        let modifiers = KeyModifiers(key.modifierFlags)
        let shifted = modifiers.subtracting(.shift).isEmpty && !key.characters.isEmpty
        self.init(keyCode: code, characters: shifted ? key.characters : key.charactersIgnoringModifiers,
                  modifiers: modifiers)
    }
}

extension KeyModifiers {
    /// ⌘ ⌥ ⌃ ⇧ of a `UIKey`; Caps Lock and the keypad are not modifiers here.
    init(_ flags: UIKeyModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.alternate) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.shift) { insert(.shift) }
    }
}
