import PaneKit
import UIKit

/// The pointer pad's text field on iPhone and iPad: it raises the on-screen keyboard and gives the
/// typing for the TV its accents, input methods, dictation and paste (⌘V, the iPad's shortcut bar),
/// and `TypingEchoView` draws what it holds. Invisible and 1 × 1 pt; the touches are the pad's. No
/// capitals or corrections of its own: the TV's searches ignore case, the `keys` way has lowercase
/// only, and a correction would send surprising replacements. On the on-screen keyboard, Space is
/// always a space; with a hardware keyboard, the arrows, Esc and Space on an empty field mean what
/// they mean on the Mac.
final class TypingTextField: UITextField {
    /// Close to iPadOS's own key repeat (as `KeyForwarder`'s): iOS sends no repeats of its own.
    private static let repeatDelay: Duration = .milliseconds(400)
    private static let repeatInterval: Duration = .milliseconds(100)
    /// Should the key's release never come: an arrow held this long stops repeating.
    private static let repeatLimit: Duration = .seconds(10)

    private let typing: TextTyping
    /// Esc with nothing to clear goes to it, to press the button it is assigned to.
    weak var keyboard: KeyboardController?
    private let returnKey = ReturnKey()
    /// `setText` is writing: what the field reports then is not the user's typing.
    private var isWriting = false
    /// The hardware keys taken: their ends are not passed on either.
    private var taken: Set<UIKeyboardHIDUsage> = []
    private var repeating: (usage: UIKeyboardHIDUsage, task: Task<Void, Never>)?
    /// The iPhone's bar above the keyboard.
    private var accessory: UIView?

    /// The screen's background, under the bar above the keyboard.
    var accessoryBackground: UIColor? {
        get { accessory?.backgroundColor }
        set { accessory?.backgroundColor = newValue }
    }

    init(typing: TextTyping) {
        self.typing = typing
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        inlinePredictionType = .no
        returnKeyType = .send
        alpha = 0
        tintColor = .clear
        // `TypingEchoView` is where the text is read.
        isAccessibilityElement = false
        returnKey.pressed = { [weak self] in self?.typing.returnPressed() }
        delegate = returnKey
        addTarget(self, action: #selector(changed), for: .editingChanged)
        // On the iPhone, the field has no edit menu (its touches are the pad's) and the keyboard no
        // Paste key: Paste goes above the keyboard, a paste control (no permission asked), with a way
        // down for it other than the pad's icon. The iPad's keyboard has both.
        if UIDevice.current.userInterfaceIdiom == .phone {
            pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
            let paste = UIPasteControl(configuration: {
                let configuration = UIPasteControl.Configuration()
                configuration.displayMode = .iconOnly
                configuration.cornerStyle = .capsule
                return configuration
            }())
            paste.target = self
            let bar = UIToolbar()
            bar.items = [UIBarButtonItem(systemItem: .flexibleSpace),
                         UIBarButtonItem(customView: paste),
                         UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
                             _ = self?.resignFirstResponder()
                         })]
            bar.sizeToFit()
            bar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
            bar.setShadowImage(UIImage(), forToolbarPosition: .any)
            // The bar takes every touch across its width: on the screen's background, the remote's keys
            // it lies over do not show through as if they could be pressed.
            let holder = UIView(frame: CGRect(origin: .zero, size: bar.frame.size))
            bar.frame = holder.bounds
            bar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            holder.addSubview(bar)
            accessory = holder
            inputAccessoryView = holder
        }
    }

    /// The paste control's text, typed at the caret as if by the keyboard: it goes to the TV like the
    /// rest, cut at the limit.
    override func paste(itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
        _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            guard let text = object as? NSString else { return }
            let string = text as String
            Task { @MainActor in self?.insertText(string) }
        }
    }

    required init?(coder: NSCoder) { nil }

    /// A touch on its point is the pad's. (A field that takes no touches at all could not take the keys.)
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

    /// Replaces the text, ending a composition first.
    func setText(_ text: String) {
        isWriting = true
        defer { isWriting = false }
        unmarkText()
        self.text = text
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            stopRepeating()
            taken = []
        }
        return resigned
    }

    // MARK: Typing

    /// The text goes to the TV once final; while composed, it only shows.
    @objc private func changed() {
        guard !isWriting else { return }
        let text = text ?? ""
        let kept = typing.fieldChanged(text, composing: markedTextRange != nil)
        if kept != text { setText(kept) }
    }

    /// ⌫ with nothing typed: the TV's field may hold text Pane does not know of.
    override func deleteBackward() {
        guard (text ?? "").isEmpty, markedTextRange == nil else {
            super.deleteBackward()
            return
        }
        typing.backspaceOnEmpty()
    }

    // MARK: Hardware keys

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passed = Set<UIPress>()
        for press in presses {
            if let key = press.key, took(key) {
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

    /// The presses that were not taken, to pass on.
    private func released(_ presses: Set<UIPress>) -> Set<UIPress> {
        presses.filter { press in
            guard let key = press.key else { return true }
            if repeating?.usage == key.keyCode { stopRepeating() }
            return taken.remove(key.keyCode) == nil
        }
    }

    /// The arrows move the TV's focus, Esc clears the text, Space with nothing typed plays or pauses;
    /// with a modifier, or while composing (an input method's candidates), they are the field's.
    private func took(_ key: UIKey) -> Bool {
        stopRepeating()
        guard markedTextRange == nil,
              key.modifierFlags.isDisjoint(with: [.command, .alternate, .control, .shift]) else { return false }
        switch key.keyCode {
        case .keyboardUpArrow: arrow(.up, held: key.keyCode)
        case .keyboardDownArrow: arrow(.down, held: key.keyCode)
        case .keyboardLeftArrow: arrow(.left, held: key.keyCode)
        case .keyboardRightArrow: arrow(.right, held: key.keyCode)
        case .keyboardEscape:
            return typing.escapePressed() || escapeUnused(key)
        case .keyboardSpacebar:
            guard (text ?? "").isEmpty else { return false }
            typing.spaceOnEmpty()
        default:
            return false
        }
        return true
    }

    /// Esc with nothing to clear does what it did before the pad took the keys: the button it is
    /// assigned to (Back, in the profiles), else whatever the system does with it. iOS sends no
    /// repeats, so a held Esc presses once.
    private func escapeUnused(_ key: UIKey) -> Bool {
        guard let event = KeyEvent(key) else { return false }
        return keyboard?.pressUntyped(event) ?? false
    }

    /// The arrow again while it is held, as on the Mac.
    private func arrow(_ direction: RemoteKey, held usage: UIKeyboardHIDUsage) {
        typing.arrow(direction)
        let clock = ContinuousClock()
        let end = clock.now + Self.repeatLimit
        let task = Task { [weak self] in
            try? await Task.sleep(for: Self.repeatDelay)
            while !Task.isCancelled, clock.now < end, HardwareKeyboard.isHeld(usage) {
                guard let self else { return }
                self.typing.arrow(direction)
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

/// Return sends: the text is submitted on the TV (OK with nothing typed), the keyboard stays up.
private final class ReturnKey: NSObject, UITextFieldDelegate {
    var pressed: (() -> Void)?

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        pressed?()
        return false
    }
}
