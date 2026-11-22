import AppKit
import PaneKit
import SwiftUI

/// Mouse and trackpad input: ⌥ held while the mouse moves, or a drag, depending on `gesture`, moves the
/// TV's pointer with the Mac's cursor frozen; a click clicks, the wheel scrolls. The keys go to the
/// text field inside, whose text goes to the TV.
struct PointerMacPad: NSViewRepresentable {
    let controller: PointerController
    let typing: TextTyping
    let gesture: PointerMoveGesture
    /// False while the TV can't be controlled or the pins are being edited: no gesture then.
    let active: Bool
    /// A gesture started (true) or ended (false).
    let drivingChanged: (Bool) -> Void
    @Environment(\.keyboard) private var keyboard

    func makeNSView(context: Context) -> PointerMacView {
        let view = PointerMacView(controller: controller, typing: typing, gesture: gesture, active: active)
        view.keyboard = keyboard
        view.drivingChanged = drivingChanged
        return view
    }

    func updateNSView(_ view: PointerMacView, context: Context) {
        view.keyboard = keyboard
        view.drivingChanged = drivingChanged
        view.mode = gesture
        view.active = active
    }
}

final class PointerMacView: NSView, NSTextFieldDelegate {
    private let controller: PointerController
    private let typing: TextTyping
    /// Esc with nothing typed goes to it, to do what it did before the pad took the keys.
    weak var keyboard: KeyboardController?
    var drivingChanged: (Bool) -> Void = { _ in }
    var mode: PointerMoveGesture {
        get { gesture.mode }
        set {
            guard newValue != gesture.mode else { return }
            endGesture()
            gesture = PointerGesture(mode: newValue)
        }
    }
    var active: Bool {
        didSet { if !active { endGesture() } }
    }
    private var gesture: PointerGesture
    private let cursor = PointerCursor()
    /// The event monitors and notification observers, while the view is in a window.
    private var monitors: [Any] = []
    /// Apart from `monitors`: only there while the window is key.
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    /// The window being watched, and its setting for mouse moves before, given back with it.
    private weak var watchedWindow: NSWindow?
    private var acceptedMouseMoves = false
    private let field = TypingTextField()
    private var scrollCarry = CGPoint.zero
    /// Something was typed since the text was last forgotten: a move or a scroll forgets it. Not every
    /// event of a gesture, which would redraw the echo each time.
    private var typedSinceForget = false

    init(controller: PointerController, typing: TextTyping, gesture mode: PointerMoveGesture, active: Bool) {
        self.controller = controller
        self.typing = typing
        gesture = PointerGesture(mode: mode)
        self.active = active
        super.init(frame: .zero)
        field.delegate = self
        field.spaceOnEmpty = { [weak self] in self?.typing.spaceOnEmpty() }
        field.compositionChanged = { [weak self] in self?.fieldChanged() }
        addSubview(field)
        typing.clearField = { [weak self] in self?.field.setText("") }
    }

    required init?(coder: NSCoder) { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow !== window else { return }
        stopWatching()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        watch(window)
        // After SwiftUI has finished placing the pad.
        Task { @MainActor [weak self] in self?.field.focus() }
    }

    // MARK: Pointer

    override func mouseDown(with event: NSEvent) {
        guard active else { return }
        forget()
        field.focus()
        apply(gesture.pressed())
    }

    override func mouseDragged(with event: NSEvent) {
        guard active else { return }
        apply(gesture.dragged(dx: event.deltaX, dy: event.deltaY, optionHeld: event.modifierFlags.contains(.option)))
    }

    override func mouseUp(with event: NSEvent) {
        guard active else { return }
        apply(gesture.released())
    }

    /// The right button (or a two-finger click) is the remote's Back, at the press, whatever the
    /// gesture; no menu. The TV's focus moves: the text is forgotten.
    override func rightMouseDown(with event: NSEvent) {
        guard active else { return }
        forget()
        field.focus()
        typing.back()
    }

    override func scrollWheel(with event: NSEvent) {
        guard active else { return }
        scrollCarry.x += event.scrollingDeltaX / 4
        scrollCarry.y += event.scrollingDeltaY / 4
        let dx = Int(scrollCarry.x)
        let dy = Int(scrollCarry.y)
        scrollCarry.x -= CGFloat(dx)
        scrollCarry.y -= CGFloat(dy)
        if dx != 0 || dy != 0 {
            forgetUnlessComposing()
            controller.scroll(dx: dx, dy: dy)
        }
    }

    /// The cursor is only frozen while Pane is in front with the pad's window key: the window losing
    /// the key, the view leaving it or the app quitting give it back. The global monitor gets the moves
    /// made over another app, ⌥ held, to start a gesture from there; it only runs while the window is
    /// key, so that the closed popover's window, which may keep the pad, doesn't wake Pane on every move.
    private func watch(_ window: NSWindow) {
        guard window !== watchedWindow else { return }
        stopWatching()
        watchedWindow = window
        acceptedMouseMoves = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .flagsChanged], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.monitored(event) }
            // Never consumed: the accents and the shown keys need the modifiers too.
            return event
        }) {
            monitors.append(local)
        }
        if window.isKeyWindow { watchElsewhere() }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.watchElsewhere() }
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.endGesture()
                    self?.stopWatchingElsewhere()
                }
            },
            center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.endGesture() }
            },
        ]
    }

    /// The moves made over other apps.
    private func watchElsewhere() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.monitored(event) }
        })
    }

    private func stopWatchingElsewhere() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
    }

    private func stopWatching() {
        endGesture()
        stopWatchingElsewhere()
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        watchedWindow?.acceptsMouseMovedEvents = acceptedMouseMoves
        watchedWindow = nil
    }

    /// A move with no button held, anywhere on screen, or a modifier change.
    private func monitored(_ event: NSEvent) {
        guard active, window?.isKeyWindow == true else { return }
        switch event.type {
        case .flagsChanged:
            apply(gesture.optionChanged(held: event.modifierFlags.contains(.option)))
        case .mouseMoved:
            // What is held now, whatever the event says: a release may have been missed.
            let optionHeld = NSEvent.modifierFlags.contains(.option)
            let onPad = padFrame?.contains(NSEvent.mouseLocation) ?? false
            apply(gesture.moved(dx: event.deltaX, dy: event.deltaY, optionHeld: optionHeld, onPad: onPad))
        default:
            break
        }
    }

    /// The pad on screen, in AppKit coordinates.
    private var padFrame: NSRect? {
        window?.convertToScreen(convert(bounds, to: nil))
    }

    private func apply(_ effects: [PointerGesture.Effect]) {
        for effect in effects {
            switch effect {
            case .freeze(let centreOnPad):
                cursor.freeze(centreOn: centreOnPad ? padFrame : nil)
                drivingChanged(true)
            case .thaw:
                cursor.thaw()
                drivingChanged(false)
            case .move(let dx, let dy):
                cursor.keepHeld()
                forgetUnlessComposing()
                controller.move(dx: dx, dy: dy)
            case .click:
                controller.click()
            }
        }
    }

    /// A forced end, which can come while SwiftUI updates or removes the view: the cursor is given
    /// back now, `drivingChanged` told on the next turn, with the state then.
    private func endGesture() {
        guard gesture.end().contains(.thaw) else { return }
        cursor.thaw()
        // The closure is kept: the view may be gone by then, and the gesture with it.
        Task { @MainActor [weak self, drivingChanged] in
            drivingChanged(self?.gesture.isDriving ?? false)
        }
    }

    /// A dead key being composed (⌥e waiting for its letter) stays: clearing the field would lose it.
    /// The text is then forgotten on the first move or scroll after the composition.
    private func forgetUnlessComposing() {
        if typedSinceForget && !field.isComposing { forget() }
    }

    /// The TV's focus may move: the text is forgotten on Pane's side.
    private func forget() {
        typedSinceForget = false
        typing.forget()
    }

    // MARK: Typing

    func controlTextDidChange(_ notification: Notification) {
        fieldChanged()
    }

    /// The text goes to the TV once final; while composed, it only shows.
    private func fieldChanged() {
        guard !field.isWriting else { return }
        let text = field.text
        let kept = typing.fieldChanged(text, composing: field.isComposing)
        if kept != text { field.setText(kept) }
        typedSinceForget = true
    }

    /// Return, Esc, ⌫ with nothing typed and the arrows mean something for the TV; Tab has nowhere to
    /// go, and the field keeps the keys.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // A held Return submits once: its repeats would press OK on what the search brings up.
            guard !NSApp.isKeyRepeat else { return true }
            typing.returnPressed()
        case #selector(NSResponder.cancelOperation(_:)):
            guard typing.escapePressed() else { return escapeUnused() }
        case #selector(NSResponder.deleteBackward(_:)):
            guard textView.string.isEmpty else { return false }
            typing.backspaceOnEmpty()
        case #selector(NSResponder.moveUp(_:)): typing.arrow(.up)
        case #selector(NSResponder.moveDown(_:)): typing.arrow(.down)
        case #selector(NSResponder.moveLeft(_:)): typing.arrow(.left)
        case #selector(NSResponder.moveRight(_:)): typing.arrow(.right)
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            return true
        default:
            return false
        }
        typedSinceForget = true
        return true
    }

    /// Esc with nothing to clear does what it did before the pad took the keys: the button it is
    /// assigned to (Back, in the profiles), else whatever the popover does with it, up the responder
    /// chain. Not consumed then: the field editor passes it on, to the popover's window. A repeat is
    /// swallowed: Esc held, after clearing the text or pressing Back, neither presses again nor closes
    /// the popover.
    private func escapeUnused() -> Bool {
        guard let event = NSApp.currentEvent, event.type == .keyDown else { return false }
        if event.isARepeat { return true }
        return keyboard?.pressUntyped(event) ?? false
    }
}
