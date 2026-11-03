import PaneKit
import SwiftUI
import UIKit

/// The keys of the iPad's keyboard, in the settings: every key of Remote's buttons and of the
/// active TV's sources (main and alternative), then the active TV's actions with their key, and
/// the reset of Custom. As in the Mac's Preferences › Keys: a tap on a key's box waits for a key of
/// the hardware keyboard (⎋ cancels, ⌫ clears, a tap on the box again cancels); a key already taken
/// asks under its row whether to swap; a change made on Arrows or Gaming while a Custom profile
/// exists asks there whether to replace it, and otherwise makes Custom from that profile.
struct KeysList: View {
    let model: AppModel
    let keyboard: KeyboardController
    /// The box waiting for a key.
    @State private var recording: Slot?
    @State private var conflict: PendingKey?
    @State private var replacing: PendingReplacement?
    @Environment(\.palette) private var palette

    private static let recorderWidth: CGFloat = 96

    /// A button's key, main or alternative.
    private struct Slot: Equatable {
        let id: ButtonID
        let role: KeySlot.Role
    }

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
    private var activeActions: [CustomAction] { model.activeID.map(model.actions.actions(for:)) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            remote
            actions
            SettingsNote("Tap a box, then press a key. Tap it again to cancel; ⌫ clears it.")
                .padding(.top, 10)
            GHButton("Reset keys") {
                dropPending()
                model.keymap.reset()
            }
            .disabled(!model.keymap.canReset)
            .padding(.top, 12)
        }
        .background {
            KeyCapture(active: recording != nil) { key in captured(key) } lost: {
                if recording != nil { recording = nil }
            }
        }
        // A pending key belongs to the keys it was weighed against, and to the TV it was made for.
        .onChange(of: model.assignments) { dropPending() }
        .onChange(of: model.keymap.choice) { dropPending() }
        .onChange(of: model.activeID) {
            dropPending()
            recording = nil
        }
    }

    // MARK: Rows

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
                row(id, roles: [.primary, .alternate])
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if !activeActions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Actions", trailing: model.activeTV?.name)
                ForEach(activeActions) { action in
                    row(.action(action.id), roles: [.primary])
                }
            }
            .padding(.top, 22)
        }
    }

    private func row(_ id: ButtonID, roles: [KeySlot.Role]) -> some View {
        PreferencesRow {
            HStack(spacing: 10) {
                Text(verbatim: title(of: id))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(roles, id: \.self) { role in recorder(Slot(id: id, role: role)) }
            }
            .padding(.vertical, 4)
            conflictLine(for: id)
            replaceLine(for: id)
        }
    }

    /// A key in a ruled box, dashed without one, amber with « ? » while it waits.
    private func recorder(_ slot: Slot) -> some View {
        let keys = model.assignments.slots[slot.id]
        let binding = slot.role == .primary ? keys?.primary : keys?.alternate
        let label = binding.map { KeyLabel.text($0, layout: keyboard.layout) }
        let waiting = recording == slot
        return Button {
            dropPending()
            recording = waiting ? nil : slot
        } label: {
            Text(verbatim: waiting ? "?" : label ?? "·")
                .font(.manrope(11, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(waiting ? palette.accent : label == nil ? palette.label : palette.fg)
                .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
                .background(waiting ? palette.accent.opacity(0.08) : .clear)
                .overlay(Rectangle().strokeBorder(waiting ? palette.accent : palette.line,
                                                  style: StrokeStyle(lineWidth: 1, dash: label == nil && !waiting ? [2, 2] : [])))
                .frame(minHeight: Metrics.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: Self.recorderWidth)
        .accessibilityLabel(Text(verbatim: "\(title(of: slot.id)) · \(label ?? "–")"))
    }

    // MARK: Recording

    /// A key of the hardware keyboard while a box waits: every key is the recorder's, none reaches
    /// the TV. A modifier alone keeps it waiting.
    private func captured(_ key: UIKey) -> Bool {
        guard let slot = recording, let event = KeyEvent(key) else { return false }
        keyboard.learn(keyCode: event.keyCode, characters: key.charactersIgnoringModifiers)
        switch KeyRecording.input(event) {
        case .ignore: return true
        case .cancel: break
        case .clear: record(nil, to: slot)
        case .record(let binding): record(binding, to: slot)
        }
        recording = nil
        return true
    }

    /// nil clears the key; a key held by another button waits under the row for Swap or Cancel.
    private func record(_ key: KeyBinding?, to slot: Slot) {
        dropPending()
        let assignments = model.assignments
        guard let key else {
            commit(assignments.removing(slot.role, of: slot.id), for: slot.id)
            return
        }
        switch assignments.assigning(key, to: slot.id, role: slot.role, layout: keyboard.layout) {
        case .assigned(let result): commit(result, for: slot.id)
        case .conflict(let owner): conflict = PendingKey(binding: key, id: slot.id, role: slot.role, owner: owner)
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

    // MARK: Questions

    @ViewBuilder private func conflictLine(for id: ButtonID) -> some View {
        if let pending = conflict, pending.id == id {
            HStack(spacing: 14) {
                Text(verbatim: KeyLabel.text(pending.binding, layout: keyboard.layout))
                    .fontWeight(.semibold)
                Text("Used by \(title(of: pending.owner))")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button("Swap") {
                    conflict = nil
                    commit(model.assignments.swapping(pending.binding, to: pending.id, from: pending.owner,
                                                      role: pending.role, layout: keyboard.layout), for: pending.id)
                }
                .fontWeight(.semibold)
                Button("Cancel") { conflict = nil }
            }
            .pendingLineStyle(palette)
        }
    }

    @ViewBuilder private func replaceLine(for id: ButtonID) -> some View {
        if let pending = replacing, pending.id == id {
            HStack(spacing: 14) {
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
    /// A question waiting under a row: amber, on a faint amber band, its buttons a finger's height.
    func pendingLineStyle(_ palette: Palette) -> some View {
        buttonStyle(.plain)
            .font(.manrope(11))
            .foregroundStyle(palette.accent)
            .frame(minHeight: Metrics.minTouch)
            .padding(.horizontal, 10)
            .background(palette.accent.opacity(0.08))
            .padding(.bottom, 8)
    }
}

/// Catches the hardware keyboard's presses while `active`, for a key recorder: `onKey` says
/// whether it took the press; `lost` tells that something else took the keys.
struct KeyCapture: UIViewRepresentable {
    let active: Bool
    let onKey: (UIKey) -> Bool
    let lost: () -> Void

    final class Coordinator {
        var onKey: (UIKey) -> Bool
        var lost: () -> Void
        init(onKey: @escaping (UIKey) -> Bool, lost: @escaping () -> Void) {
            self.onKey = onKey
            self.lost = lost
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onKey: onKey, lost: lost) }

    func makeUIView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        let coordinator = context.coordinator
        view.onPress = { coordinator.onKey($0) }
        view.onLost = { coordinator.lost() }
        view.setActive(active)
        return view
    }

    func updateUIView(_ view: KeyCatcherView, context: Context) {
        context.coordinator.onKey = onKey
        context.coordinator.lost = lost
        view.setActive(active)
    }
}
