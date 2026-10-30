import Foundation
import Observation
import SwiftUI

/// Custom actions, their keys and their pins, kept per TV (`TVConfig.id`).
/// Defaults "actions": JSON `[tvUUID: [CustomAction]]`; "pins": JSON `[tvUUID: [actionUUID]]`.
@MainActor @Observable public final class ActionStore {
    private static let actionsKey = "actions", pinsKey = "pins"

    private var actionsByTV: [String: [CustomAction]]
    private var pinsByTV: [String: [UUID]]

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // An unreadable action is skipped on its own; unreadable top-level data counts as empty.
        actionsByTV = defaults.data(forKey: Self.actionsKey)
            .flatMap { try? JSONDecoder().decode([String: LossyArray<CustomAction>].self, from: $0) }
            .map { $0.mapValues { Self.unique($0.elements, by: \.id) } } ?? [:]
        pinsByTV = defaults.data(forKey: Self.pinsKey)
            .flatMap { try? JSONDecoder().decode([String: LossyArray<UUID>].self, from: $0) }
            .map { $0.mapValues { Self.unique($0.elements, by: \.self) } } ?? [:]
    }

    /// Keeps the first of each key, so hand-edited or merged data cannot duplicate an id.
    private static func unique<T, K: Hashable>(_ items: [T], by key: (T) -> K) -> [T] {
        var seen = Set<K>()
        return items.filter { seen.insert(key($0)).inserted }
    }

    public func actions(for tv: UUID) -> [CustomAction] { actionsByTV[tv.uuidString] ?? [] }

    /// In pin order; pins whose action no longer exists are left out.
    public func pinned(for tv: UUID) -> [CustomAction] {
        let all = actions(for: tv)
        return (pinsByTV[tv.uuidString] ?? []).compactMap { id in all.first { $0.id == id } }
    }

    public func isPinned(_ id: UUID, for tv: UUID) -> Bool { pinsByTV[tv.uuidString]?.contains(id) ?? false }

    /// Whether a pinned action of this TV does just this step, whatever its title.
    public func isPinned(onlyStep step: ActionStep, for tv: UUID) -> Bool {
        pinned(for: tv).contains { $0.steps.count == 1 && $0.steps[0].hasSameEffect(as: step) }
    }

    public func save(_ action: CustomAction, for tv: UUID) {
        var list = actions(for: tv)
        if let i = list.firstIndex(where: { $0.id == action.id }) { list[i] = action } else { list.append(action) }
        actionsByTV[tv.uuidString] = list
        persist()
    }

    public func delete(_ id: UUID, for tv: UUID) {
        actionsByTV[tv.uuidString]?.removeAll { $0.id == id }
        pinsByTV[tv.uuidString]?.removeAll { $0 == id }
        persist()
    }

    public func pin(_ id: UUID, for tv: UUID) {
        guard !isPinned(id, for: tv) else { return }
        pinsByTV[tv.uuidString, default: []].append(id)
        persist()
    }

    public func unpin(_ id: UUID, for tv: UUID) {
        pinsByTV[tv.uuidString]?.removeAll { $0 == id }
        persist()
    }

    /// Offsets in `pinned(for:)`: the pins whose action is gone are dropped on the way.
    public func movePin(for tv: UUID, from: IndexSet, to: Int) {
        guard pinsByTV[tv.uuidString] != nil else { return }
        var list = pinned(for: tv).map(\.id)
        list.move(fromOffsets: from, toOffset: to)
        pinsByTV[tv.uuidString] = list
        persist()
    }

    public func setKey(_ key: KeyBinding?, action id: UUID, for tv: UUID) {
        guard var list = actionsByTV[tv.uuidString], let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].key = key
        actionsByTV[tv.uuidString] = list
        persist()
    }

    /// `.action(id)` → its key, for the actions of this TV that have one.
    public func keySlots(for tv: UUID) -> [ButtonID: KeySlot] {
        Dictionary(actions(for: tv).compactMap { a in
            a.key.map { (ButtonID.action(a.id), KeySlot(primary: $0)) }
        }, uniquingKeysWith: { first, _ in first })
    }

    public func forget(tv: UUID) {
        actionsByTV[tv.uuidString] = nil
        pinsByTV[tv.uuidString] = nil
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(actionsByTV), forKey: Self.actionsKey)
        defaults.set(try? JSONEncoder().encode(pinsByTV), forKey: Self.pinsKey)
    }
}
