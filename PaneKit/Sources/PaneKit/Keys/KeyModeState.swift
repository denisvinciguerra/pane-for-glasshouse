import Foundation

public enum KeyMode: Equatable, Sendable {
    case normal
    case showing(selected: ButtonID?)  // icon click: tiles, a button may be selected; nothing is sent
    case capturing(ButtonID)           // "Change" on the key's row: one key for one button, from the keys shown
    case capturingGlobal(ButtonID)     // "Change" on the shortcut's row: one system-wide combination for one button
}

/// Why a combination typed for a global shortcut was not taken: the capture keeps waiting.
public enum GlobalNotice: Equatable, Sendable {
    /// The key came without ⌘, ⌃ or ⌥ (carried as typed, by key position, to say "P alone is not enough").
    case needsModifier(KeyBinding)
    /// Another app already holds the combination.
    case takenByAnotherApp(KeyBinding)
}

public struct KeyConflict: Equatable, Sendable {
    public let binding: KeyBinding
    public let target: ButtonID
    public let owner: ButtonID
    /// The conflict is between global shortcuts: Swap exchanges those, not the popover's keys.
    public let global: Bool
    public init(binding: KeyBinding, target: ButtonID, owner: ButtonID, global: Bool = false) {
        self.binding = binding; self.target = target; self.owner = owner; self.global = global
    }
}

/// Pure state machine for the key modes; the caller applies the returned effects.
public struct KeyModeState: Equatable, Sendable {
    public private(set) var mode: KeyMode = .normal
    public private(set) var optionHeld = false
    public private(set) var conflict: KeyConflict?
    /// A change that would replace the Custom profile, waiting for Replace or Cancel.
    public private(set) var replacing: Effect?
    /// Set while a global capture waits, after a combination it could not take.
    public private(set) var globalNotice: GlobalNotice?
    /// The last key pressed (not a repeat) and what came of it: its repeats follow it.
    private var lastPress: Press?

    private struct Press: Equatable, Sendable {
        enum Outcome: Equatable, Sendable { case fired(ButtonID), passed, consumed }
        let keyCode: UInt16
        let outcome: Outcome
    }

    public var showsTiles: Bool { mode != .normal || optionHeld }
    public var sendsCommands: Bool { mode == .normal }

    /// The button chosen in the keys shown, or the one a capture waits for.
    public var selected: ButtonID? {
        switch mode {
        case .normal: nil
        case .showing(let id): id
        case .capturing(let id), .capturingGlobal(let id): id
        }
    }

    public enum Effect: Equatable, Sendable {
        case none, pass, fire(ButtonID)
        case assign(KeyBinding, to: ButtonID)
        case swap(KeyBinding, to: ButtonID, from: ButtonID)
        case remove(ButtonID)
        case assignGlobal(KeyBinding, to: ButtonID)
        case swapGlobal(KeyBinding, to: ButtonID, from: ButtonID)
        case removeGlobal(ButtonID)
    }

    public init() {}

    public mutating func iconClicked() {
        conflict = nil
        replacing = nil
        globalNotice = nil
        mode = mode == .normal ? .showing(selected: nil) : .normal
    }

    /// Right click, or a click while the keys are shown: this button is the one to set. A capture in progress
    /// is abandoned.
    public mutating func select(_ id: ButtonID) {
        conflict = nil
        replacing = nil
        globalNotice = nil
        mode = .showing(selected: id)
    }

    /// Closes the chosen button's bar, a capture included: the keys stay shown, no button chosen.
    public mutating func deselect() {
        guard mode != .normal else { return }
        conflict = nil
        replacing = nil
        globalNotice = nil
        mode = .showing(selected: nil)
    }

    public mutating func optionChanged(down: Bool) { optionHeld = down }

    public mutating func buttonClicked(_ id: ButtonID) -> Effect {
        if mode == .normal {
            replacing = nil
            return .fire(id)
        }
        if selected == id {   // the chosen button again (or the one that waits): its bar closes
            deselect()
        } else {
            select(id)
        }
        return .none
    }

    /// Out of the capture, back to the keys shown, dropping what waits (as Esc, at once).
    public mutating func done() {
        conflict = nil
        replacing = nil
        globalNotice = nil
        if let id = selected { mode = .showing(selected: id) }
    }

    public mutating func setKey(for id: ButtonID) {
        conflict = nil
        replacing = nil
        globalNotice = nil
        mode = .capturing(id)
    }

    /// "Change" on the shortcut's row: the next combination typed is a system-wide shortcut for this button.
    public mutating func setGlobal(for id: ButtonID) {
        conflict = nil
        replacing = nil
        globalNotice = nil
        mode = .capturingGlobal(id)
    }

    /// The caller registered the combination `.assignGlobal` gave: the capture is over, the keys stay shown.
    public mutating func globalRecorded() {
        guard case .capturingGlobal(let id) = mode else { return }
        globalNotice = nil
        mode = .showing(selected: id)
    }

    /// Another app holds the combination `.assignGlobal` gave: the capture keeps waiting for another.
    public mutating func globalTaken(_ binding: KeyBinding) {
        guard case .capturingGlobal = mode else { return }
        globalNotice = .takenByAnotherApp(binding)
    }

    /// A repeat follows its press: it fires again only a fired button that repeats, passes only a
    /// passed key, and is swallowed otherwise (a held key after "Change" sends nothing).
    public mutating func key(_ event: KeyEvent, assignments: KeyAssignments, globalAssignments: KeyAssignments,
                             layout: some KeyboardLayout, textInputActive: Bool) -> Effect {
        if event.isRepeat { return repeated(event, assignments: assignments, textInputActive: textInputActive) }
        let effect = pressed(event, assignments: assignments, globalAssignments: globalAssignments,
                             layout: layout, textInputActive: textInputActive)
        let outcome: Press.Outcome = switch effect {
        case .fire(let id): .fired(id)
        case .pass: .passed
        case .none, .assign, .swap, .remove, .assignGlobal, .swapGlobal, .removeGlobal: .consumed
        }
        lastPress = Press(keyCode: event.keyCode, outcome: outcome)
        return effect
    }

    private func repeated(_ event: KeyEvent, assignments: KeyAssignments, textInputActive: Bool) -> Effect {
        if replacing != nil { return .none }
        switch mode {
        case .capturing, .capturingGlobal, .showing: return .none
        case .normal: break
        }
        if textInputActive { return .pass }
        if let lastPress, lastPress.keyCode == event.keyCode {
            switch lastPress.outcome {
            case .passed: return .pass
            case .consumed: return .none
            case .fired(let id): return assignments.button(for: event) == id ? .fire(id) : .none
            }
        }
        // Held since before its press reached us: a key of a button is swallowed all the same.
        let press = KeyEvent(keyCode: event.keyCode, characters: event.characters, modifiers: event.modifiers)
        return assignments.button(for: press) == nil ? .pass : .none
    }

    private mutating func pressed(_ event: KeyEvent, assignments: KeyAssignments, globalAssignments: KeyAssignments,
                                  layout: some KeyboardLayout, textInputActive: Bool) -> Effect {
        // While asking, the keys wait; Esc cancels (it is not Back then).
        if replacing != nil {
            if event.keyCode == KeyCode.escape, event.modifiers.isEmpty { replacing = nil }
            return .none
        }
        if event.keyCode == KeyCode.escape, event.modifiers.isEmpty {
            switch mode {
            case .capturing(let id):
                if conflict != nil { conflict = nil } else { mode = .showing(selected: id) }
                return .none
            case .showing(let selected):
                mode = selected == nil ? .normal : .showing(selected: nil)
                return .none
            case .capturingGlobal, .normal: break
            }
        }
        switch mode {
        case .capturingGlobal(let id):
            return globalPressed(event, id: id, globalAssignments: globalAssignments, layout: layout)
        case .capturing(let id):
            guard conflict == nil, let binding = KeyBinding.recorded(event) else { return .none }
            switch assignments.assigning(binding, to: id, layout: layout) {
            case .conflict(let owner):
                conflict = KeyConflict(binding: binding, target: id, owner: owner)
                return .none
            case .assigned:
                mode = .showing(selected: id)
                return .assign(binding, to: id)
            }
        case .showing:
            return .none   // the keys are shown, not pressed
        case .normal:
            if textInputActive { return .pass }
            return assignments.button(for: event).map(Effect.fire) ?? .pass
        }
    }

    /// A key during the global capture: `GlobalKey.input` decides, the same rules as in Settings.
    private mutating func globalPressed(_ event: KeyEvent, id: ButtonID, globalAssignments: KeyAssignments,
                                        layout: some KeyboardLayout) -> Effect {
        globalNotice = nil
        let recording = GlobalKey.input(event)
        if recording == .cancel {
            if conflict != nil { conflict = nil } else { mode = .showing(selected: id) }
            return .none
        }
        guard conflict == nil else { return .none }   // Swap or Cancel first
        switch recording {
        case .cancel, .ignore: return .none
        case .clear:
            mode = .showing(selected: id)
            return .removeGlobal(id)
        case .needsModifier:
            globalNotice = .needsModifier(KeyBinding(.keyCode(event.keyCode), modifiers: event.modifiers))
            return .none
        case .record(let binding):
            switch globalAssignments.assigning(binding, to: id, layout: layout) {
            case .conflict(let owner):
                conflict = KeyConflict(binding: binding, target: id, owner: owner, global: true)
                return .none
            case .assigned:
                return .assignGlobal(binding, to: id)   // the capture ends on `globalRecorded()`
            }
        }
    }

    public mutating func resolveConflict(swap: Bool) -> Effect {
        guard let pending = conflict else { return .none }
        conflict = nil
        guard swap else { return .none }
        mode = .showing(selected: pending.target)
        if pending.global { return .swapGlobal(pending.binding, to: pending.target, from: pending.owner) }
        return .swap(pending.binding, to: pending.target, from: pending.owner)
    }

    /// The change would replace the Custom profile: it waits for `resolveReplacement`.
    public mutating func askToReplace(_ effect: Effect) {
        conflict = nil
        replacing = effect
    }

    /// Replace: the change that waited, to apply; Cancel: nothing.
    public mutating func resolveReplacement(replace: Bool) -> Effect {
        guard let pending = replacing else { return .none }
        replacing = nil
        return replace ? pending : .none
    }

    public mutating func closed() { self = KeyModeState() }
}
