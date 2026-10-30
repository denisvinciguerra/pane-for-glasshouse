import Foundation
import Observation

/// The keys in use: one of the fixed profiles, or Custom.
public enum KeymapChoice: Hashable, Sendable {
    case profile(KeyProfile)
    case custom
}

/// The one Custom profile: the profile it started from, and its keys.
public struct CustomKeymap: Equatable, Sendable, Codable {
    public var base: KeyProfile
    public var slots: [ButtonID: KeySlot]

    public init(base: KeyProfile, slots: [ButtonID: KeySlot]) {
        self.base = base
        self.slots = slots
    }

    private enum CodingKeys: String, CodingKey { case base, slots }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = try c.decode(KeyProfile.self, forKey: .base)
        slots = KeymapStore.slots(from: try c.decode([String: KeySlot].self, forKey: .slots))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(base, forKey: .base)
        try c.encode(KeymapStore.encodable(slots), forKey: .slots)
    }
}

/// The keymap shared by every TV: the fixed profiles, and the Custom one kept apart. Choosing a
/// fixed profile keeps Custom; a change of keys on a fixed profile makes Custom from it.
@MainActor @Observable public final class KeymapStore {
    private static let profileKey = "keyProfile", customKey = "customKeymap"
    /// Before Custom was kept apart: the keys in use, and whether they differed from the profile.
    private static let legacyKeymapKey = "keymap", legacyCustomKey = "keyCustom"

    public private(set) var choice: KeymapChoice
    public private(set) var custom: CustomKeymap?

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.profileKey)
        let custom = defaults.data(forKey: Self.customKey).flatMap { try? JSONDecoder().decode(CustomKeymap.self, from: $0) }
        if defaults.object(forKey: Self.customKey) == nil, let legacy = defaults.data(forKey: Self.legacyKeymapKey) {
            // An unreadable keymap falls back to the profile, not to Custom.
            let base = stored.flatMap(KeyProfile.init(rawValue:)) ?? .arrows
            let slots = (try? JSONDecoder().decode([String: KeySlot].self, from: legacy)).map(Self.slots(from:))
            if let slots, Self.differs(slots, from: base) {
                self.custom = CustomKeymap(base: base, slots: slots)
                choice = .custom
            } else {
                self.custom = nil
                choice = .profile(base)
            }
            return
        }
        self.custom = custom
        if stored == "custom" {
            choice = custom == nil ? .profile(.arrows) : .custom
        } else {
            choice = .profile(stored.flatMap(KeyProfile.init(rawValue:)) ?? .arrows)
        }
    }

    /// The keys in use: the profile's, or Custom's.
    public var slots: [ButtonID: KeySlot] {
        switch choice {
        case .profile(let profile): profile.slots
        case .custom: custom?.slots ?? KeyProfile.arrows.slots
        }
    }

    /// Custom only once it exists.
    public func choose(_ choice: KeymapChoice) {
        if choice == .custom, custom == nil { return }
        self.choice = choice
        save()
    }

    /// Keeps the fixed buttons and the sources (not the `.action`s). On a fixed profile, a change
    /// makes Custom from it, in place of the one there was.
    public func set(_ slots: [ButtonID: KeySlot]) {
        let kept = Self.shared(slots)
        guard kept != self.slots else { return }
        switch choice {
        case .profile(let profile): custom = CustomKeymap(base: profile, slots: kept)
        case .custom: custom?.slots = kept
        }
        choice = .custom
        save()
    }

    /// Whether `set(slots)` would replace the Custom profile there is: a change made on a fixed profile.
    public func replacesCustom(with slots: [ButtonID: KeySlot]) -> Bool {
        guard case .profile = choice, custom != nil else { return false }
        return Self.shared(slots) != self.slots
    }

    /// Custom differs from the profile it started from.
    public var canReset: Bool {
        guard choice == .custom, let custom else { return false }
        return Self.differs(custom.slots, from: custom.base)
    }

    /// Custom back to the profile it started from.
    public func reset() {
        guard canReset, let base = custom?.base else { return }
        custom?.slots = base.slots
        save()
    }

    private static func shared(_ slots: [ButtonID: KeySlot]) -> [ButtonID: KeySlot] {
        slots.filter { ButtonID.remote.contains($0.key) || $0.key.sourceID != nil }
    }

    private static func differs(_ slots: [ButtonID: KeySlot], from profile: KeyProfile) -> Bool {
        func filled(_ s: [ButtonID: KeySlot]) -> [ButtonID: KeySlot] { s.filter { $0.value != KeySlot() } }
        return filled(slots) != filled(profile.slots)
    }

    nonisolated static func slots(from encoded: [String: KeySlot]) -> [ButtonID: KeySlot] {
        Dictionary(uniqueKeysWithValues: encoded.map { (ButtonID(rawValue: $0.key), $0.value) })
    }

    nonisolated static func encodable(_ slots: [ButtonID: KeySlot]) -> [String: KeySlot] {
        Dictionary(uniqueKeysWithValues: slots.map { ($0.key.rawValue, $0.value) })
    }

    private func save() {
        switch choice {
        case .profile(let profile): defaults.set(profile.rawValue, forKey: Self.profileKey)
        case .custom: defaults.set("custom", forKey: Self.profileKey)
        }
        defaults.set(custom.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.customKey)
        defaults.removeObject(forKey: Self.legacyKeymapKey)
        defaults.removeObject(forKey: Self.legacyCustomKey)
    }
}
