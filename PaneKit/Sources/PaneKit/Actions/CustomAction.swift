import Foundation

/// One thing an action does. Encoded as `{"kind": …}` plus the fields of its kind.
public enum ActionStep: Codable, Equatable, Sendable {
    case button(ButtonID)
    case launchApp(id: String, title: String)
    case pictureMode(value: String, label: String)
    case setting(id: String, section: String, title: String, value: SettingValue, valueLabel: String)
    case screenOff, screenOn
    /// "off", "10", "30", "60", "90" or "120".
    case sleepTimer(String)

    private enum CodingKeys: String, CodingKey { case kind, button, id, title, value, label, section, valueLabel }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "button": self = .button(try c.decode(ButtonID.self, forKey: .button))
        case "app": self = .launchApp(id: try c.decode(String.self, forKey: .id), title: try c.decode(String.self, forKey: .title))
        case "pictureMode":
            self = .pictureMode(value: try c.decode(String.self, forKey: .value), label: try c.decode(String.self, forKey: .label))
        case "setting":
            self = .setting(id: try c.decode(String.self, forKey: .id), section: try c.decode(String.self, forKey: .section),
                            title: try c.decode(String.self, forKey: .title), value: try c.decode(SettingValue.self, forKey: .value),
                            valueLabel: try c.decode(String.self, forKey: .valueLabel))
        case "screenOff": self = .screenOff
        case "screenOn": self = .screenOn
        case "sleepTimer": self = .sleepTimer(try c.decode(String.self, forKey: .value))
        case let kind:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown step kind \(kind)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .button(let b): try c.encode("button", forKey: .kind); try c.encode(b, forKey: .button)
        case .launchApp(let id, let title):
            try c.encode("app", forKey: .kind); try c.encode(id, forKey: .id); try c.encode(title, forKey: .title)
        case .pictureMode(let value, let label):
            try c.encode("pictureMode", forKey: .kind); try c.encode(value, forKey: .value); try c.encode(label, forKey: .label)
        case .setting(let id, let section, let title, let value, let valueLabel):
            try c.encode("setting", forKey: .kind); try c.encode(id, forKey: .id); try c.encode(section, forKey: .section)
            try c.encode(title, forKey: .title); try c.encode(value, forKey: .value); try c.encode(valueLabel, forKey: .valueLabel)
        case .screenOff: try c.encode("screenOff", forKey: .kind)
        case .screenOn: try c.encode("screenOn", forKey: .kind)
        case .sleepTimer(let v): try c.encode("sleepTimer", forKey: .kind); try c.encode(v, forKey: .value)
        }
    }

    /// Mute toggles from `stats.muted`; volume ± is one step; `nil` for a button that sends nothing
    /// (a custom action, or a button this version does not know).
    public func command(stats: Stats?) -> Command? {
        switch self {
        case .button(let id): Self.command(for: id, stats: stats)
        case .launchApp(let id, _): .launchApp(id)
        case .pictureMode(let value, _): .pictureMode(value)
        case .setting(let id, _, _, let value, _): .lgSetting(id: id, value)
        case .screenOff: .screenOff
        case .screenOn: .screenOn
        case .sleepTimer(let v): .sleepTimer(v)
        }
    }

    private static func command(for id: ButtonID, stats: Stats?) -> Command? {
        if let source = id.sourceID { return .input(source) }
        switch id.rawValue {
        case "volume.up": return .volumeStep(1)
        case "volume.down": return .volumeStep(-1)
        case "mute": return .mute(!(stats?.muted ?? false))
        default: break
        }
        if id.rawValue.hasPrefix("rcu."), let k = RemoteKey(rawValue: String(id.rawValue.dropFirst(4))) { return .rcu(k) }
        if id.rawValue.hasPrefix("media."), let k = MediaKey(rawValue: String(id.rawValue.dropFirst(6))) { return .media(k) }
        return nil
    }

    public func defaultTitle(sources: [Source]) -> String { defaultTitle(sources: sources, bundle: .module) }

    func defaultTitle(sources: [Source], bundle: Bundle) -> String {
        switch self {
        case .button(let id): id.title(sources: sources, actions: [], bundle: bundle)
        case .launchApp(_, let title): title
        case .pictureMode(_, let label): label
        case .setting(_, _, let title, _, let valueLabel): "\(title) · \(valueLabel)"
        case .screenOff: String(localized: "Screen off", bundle: bundle)
        case .screenOn: String(localized: "Screen on", bundle: bundle)
        case .sleepTimer(let v):
            v == "off" ? String(localized: "Sleep off", bundle: bundle) : String(localized: "Sleep \(v) min", bundle: bundle)
        }
    }
}

extension ActionStep {
    /// The row set to `value`, labelled as the row shows it: ON or OFF, the choice's label, the
    /// number as the web words it.
    public init(row: SettingRow, value: SettingValue) {
        let label: String
        switch value {
        case .bool(let on): label = on ? "ON" : "OFF"
        case .string(let v):
            if case .choice(_, let choices) = row.kind { label = choices.first { $0.value == v }?.label ?? v } else { label = v }
        case .number(let n): label = RowLayout.valueText(row, value: n)
        }
        self = .setting(id: row.id, section: row.section, title: row.title, value: value, valueLabel: label)
    }

    /// The row at its current value; `nil` for a row this app cannot show.
    public init?(currentValueOf row: SettingRow) {
        switch row.kind {
        case .toggle(let on): self.init(row: row, value: .bool(on))
        case .choice(let value, _): self.init(row: row, value: .string(value))
        case .number(let value, _, _): self.init(row: row, value: .number(value))
        case .unsupported: return nil
        }
    }

    /// The same kind, target and value (a setting: the same id and value); the titles and labels
    /// the steps carry are ignored.
    public func hasSameEffect(as other: ActionStep) -> Bool {
        switch (self, other) {
        case let (.button(a), .button(b)): a == b
        case let (.launchApp(a, _), .launchApp(b, _)): a == b
        case let (.pictureMode(a, _), .pictureMode(b, _)): a == b
        case let (.setting(a, _, _, va, _), .setting(b, _, _, vb, _)): a == b && va == vb
        case (.screenOff, .screenOff), (.screenOn, .screenOn): true
        case let (.sleepTimer(a), .sleepTimer(b)): a == b
        default: false
        }
    }
}

public struct CustomAction: Codable, Equatable, Sendable, Identifiable {
    /// What a pinned action's tile shows: the icon of the app it launches, or its title.
    public enum Tile: String, Codable, Sendable { case icon, text }

    public let id: UUID
    public var title: String
    public var steps: [ActionStep]
    public var key: KeyBinding?
    /// The tile chosen in the editor; `nil` for the default (see `shownTile`).
    public var tile: Tile?

    public init(id: UUID = UUID(), title: String, steps: [ActionStep], key: KeyBinding? = nil, tile: Tile? = nil) {
        self.id = id; self.title = title; self.steps = steps; self.key = key; self.tile = tile
    }

    /// The first app the action launches: the one whose icon its tile can show.
    public var iconAppID: String? {
        steps.lazy.compactMap { step -> String? in
            if case .launchApp(let id, _) = step { return id }
            return nil
        }.first
    }

    /// The tile chosen, by default the icon for an action that only launches an app; the text
    /// when no app gives an icon.
    public var shownTile: Tile {
        guard iconAppID != nil else { return .text }
        return tile ?? (steps.count == 1 ? .icon : .text)
    }

    /// The titles of the steps joined by " + " (« PS5 Console de jeu + Game Optimizer · ON »).
    public static func defaultTitle(_ steps: [ActionStep], sources: [Source]) -> String {
        steps.map { $0.defaultTitle(sources: sources) }.joined(separator: " + ")
    }
}

extension ButtonID {
    /// `fixedTitle`, else the source's name, the action's title, or the raw value.
    public func title(sources: [Source], actions: [CustomAction]) -> String {
        title(sources: sources, actions: actions, bundle: .module)
    }

    func title(sources: [Source], actions: [CustomAction], bundle: Bundle) -> String {
        if let fixed = fixedTitle(bundle: bundle) { return fixed }
        if let source = sourceID { return sources.first { $0.id == source }?.label ?? source }
        if let action = actionID, let found = actions.first(where: { $0.id == action }) { return found.title }
        return rawValue
    }
}
