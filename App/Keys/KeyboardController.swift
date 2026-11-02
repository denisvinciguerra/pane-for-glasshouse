import AppKit
import Carbon.HIToolbox
import Observation
import PaneKit
import SwiftUI

/// The keyboard while the popover is open: a local monitor on its window turns the keys into
/// presses or new keys, by the key modes of `KeyModeState`, and a right-click on a button into its
/// choice in the keys shown. The global shortcuts are registered apart, by `GlobalHotKeys`, and are
/// suspended while a button awaits its key or its shortcut.
@MainActor @Observable final class KeyboardController {
    private(set) var state = KeyModeState()
    /// Read again at each opening and when the input source changes.
    private(set) var layout = CurrentKeyboardLayout()
    /// The pins' "+" list is open: it takes the keys, Esc closes it.
    var pinsListOpen = false
    /// Remote's pins are being edited (Edit, next to Pinned): the keys send nothing, Esc ends it.
    private(set) var pinsEditing = false

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var layoutObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
    }

    /// Starts listening to the popover's window: its key presses, its modifier changes (⌥) and its
    /// right-clicks.
    func attach(to window: NSWindow) {
        detachMonitors()
        self.window = window
        layout = CurrentKeyboardLayout()
        let events: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .rightMouseDown, .leftMouseDown]
        monitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
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
        finishEditingPins()
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
        if event.type == .rightMouseDown || event.type == .leftMouseDown {
            return rightClicked(event, control: flags.contains(.control))
        }
        // ⌘, opens the preferences, from the connect form and the action editor too.
        if event.type == .keyDown, KeyModifiers(flags) == .command, event.charactersIgnoringModifiers == "," {
            model.openPreferences(.keys)
            return true
        }
        // The action editor has no buttons to press: its keys are its own.
        guard model.session != nil, model.editingAction == nil else { return false }
        if pinsListOpen, event.type == .keyDown {
            if event.keyCode == UInt16(kVK_Escape) { pinsListOpen = false }
            return true
        }
        if pinsEditing, event.type == .keyDown {
            if event.keyCode == UInt16(kVK_Escape) { finishEditingPins() }
            return true
        }
        if event.type == .flagsChanged {
            state.optionChanged(down: flags.contains(.option))
            return false
        }
        let key = KeyEvent(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
                           modifiers: KeyModifiers(flags), isRepeat: event.isARepeat)
        let effect = state.key(key, assignments: model.assignments, globalAssignments: model.globalAssignments,
                               layout: layout, textInputActive: window.firstResponder is NSText)
        if effect == .pass { return false }
        perform(effect)
        return true
    }

    /// A change of keys that would replace the Custom profile asks first, unless `confirmed`; the
    /// global shortcuts are no part of the profile.
    private func perform(_ effect: KeyModeState.Effect, confirmed: Bool = false) {
        let assignments: KeyAssignments
        switch effect {
        case .none, .pass: return
        case .fire(let id):
            model.press(id)
            return
        case .assignGlobal(let binding, let id):
            assignGlobal(binding, to: id)
            return
        case .swapGlobal(let binding, let id, let owner):
            model.applyGlobals(model.globalAssignments.swapping(binding, to: id, from: owner, layout: layout))
            return
        case .removeGlobal(let id):
            model.applyGlobals(model.globalAssignments.removing(.primary, of: id))
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

    /// A combination another app holds is not kept: the capture waits for another. Pane's own
    /// shortcuts are suspended while it waits, so `isFree` weighs only the other apps'. Once the
    /// combination is free, the capture ends whether or not `assigning` changed anything, as when
    /// the button's own combination is typed again.
    private func assignGlobal(_ binding: KeyBinding, to id: ButtonID) {
        guard model.hotKeys.isFree(binding) else {
            state.globalTaken(binding)
            return
        }
        if case .assigned(let result) = model.globalAssignments.assigning(binding, to: id, layout: layout) {
            model.applyGlobals(result)
        }
        state.globalRecorded()
    }

    // MARK: Clicks

    /// A right-click (or ⌃-click) on a button that can carry a key chooses it in the keys shown, the
    /// TV off too; no menu. The button is found by the `KeyArea` under it, the other clicks pass.
    private func rightClicked(_ event: NSEvent, control: Bool) -> Bool {
        guard event.type == .rightMouseDown || control, !pinsListOpen, !pinsEditing, model.session != nil, model.editingAction == nil,
              let root = window?.contentView, let id = KeyArea.button(at: event.locationInWindow, in: root)
        else { return false }
        state.select(id)
        return true
    }

    /// The footer's keyboard icon: shows the keys, hides them; it ends the pins' edit first.
    func iconClicked() {
        finishEditingPins()
        state.iconClicked()
    }

    /// Edit, next to Pinned: no key mode is left under it.
    func editPins() {
        state.closed()
        pinsListOpen = false
        pinsEditing = true
    }

    /// Done, next to Pinned, or Esc.
    func finishEditingPins() {
        pinsListOpen = false
        pinsEditing = false
    }

    /// The × of the chosen button's bar, or its button clicked again: back to "Click a button to set its keys".
    func deselect() {
        state.deselect()
    }

    /// A button of Remote: its press, or, while the keys show, its choice.
    func buttonClicked(_ id: ButtonID) {
        perform(state.buttonClicked(id))
    }

    /// "Change" in the bar: the next key goes to this button.
    func setKey(for id: ButtonID) {
        state.setKey(for: id)
    }

    /// The action editor opens: no key mode is left under it, ⌥ included (the editor's keys are
    /// its own, so Esc could no longer leave one).
    func leaveKeyModes() {
        state.closed()
    }

    /// "Remove" in the bar: a wait on another row ends first.
    func removeKey(of id: ButtonID) {
        state.select(id)
        perform(.remove(id))
    }

    /// "Change" in the bar: the next combination becomes this button's system-wide shortcut.
    func setGlobal(for id: ButtonID) {
        state.setGlobal(for: id)
    }

    func removeGlobal(of id: ButtonID) {
        state.select(id)
        perform(.removeGlobal(id))
    }

    /// "Cancel" on the row that waits: back to the keys shown, on the same button.
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

    /// The button's global shortcut.
    func globalKey(of id: ButtonID) -> KeyBinding? {
        model.globalAssignments.slots[id]?.primary
    }

    /// The button's global shortcut as the Mac's layout types it; nil without one.
    func globalLabel(for id: ButtonID) -> String? {
        globalKey(of: id).map { KeyLabel.text($0, layout: layout) }
    }

    /// The button awaiting its key or its global shortcut: the global shortcuts are suspended meanwhile.
    var awaitingKey: ButtonID? {
        switch state.mode {
        case .capturing(let id), .capturingGlobal(let id): id
        case .normal, .showing: nil
        }
    }

    /// A button's name, for the bar.
    func title(of id: ButtonID) -> String {
        let inputs = model.session?.stats.map(sources(from:)) ?? []
        let actions = model.store.activeID.map(model.actions.actions(for:)) ?? []
        return id.title(sources: inputs, actions: actions)
    }

    #if DEBUG
    /// Screenshots (-PaneKeys): "show" shows the keys.
    func enterForScreenshot(_ mode: String) {
        if mode == "show" { state.iconClicked() }
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
