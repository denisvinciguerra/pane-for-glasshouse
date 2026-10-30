import AppKit
import Carbon.HIToolbox
import Observation
import PaneKit
import SwiftUI

/// The keyboard while the popover is open: a local monitor on its window turns the keys into
/// presses or new keys, by the key modes of `KeyModeState`. There is no global shortcut.
@MainActor @Observable final class KeyboardController {
    private(set) var state = KeyModeState()
    /// Read again at each opening and when the input source changes.
    private(set) var layout = CurrentKeyboardLayout()

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var layoutObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
    }

    /// Starts listening to the popover's window: its key presses and its modifier changes (⌥).
    func attach(to window: NSWindow) {
        detachMonitors()
        self.window = window
        layout = CurrentKeyboardLayout()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handle(event)
            } ? nil : event
        }
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout = CurrentKeyboardLayout() }
        }
    }

    /// The popover closed: no more listening, back to the normal mode.
    func detach() {
        detachMonitors()
        window = nil
        state.closed()
    }

    private func detachMonitors() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let layoutObserver { DistributedNotificationCenter.default().removeObserver(layoutObserver) }
        layoutObserver = nil
    }

    // MARK: Events

    /// Whether the event is consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // ⌘, opens the preferences, from the connect form and the action editor too.
        if event.type == .keyDown, KeyModifiers(flags) == .command, event.charactersIgnoringModifiers == "," {
            model.openPreferences(.keys)
            return true
        }
        // The action editor has no buttons to press: its keys are its own.
        guard model.session != nil, model.editingAction == nil else { return false }
        if event.type == .flagsChanged {
            state.optionChanged(down: flags.contains(.option))
            return false
        }
        let key = KeyEvent(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
                           modifiers: KeyModifiers(flags), isRepeat: event.isARepeat)
        let effect = state.key(key, assignments: model.assignments, layout: layout,
                               textInputActive: window.firstResponder is NSText)
        if effect == .pass { return false }
        perform(effect)
        return true
    }

    /// A change of keys that would replace the Custom profile asks first, unless `confirmed`.
    private func perform(_ effect: KeyModeState.Effect, confirmed: Bool = false) {
        let assignments: KeyAssignments
        switch effect {
        case .none, .pass: return
        case .fire(let id):
            model.press(id)
            return
        case .assign(let binding, let id):
            guard case .assigned(let result) = model.assignments.assigning(binding, to: id, layout: layout) else { return }
            assignments = result
        case .swap(let binding, let id, let owner):
            assignments = model.assignments.swapping(binding, to: id, from: owner, layout: layout)
        case .remove(let id):
            assignments = model.assignments.removingPrimary(of: id)
        }
        if !confirmed, model.replacesCustom(assignments) {
            state.askToReplace(effect)
        } else {
            model.apply(assignments)
        }
    }

    // MARK: Clicks

    /// The footer's keyboard icon: shows the keys, hides them; ⌥-click edits them all.
    func iconClicked() {
        state.iconClicked(option: NSEvent.modifierFlags.contains(.option))
    }

    /// "Edit" in the bar while the keys show: every button awaits a click, as after ⌥-click.
    func editAll() {
        state.editAll()
    }

    /// A button of Remote: its press, or, while editing, the button that awaits its key.
    func buttonClicked(_ id: ButtonID) {
        perform(state.buttonClicked(id))
    }

    /// "Set Key…": the next key goes to this button.
    func setKey(for id: ButtonID) {
        state.setKey(for: id)
    }

    /// The action editor opens: no key mode is left under it, ⌥ included (the editor's keys are
    /// its own, so Esc could no longer leave one).
    func leaveKeyModes() {
        state.closed()
    }

    func removeKey(of id: ButtonID) {
        perform(.remove(id))
    }

    /// "Done" in the edit bar: back to the normal mode.
    func done() {
        state.done()
    }

    func resolveConflict(swap: Bool) {
        perform(state.resolveConflict(swap: swap))
    }

    /// "Replace your Custom profile?": Replace applies the change that waited.
    func resolveReplacement(replace: Bool) {
        perform(state.resolveReplacement(replace: replace), confirmed: true)
    }

    /// The button's main key.
    func key(of id: ButtonID) -> KeyBinding? {
        model.assignments.slots[id]?.primary
    }

    /// The button's main key as the Mac's layout types it; nil without one.
    func label(for id: ButtonID) -> String? {
        key(of: id).map { KeyLabel.text($0, layout: layout) }
    }

    /// A button's name, for the edit bar.
    func title(of id: ButtonID) -> String {
        let inputs = model.session?.stats.map(sources(from:)) ?? []
        let actions = model.store.activeID.map(model.actions.actions(for:)) ?? []
        return id.title(sources: inputs, actions: actions)
    }

    #if DEBUG
    /// Screenshots (-PaneKeys): "show" shows the keys; "edit" is the edit mode, Back awaiting its key.
    func enterForScreenshot(_ mode: String) {
        switch mode {
        case "show": state.iconClicked(option: false)
        case "edit":
            state.iconClicked(option: true)
            _ = state.buttonClicked(.rcu(.back))
        default: break
        }
    }
    #endif
}

extension EnvironmentValues {
    @Entry var keyboard: KeyboardController?
}

extension KeyModifiers {
    /// ⌘ ⌥ ⌃ ⇧ of an `NSEvent`; Caps Lock and fn are not modifiers here.
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.shift) { insert(.shift) }
    }
}
