import PaneKit
import SwiftUI

/// Preferences › Keys: the profile (Arrows, Gaming, Custom), every key of Remote's buttons and of
/// the active TV's sources (main and alternative), the active TV's actions with their key, and the
/// reset of Custom. A key already taken asks under its row whether to swap; a change made on Arrows
/// or Gaming while a Custom profile exists asks there whether to replace it.
struct KeysPane: View {
    let model: AppModel
    let layout: CurrentKeyboardLayout
    @State private var conflict: PendingKey?
    @State private var replacing: PendingReplacement?
    /// The action open in the editor's sheet: a new one is pinned when saved.
    @State private var editing: CustomAction?
    @Environment(\.palette) private var palette

    private static let recorderWidth: CGFloat = 86

    /// A key that `id` would take in `role`, held by `owner`.
    private struct PendingKey: Equatable {
        let binding: KeyBinding
        let id: ButtonID
        let role: KeySlot.Role
        let owner: ButtonID
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
        }
        .onChange(of: activeActions.map(\.id)) { old, new in
            if let id = editing?.id, old.contains(id), !new.contains(id) { editing = nil }
        }
        .onChange(of: model.assignments) { dropPending() }
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

    // MARK: Profile

    private var profile: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Profile")
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
    }

    @ViewBuilder private func conflictLine(for id: ButtonID) -> some View {
        if let pending = conflict, pending.id == id {
            HStack(spacing: 10) {
                Text(verbatim: KeyLabel.text(pending.binding, layout: layout))
                    .fontWeight(.semibold)
                Text("Used by \(title(of: pending.owner))")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button("Swap") {
                    conflict = nil
                    commit(model.assignments.swapping(pending.binding, to: pending.id, from: pending.owner,
                                                      role: pending.role, layout: layout), for: pending.id)
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
