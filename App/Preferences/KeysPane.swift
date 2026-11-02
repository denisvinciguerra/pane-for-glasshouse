import PaneKit
import SwiftUI

/// Preferences › Keys: the global shortcuts, then the popover's keys: the profile (Arrows, Gaming,
/// Custom), every key of Remote's buttons and of the active TV's sources (main and alternative), the
/// active TV's actions with their key, and the reset of Custom. A key already taken asks under its
/// row whether to swap; a change made on Arrows or Gaming while a Custom profile exists asks there
/// whether to replace it.
struct KeysPane: View {
    let model: AppModel
    let layout: CurrentKeyboardLayout
    @State private var conflict: PendingKey?
    @State private var replacing: PendingReplacement?
    /// The button or action chosen in « Add a global shortcut… », its row waiting for a combination.
    @State private var draftGlobal: ButtonID?
    /// The row whose combination another app holds: it was not kept.
    @State private var takenGlobal: ButtonID?
    /// The action open in the editor's sheet: a new one is pinned when saved.
    @State private var editing: CustomAction?
    @Environment(\.palette) private var palette

    private static let recorderWidth: CGFloat = 86

    /// A key that `id` would take in `role`, held by `owner`; a global shortcut's in its primary role.
    private struct PendingKey: Equatable {
        let binding: KeyBinding
        let id: ButtonID
        let role: KeySlot.Role
        let owner: ButtonID
        var global = false
    }

    /// The keys after a change on `id` that would replace the Custom profile.
    private struct PendingReplacement: Equatable {
        let id: ButtonID
        let assignments: KeyAssignments
    }

    private var sources: [Source] { model.session?.stats.map(PaneKit.sources(from:)) ?? [] }
    private var activeActions: [CustomAction] { model.store.activeID.map(model.actions.actions(for:)) ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            PreferencesScroll {
                globals
                profile
                remote
                actions
            }
            HStack {
                Spacer()
                GHButton("Reset keys", height: 28) {
                    dropPending()
                    model.keymap.reset()
                }
                .frame(width: 230)
                .disabled(!model.keymap.canReset)
            }
            .padding(.horizontal, PreferencesView.gutter)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Hairline() }
        }
        // A draft and a pending key belong to the TV they were made for, a draft to its action, a
        // pending key to the keys it was weighed against.
        .onChange(of: model.store.activeID) {
            dropPending()
            editing = nil
            draftGlobal = nil
        }
        .onChange(of: activeActions.map(\.id)) { old, new in
            if let id = editing?.id, old.contains(id), !new.contains(id) { editing = nil }
            if let id = draftGlobal?.actionID, !new.contains(id) { draftGlobal = nil }
        }
        .onChange(of: model.assignments) { dropPending() }
        .onChange(of: model.globalAssignments) { dropPending() }
        .onChange(of: model.keymap.choice) { dropPending() }
        .sheet(item: $editing) { action in
            ActionEditorView(model: model, draft: action) { editing = nil }
                .padding(PreferencesView.gutter)
                .frame(width: 380)
                .font(.manrope(11))
                .foregroundStyle(palette.fg)
                .background(palette.bg)
                .environment(\.palette, palette)
                .environment(\.appModel, model)
        }
    }

    // MARK: Global shortcuts

    /// Those set, and a draft row at the end; then the menu that adds one.
    private var globals: some View {
        let slots = model.globalAssignments.slots
        let ids = globalIDs
        let set = ids.filter { slots[$0]?.primary != nil }
        let rows = set + [draftGlobal].compactMap { $0 }.filter { !set.contains($0) }
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Global shortcuts", tint: palette.global)
            PreferencesNote("They work in any app, even with the popover closed. Use ⌘, ⌃ or ⌥.")
                .padding(.bottom, 8)
            ForEach(rows, id: \.self) { id in globalRow(id) }
            addGlobalMenu(ids.filter { slots[$0]?.primary == nil && $0 != draftGlobal })
                .padding(.top, 10)
        }
    }

    /// What can take a global shortcut, in the list's order: the buttons, the sources (the active
    /// TV's, then those of another TV that keep one), the active TV's actions.
    private var globalIDs: [ButtonID] {
        let sourceIDs = sources.map { ButtonID.source($0.id) }
        let others = model.globalAssignments.slots.keys
            .filter { $0.sourceID != nil && !sourceIDs.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
        return ButtonID.globalButtons + sourceIDs + others + activeActions.map { .action($0.id) }
    }

    private func globalRow(_ id: ButtonID) -> some View {
        PreferencesRow {
            // Top-aligned: the recorder's request for a modifier grows the row downwards.
            HStack(alignment: .top, spacing: 10) {
                Text(verbatim: title(of: id))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                KeyRecorder(binding: model.globalAssignments.slots[id]?.primary, layout: layout, global: true) { key in
                    recordGlobal(key, to: id)
                }
                .frame(width: Self.recorderWidth)
                Button("Remove") { removeGlobal(id) }
                    .buttonStyle(TextButtonStyle())
                    .fixedSize()
                    .frame(minHeight: 24)
            }
            .padding(.vertical, 5)
            conflictLine(for: id, global: true)
            if takenGlobal == id {
                globalNote("Another app already uses this shortcut")
            } else if model.hotKeys.inactive.contains(id) {
                if let holder = globalHolder(of: id) {
                    globalNote("Already used by \(title(of: holder))")
                } else {
                    globalNote("Not active: another app uses it")
                }
            }
        }
    }

    /// The id of Pane's that holds the combination `id`'s was refused for: a shared button's,
    /// left on an action of another TV. nil when no active one has it: another app does.
    private func globalHolder(of id: ButtonID) -> ButtonID? {
        let assignments = model.globalAssignments
        guard let binding = assignments.slots[id]?.primary,
              let owner = assignments.owner(of: binding, layout: layout, except: id),
              !model.hotKeys.inactive.contains(owner) else { return nil }
        return owner
    }

    private func globalNote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.manrope(10))
            .foregroundStyle(palette.label)
            .padding(.bottom, 8)
    }

    /// Two sections, the buttons and sources then the active TV's actions, of what has no global
    /// shortcut yet. The choice adds a draft row.
    private func addGlobalMenu(_ available: [ButtonID]) -> some View {
        let buttons = available.filter { $0.actionID == nil }
        let actions = available.filter { $0.actionID != nil }
        return Menu {
            if !buttons.isEmpty {
                Section("Buttons") { ForEach(buttons, id: \.self) { addGlobalChoice($0) } }
            }
            if !actions.isEmpty {
                Section("Actions") { ForEach(actions, id: \.self) { addGlobalChoice($0) } }
            }
        } label: {
            Text("+ Add a global shortcut…")
                .textCase(.uppercase)
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .font(.manrope(10))
                .foregroundStyle(palette.global)
                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        // The edge is drawn outside the menu: the menu styles replace a label's own chrome.
        .overlay(Rectangle().strokeBorder(palette.global.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            .allowsHitTesting(false))
        .disabled(available.isEmpty)
    }

    private func addGlobalChoice(_ id: ButtonID) -> some View {
        Button {
            dropPending()
            draftGlobal = id
        } label: {
            Text(verbatim: title(of: id))
        }
    }

    /// nil clears the shortcut. A combination another app holds is not kept; one held by another
    /// button waits under the row for Swap or Cancel. Pane's own shortcuts are suspended while the
    /// recorder waits, so `isFree` weighs only the other apps': Pane's are weighed by `assigning`.
    private func recordGlobal(_ key: KeyBinding?, to id: ButtonID) {
        dropPending()
        let assignments = model.globalAssignments
        guard let key else {
            model.applyGlobals(assignments.removing(.primary, of: id))
            return
        }
        guard model.hotKeys.isFree(key) else {
            takenGlobal = id
            return
        }
        switch assignments.assigning(key, to: id, layout: layout) {
        case .assigned(let result): applyGlobals(result, to: id)
        case .conflict(let owner): conflict = PendingKey(binding: key, id: id, role: .primary, owner: owner, global: true)
        }
    }

    /// Stores the shortcuts, `id` having one: its draft row becomes an ordinary one.
    private func applyGlobals(_ assignments: KeyAssignments, to id: ButtonID) {
        if draftGlobal == id { draftGlobal = nil }
        model.applyGlobals(assignments)
    }

    private func removeGlobal(_ id: ButtonID) {
        dropPending()
        if draftGlobal == id { draftGlobal = nil }
        model.applyGlobals(model.globalAssignments.removing(.primary, of: id))
    }

    // MARK: Profile

    private var profile: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Profile · popover open")
            HStack(spacing: 6) {
                ForEach(KeyProfile.allCases, id: \.self) { profile in
                    GHButton(profile.title, selected: model.keymap.choice == .profile(profile), height: 30) {
                        dropPending()
                        model.keymap.choose(.profile(profile))
                    }
                }
                GHButton("Custom", selected: model.keymap.choice == .custom, height: 30) {
                    dropPending()
                    model.keymap.choose(.custom)
                }
                .disabled(model.keymap.custom == nil)
            }
            if model.keymap.choice == .custom, let base = model.keymap.custom?.base {
                Text("Based on \(base.name)")
                    .font(.manrope(10.5))
                    .foregroundStyle(palette.label)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: Remote

    private var remote: some View {
        let ids = ButtonID.remote + sources.map { ButtonID.source($0.id) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Remote").frame(maxWidth: .infinity, alignment: .leading)
                Text("Key").frame(width: Self.recorderWidth)
                Text("Alternative").frame(width: Self.recorderWidth)
            }
            .sectionLabelStyle()
            .padding(.bottom, 7)
            ForEach(ids, id: \.self) { id in
                PreferencesRow {
                    HStack(spacing: 10) {
                        Text(verbatim: title(of: id))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        recorder(id, .primary)
                        recorder(id, .alternate)
                    }
                    .frame(minHeight: 34)
                    conflictLine(for: id)
                    replaceLine(for: id)
                }
            }
        }
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Actions", trailing: model.store.active?.name)
            if let tv = model.store.activeID {
                ForEach(model.actions.actions(for: tv)) { action in
                    PreferencesRow {
                        HStack(spacing: 10) {
                            Text(verbatim: action.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            recorder(.action(action.id), .primary)
                            HStack(spacing: 10) {
                                Button("Edit") {
                                    dropPending()
                                    editing = action
                                }
                                if !model.actions.isPinned(action.id, for: tv) {
                                    Button("Pin") { model.pin(action.id) }
                                }
                                Button("Delete") {
                                    dropPending()
                                    model.deleteAction(action.id)
                                }
                            }
                            .buttonStyle(TextButtonStyle())
                            .fixedSize()
                        }
                        .frame(minHeight: 34)
                        conflictLine(for: .action(action.id))
                        replaceLine(for: .action(action.id))
                    }
                }
                GHButton("New action", dashed: true, height: 28) {
                    dropPending()
                    editing = CustomAction(title: "", steps: [])
                }
                .padding(.top, 10)
            } else {
                PreferencesNote("Connect a TV first")
            }
        }
    }

    // MARK: Recording

    private func recorder(_ id: ButtonID, _ role: KeySlot.Role) -> some View {
        let slot = model.assignments.slots[id]
        return KeyRecorder(binding: role == .primary ? slot?.primary : slot?.alternate, layout: layout) { key in
            record(key, to: id, role: role)
        }
        .frame(width: Self.recorderWidth)
    }

    /// nil clears the key; a key held by another button waits under the row for Swap or Cancel.
    private func record(_ key: KeyBinding?, to id: ButtonID, role: KeySlot.Role) {
        dropPending()
        let assignments = model.assignments
        guard let key else {
            commit(assignments.removing(role, of: id), for: id)
            return
        }
        switch assignments.assigning(key, to: id, role: role, layout: layout) {
        case .assigned(let result): commit(result, for: id)
        case .conflict(let owner): conflict = PendingKey(binding: key, id: id, role: role, owner: owner)
        }
    }

    /// Applies the keys, unless they would replace the Custom profile: then they wait under the row.
    private func commit(_ assignments: KeyAssignments, for id: ButtonID) {
        if model.replacesCustom(assignments) {
            replacing = PendingReplacement(id: id, assignments: assignments)
        } else {
            model.apply(assignments)
        }
    }

    private func dropPending() {
        conflict = nil
        replacing = nil
        takenGlobal = nil
    }

    /// `global`: under a global shortcut's row, a button's row being able to show both.
    @ViewBuilder private func conflictLine(for id: ButtonID, global: Bool = false) -> some View {
        if let pending = conflict, pending.id == id, pending.global == global {
            HStack(spacing: 10) {
                Text(verbatim: KeyLabel.text(pending.binding, layout: layout))
                    .fontWeight(.semibold)
                // Two keys: in French, a shortcut (« raccourci ») is masculine and a key feminine.
                Text(global ? LocalizedStringKey("Shortcut used by \(title(of: pending.owner))")
                            : LocalizedStringKey("Used by \(title(of: pending.owner))"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button("Swap") {
                    conflict = nil
                    if pending.global {
                        applyGlobals(model.globalAssignments.swapping(pending.binding, to: pending.id, from: pending.owner,
                                                                      layout: layout), to: pending.id)
                    } else {
                        commit(model.assignments.swapping(pending.binding, to: pending.id, from: pending.owner,
                                                          role: pending.role, layout: layout), for: pending.id)
                    }
                }
                .fontWeight(.semibold)
                Button("Cancel") { conflict = nil }
            }
            .pendingLineStyle(palette)
        }
    }

    @ViewBuilder private func replaceLine(for id: ButtonID) -> some View {
        if let pending = replacing, pending.id == id {
            HStack(spacing: 10) {
                Text("Replace your Custom profile?")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button("Replace") {
                    replacing = nil
                    model.apply(pending.assignments)
                }
                .fontWeight(.semibold)
                Button("Cancel") { replacing = nil }
            }
            .pendingLineStyle(palette)
        }
    }

    private func title(of id: ButtonID) -> String {
        id.title(sources: sources, actions: activeActions)
    }
}

private extension View {
    /// A question waiting under a row: amber, on a faint amber band.
    func pendingLineStyle(_ palette: Palette) -> some View {
        buttonStyle(.plain)
            .font(.manrope(10))
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(palette.accent.opacity(0.08))
            .padding(.bottom, 8)
    }
}

private extension KeyProfile {
    var title: LocalizedStringKey {
        switch self {
        case .arrows: "Arrows"
        case .gaming: "Gaming"
        }
    }

    var name: String {
        switch self {
        case .arrows: String(localized: "Arrows")
        case .gaming: String(localized: "Gaming")
        }
    }
}
