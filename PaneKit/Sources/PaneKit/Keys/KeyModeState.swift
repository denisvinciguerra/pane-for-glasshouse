import Foundation

public enum KeyMode: Equatable, Sendable {
    case normal
    case showing                       // icon click: tiles until the next click
    case editing(awaiting: ButtonID?)  // ⌥-click: each click picks a button, which then awaits its key
    case capturing(ButtonID)           // "Set Key…": one key for one button
}

public struct KeyConflict: Equatable, Sendable {
    public let binding: KeyBinding
    public let target: ButtonID
    public let owner: ButtonID
    public init(binding: KeyBinding, target: ButtonID, owner: ButtonID) {
        self.binding = binding; self.target = target; self.owner = owner
    }
}

/// Pure state machine for the key modes; the caller applies the returned effects.
public struct KeyModeState: Equatable, Sendable {
    public private(set) var mode: KeyMode = .normal
    public private(set) var optionHeld = false
    public private(set) var conflict: KeyConflict?
    /// A change that would replace the Custom profile, waiting for Replace or Cancel.
    public private(set) var replacing: Effect?
    /// The last key pressed (not a repeat) and what came of it: its repeats follow it.
    private var lastPress: Press?

    private struct Press: Equatable, Sendable {
        enum Outcome: Equatable, Sendable { case fired(ButtonID), passed, consumed }
        let keyCode: UInt16
        let outcome: Outcome
    }

    public var showsTiles: Bool { mode != .normal || optionHeld }
    public var sendsCommands: Bool { mode == .normal || mode == .showing }

    public enum Effect: Equatable, Sendable {
        case none, pass, fire(ButtonID)
        case assign(KeyBinding, to: ButtonID)
        case swap(KeyBinding, to: ButtonID, from: ButtonID)
        case remove(ButtonID)
    }

    public init() {}

    public mutating func iconClicked(option: Bool) {
        if option { editAll(); return }
        conflict = nil
        replacing = nil
        mode = mode == .normal ? .showing : .normal
    }

    /// ⌥-click on the icon, or "Edit" in the bar while the keys show: every button awaits a click.
    public mutating func editAll() {
        conflict = nil
        replacing = nil
        mode = .editing(awaiting: nil)
    }

    public mutating func optionChanged(down: Bool) { optionHeld = down }

    public mutating func buttonClicked(_ id: ButtonID) -> Effect {
        replacing = nil
        switch mode {
        case .editing: conflict = nil; mode = .editing(awaiting: id); return .none
        case .capturing: conflict = nil; mode = .capturing(id); return .none
        case .normal, .showing: return .fire(id)
        }
    }

    /// "Done" in the edit bar: out of the edit mode or the capture, dropping what waits (as Esc, at once).
    public mutating func done() {
        conflict = nil
        replacing = nil
        mode = .normal
    }

    public mutating func setKey(for id: ButtonID) {
        conflict = nil
        replacing = nil
        mode = .capturing(id)
    }

    /// A repeat follows its press: it fires again only a fired button that repeats, passes only a
    /// passed key, and is swallowed otherwise (a held key after "Set Key…" sends nothing).
    public mutating func key(_ event: KeyEvent, assignments: KeyAssignments, layout: some KeyboardLayout,
                             textInputActive: Bool) -> Effect {
        if event.isRepeat { return repeated(event, assignments: assignments, textInputActive: textInputActive) }
        let effect = pressed(event, assignments: assignments, layout: layout, textInputActive: textInputActive)
        let outcome: Press.Outcome = switch effect {
        case .fire(let id): .fired(id)
        case .pass: .passed
        case .none, .assign, .swap, .remove: .consumed
        }
        lastPress = Press(keyCode: event.keyCode, outcome: outcome)
        return effect
    }

    private func repeated(_ event: KeyEvent, assignments: KeyAssignments, textInputActive: Bool) -> Effect {
        if replacing != nil { return .none }
        switch mode {
        case .editing, .capturing: return .none
        case .normal, .showing: break
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

    private mutating func pressed(_ event: KeyEvent, assignments: KeyAssignments, layout: some KeyboardLayout,
                                  textInputActive: Bool) -> Effect {
        // While asking, the keys wait; Esc cancels (it is not Back then).
        if replacing != nil {
            if event.keyCode == KeyCode.escape, event.modifiers.isEmpty { replacing = nil }
            return .none
        }
        if event.keyCode == KeyCode.escape, event.modifiers.isEmpty {
            switch mode {
            case .editing, .capturing:
                if conflict != nil { conflict = nil } else { mode = .normal }
                return .none
            case .normal, .showing: break
            }
        }
        switch mode {
        case .editing(awaiting: nil): return .none
        case .editing(awaiting: let id?), .capturing(let id):
            guard conflict == nil, let binding = KeyBinding.recorded(event) else { return .none }
            switch assignments.assigning(binding, to: id, layout: layout) {
            case .conflict(let owner):
                conflict = KeyConflict(binding: binding, target: id, owner: owner)
                return .none
            case .assigned:
                finishAssignment()
                return .assign(binding, to: id)
            }
        case .normal, .showing:
            if textInputActive { return .pass }
            return assignments.button(for: event).map(Effect.fire) ?? .pass
        }
    }

    public mutating func resolveConflict(swap: Bool) -> Effect {
        guard let pending = conflict else { return .none }
        conflict = nil
        guard swap else { return .none }
        finishAssignment()
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

    private mutating func finishAssignment() {
        if case .editing = mode { mode = .editing(awaiting: nil) } else { mode = .normal }
    }
}
