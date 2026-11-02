import PaneKit
import SwiftUI

/// The bar under the footer while the keys show. With no button chosen, what to do and Done; with
/// one, a white line over it, the button's name and a × that closes it (the keys stay shown), then a
/// row for its popover key (a white chip) and one for its global shortcut (a blue chip), each with
/// Change (Set without one) and Remove, and for a pinned action a row to unpin or edit it. While a
/// row awaits, its chip shows "?" (amber for the key, blue for the shortcut) and under it the
/// instruction, why a combination was not taken, the offer to swap, or, for the key, the question
/// about the Custom profile.
struct KeysBar: View {
    let model: AppModel
    let keyboard: KeyboardController
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if let id = keyboard.state.selected { chosen(id) } else { prompt }
        }
        .buttonStyle(.plain)
        .font(.manrope(11))
    }

    private var prompt: some View {
        HStack(spacing: 12) {
            Text("Click a button to set its keys")
                .foregroundStyle(palette.label)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Done") { keyboard.iconClicked() }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { Hairline() }
    }

    private func chosen(_ id: ButtonID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(verbatim: keyboard.title(of: id))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button { keyboard.deselect() } label: {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .help(Text("Close"))
                .accessibilityLabel(Text("Close"))
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
                row(.key, of: id)
                Hairline()
                row(.global, of: id)
            }
            if let action = pinned(id) {
                Hairline()
                HStack(spacing: 14) {
                    Button("Edit Action…") {
                        keyboard.leaveKeyModes()
                        model.edit(action)
                    }
                    .fontWeight(.semibold)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.fg.opacity(0.04))
        .overlay(alignment: .top) { Rectangle().fill(palette.fg).frame(height: 1) }
    }

    private enum Kind { case key, global }

    /// The row's name, its chip, then Change (Set) and Remove; Cancel alone while it awaits, nothing
    /// while a swap or a replacement asks. Under it, its message while it awaits or asks.
    @ViewBuilder private func row(_ kind: Kind, of id: ButtonID) -> some View {
        let state = keyboard.state
        let global = kind == .global
        let awaiting = state.mode == (global ? KeyMode.capturingGlobal(id) : .capturing(id))
        let label = global ? keyboard.globalLabel(for: id) : keyboard.label(for: id)
        let tint = global ? palette.global : palette.accent
        let note = message(kind, awaiting: awaiting)
        let name: LocalizedStringKey = global ? "Global shortcut" : "Popover key"
        let none: LocalizedStringKey = global ? "shortcut.none" : "key.none"
        GridRow {
            Text(name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            Chip(text: awaiting ? "?" : label, fill: awaiting || global ? tint : palette.fg, none: none)
                .gridColumnAlignment(.center)
            if note?.asks == true {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            } else if awaiting {
                Button("Cancel") { keyboard.done() }
                    .fontWeight(.semibold)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            } else {
                Button(label == nil ? "Set" : "Change") {
                    if global { keyboard.setGlobal(for: id) } else { keyboard.setKey(for: id) }
                }
                .fontWeight(.semibold)
                if label != nil {
                    Button("Remove") {
                        if global { keyboard.removeGlobal(of: id) } else { keyboard.removeKey(of: id) }
                    }
                    .foregroundStyle(palette.label)
                } else {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
            }
        }
        if let note {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: note.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if state.replacing != nil {
                    Button("Replace") { keyboard.resolveReplacement(replace: true) }
                        .fontWeight(.semibold)
                    Button("Cancel") { keyboard.resolveReplacement(replace: false) }
                } else if state.conflict != nil {
                    Button("Swap") { keyboard.resolveConflict(swap: true) }
                        .fontWeight(.semibold)
                    Button("Cancel") { keyboard.resolveConflict(swap: false) }
                }
            }
            .foregroundStyle(state.replacing != nil ? palette.accent : tint)
            .padding(.bottom, 8)
        }
    }

    /// What the row says under it: the question about the Custom profile (the key's row), the
    /// conflict, why a combination was not taken, else what to press. `asks`: it carries its buttons.
    private func message(_ kind: Kind, awaiting: Bool) -> (text: String, asks: Bool)? {
        let state = keyboard.state
        if state.replacing != nil {
            return kind == .key ? (String(localized: "Replace your Custom profile?"), true) : nil
        }
        guard awaiting else { return nil }
        if let conflict = state.conflict {
            let key = KeyLabel.text(conflict.binding, layout: keyboard.layout)
            let owner = keyboard.title(of: conflict.owner)
            return (conflict.global ? String(localized: "\(key) is \(owner)'s global shortcut")
                                    : String(localized: "\(key) is \(owner)'s key"), true)
        }
        switch state.globalNotice {
        case .needsModifier(let binding):
            let key = KeyLabel.text(binding, layout: keyboard.layout)
            return (String(localized: "\(key) alone isn't enough: add ⌘, ⌃ or ⌥"), false)
        case .takenByAnotherApp(let binding):
            let key = KeyLabel.text(binding, layout: keyboard.layout)
            return (String(localized: "Another app already uses \(key)"), false)
        case nil:
            return (kind == .global ? String(localized: "Press ⌘, ⌃ or ⌥ + a key") : String(localized: "Press a key"), false)
        }
    }

    /// The pinned action the chosen button is, for its third row.
    private func pinned(_ id: ButtonID) -> CustomAction? {
        guard let actionID = id.actionID, let tv = model.store.activeID else { return nil }
        return model.actions.pinned(for: tv).first { $0.id == actionID }
    }
}

/// A row's key or shortcut on its colour, or a dashed "none" without one.
struct Chip: View {
    let text: String?
    let fill: Color
    let none: LocalizedStringKey
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if let text {
                Text(verbatim: text)
                    .fontWeight(.bold)
                    .foregroundStyle(palette.bg)
            } else {
                Text(none)
                    .foregroundStyle(palette.label)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 5)
        .frame(minWidth: 26, minHeight: 20, maxHeight: 20)
        .background(text == nil ? .clear : fill)
        .overlay {
            if text == nil {
                Rectangle().strokeBorder(palette.label, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
    }
}

extension KeyModeState {
    /// The keys show, a button chosen or not, a key or a shortcut awaited or not: the bar is up.
    var keysShown: Bool { mode != .normal }

    /// A key is being set after "Change", or a global shortcut.
    var setsKeys: Bool {
        switch mode {
        case .capturing, .capturingGlobal: true
        case .normal, .showing: false
        }
    }

    /// A global shortcut is being set and nothing is being replaced: the keys icon is blue. A
    /// question about the Custom profile keeps the amber.
    var setsGlobal: Bool {
        if case .capturingGlobal = mode, replacing == nil { true } else { false }
    }
}
