import Foundation

/// Toutes les touches en jeu : les boutons communs et les actions de la TV active (`.action(id)`).
public struct KeyAssignments: Equatable, Sendable {
    public var slots: [ButtonID: KeySlot]
    public init(slots: [ButtonID: KeySlot]) { self.slots = slots }

    /// Deux touches produisent la même frappe : mêmes modificateurs (Maj ignorée côté caractère) et
    /// même code, même caractère, ou caractère de la disposition pour ce code.
    private static func sameKeystroke(_ a: KeyBinding, _ b: KeyBinding, layout: some KeyboardLayout) -> Bool {
        switch (a.trigger, b.trigger) {
        case (.keyCode(let x), .keyCode(let y)): return x == y && a.modifiers == b.modifiers
        case (.character(let x), .character(let y)):
            return x.lowercased() == y.lowercased() && a.modifiers.subtracting(.shift) == b.modifiers.subtracting(.shift)
        case (.keyCode(let code), .character(let c)), (.character(let c), .keyCode(let code)):
            return layout.character(for: code)?.lowercased() == c.lowercased()
                && a.modifiers.subtracting(.shift) == b.modifiers.subtracting(.shift)
        }
    }

    /// The shared buttons, then the actions: a keystroke left on both (after Reset keys or a
    /// profile) is the shared button's.
    private var sortedIDs: [ButtonID] {
        func rank(_ id: ButtonID) -> Int { id.actionID == nil ? 0 : 1 }
        return slots.keys.sorted { (rank($0), $0.rawValue) < (rank($1), $1.rawValue) }
    }

    /// Le bouton dont une touche (principale ou rechange) produit la même frappe que `binding`.
    public func owner(of binding: KeyBinding, layout: some KeyboardLayout, except: ButtonID? = nil) -> ButtonID? {
        sortedIDs.first { id in
            guard id != except, let slot = slots[id] else { return false }
            return [slot.primary, slot.alternate].contains { $0.map { Self.sameKeystroke($0, binding, layout: layout) } ?? false }
        }
    }

    private static let repeatable: Set<ButtonID> = [.rcu(.up), .rcu(.down), .rcu(.left), .rcu(.right), .volumeUp, .volumeDown]

    /// Le bouton à presser pour cet événement : les boutons communs avant les actions, puis `keyCode`
    /// avant caractère, principale avant rechange.
    /// Une répétition ne vaut que pour up/down/left/right et volumeUp/volumeDown.
    public func button(for event: KeyEvent) -> ButtonID? {
        func isCode(_ b: KeyBinding) -> Bool { if case .keyCode = b.trigger { true } else { false } }
        func first(among ids: [ButtonID]) -> ButtonID? {
            [true, false].lazy.flatMap { codes in
                [\KeySlot.primary, \KeySlot.alternate].lazy.compactMap { role in
                    ids.first { id in
                        guard let b = slots[id]?[keyPath: role] else { return false }
                        return isCode(b) == codes && b.matches(event)
                    }
                }
            }.first { _ in true }
        }
        let ids = sortedIDs
        let found = first(among: ids.filter { $0.actionID == nil }) ?? first(among: ids.filter { $0.actionID != nil })
        guard let found, !event.isRepeat || Self.repeatable.contains(found) else { return nil }
        return found
    }

    public enum Outcome: Equatable { case assigned(KeyAssignments), conflict(owner: ButtonID) }

    private func binding(_ role: KeySlot.Role, of id: ButtonID) -> KeyBinding? {
        role == .primary ? slots[id]?.primary : slots[id]?.alternate
    }

    private func setting(_ binding: KeyBinding?, _ role: KeySlot.Role, of id: ButtonID) -> KeyAssignments {
        var copy = self
        var slot = copy.slots[id] ?? KeySlot()
        if role == .primary { slot.primary = binding } else { slot.alternate = binding }
        copy.slots[id] = slot
        return copy
    }

    private static func other(_ role: KeySlot.Role) -> KeySlot.Role { role == .primary ? .alternate : .primary }

    /// Comme `role` de `id`. Déjà sa touche pour ce rôle : inchangé. Une touche que `id` tient dans
    /// son autre rôle y est déplacée, sans conflit.
    public func assigning(_ binding: KeyBinding, to id: ButtonID, role: KeySlot.Role = .primary,
                          layout: some KeyboardLayout) -> Outcome {
        if self.binding(role, of: id) == binding { return .assigned(self) }
        if let owner = owner(of: binding, layout: layout, except: id) { return .conflict(owner: owner) }
        var result = self
        let otherRole = Self.other(role)
        if let held = self.binding(otherRole, of: id), Self.sameKeystroke(held, binding, layout: layout) {
            result = result.setting(nil, otherRole, of: id)
        }
        return .assigned(result.setting(binding, role, of: id))
    }

    /// `id` prend `binding` ; `owner` perd cette touche, là où il la tenait, et y prend l'ancienne
    /// touche de `id` pour ce rôle (ou rien).
    public func swapping(_ binding: KeyBinding, to id: ButtonID, from owner: ButtonID,
                         role: KeySlot.Role = .primary,
                         layout: some KeyboardLayout) -> KeyAssignments {
        let old = self.binding(role, of: id)
        var result = self
        func held(_ r: KeySlot.Role) -> Bool {
            self.binding(r, of: owner).map { Self.sameKeystroke($0, binding, layout: layout) } ?? false
        }
        if let r = [KeySlot.Role.primary, .alternate].first(where: held) { result = result.setting(old, r, of: owner) }
        return result.setting(binding, role, of: id)
    }

    public func removing(_ role: KeySlot.Role, of id: ButtonID) -> KeyAssignments {
        slots[id] == nil ? self : setting(nil, role, of: id)
    }

    public func removingPrimary(of id: ButtonID) -> KeyAssignments { removing(.primary, of: id) }
}
