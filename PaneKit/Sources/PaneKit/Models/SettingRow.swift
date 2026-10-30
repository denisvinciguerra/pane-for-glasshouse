import Foundation

public struct Choice: Decodable, Equatable, Sendable {
    public let value: String
    public let label: String

    public init(value: String, label: String) { self.value = value; self.label = label }
}

/// One setting of the TV, as the server sends it. Decoding is tolerant: a row of an unknown
/// type, or a known type missing what it needs, becomes `.unsupported` instead of failing.
public struct SettingRow: Decodable, Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case toggle(on: Bool)
        case choice(value: String, choices: [Choice])
        case number(value: Double, min: Double, max: Double)
        case unsupported(String)
    }

    public let id: String
    public let section: String
    public let title: String
    public let desc: String?
    public let group: String?
    public let track: String?
    public let port: Int?
    public let column: String?
    public let active: Bool
    public let inactive: String?
    public let cms: String?
    public internal(set) var kind: Kind

    /// A number row beyond ±1e9, or with its minimum above its maximum, is unsupported: the
    /// slider and the value text could not draw it.
    static let numberLimit = 1e9

    private enum CodingKeys: String, CodingKey {
        case id, section, title, desc, group, track, port, column, active, inactive, cms
        case type, on, value, choices, min, max
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        section = try c.decode(String.self, forKey: .section)
        title = try c.decode(String.self, forKey: .title)
        desc = try? c.decodeIfPresent(String.self, forKey: .desc)
        group = try? c.decodeIfPresent(String.self, forKey: .group)
        track = try? c.decodeIfPresent(String.self, forKey: .track)
        port = try? c.decodeIfPresent(Int.self, forKey: .port)
        column = try? c.decodeIfPresent(String.self, forKey: .column)
        active = (try? c.decodeIfPresent(Bool.self, forKey: .active)) ?? true
        inactive = try? c.decodeIfPresent(String.self, forKey: .inactive)
        cms = try? c.decodeIfPresent(String.self, forKey: .cms)

        let type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "switch"
        switch type {
        case "switch":
            if let on = try? c.decode(Bool.self, forKey: .on) { kind = .toggle(on: on) } else { kind = .unsupported(type) }
        case "choice":
            if let value = try? c.decode(String.self, forKey: .value),
               let choices = try? c.decode([Choice].self, forKey: .choices) {
                kind = .choice(value: value, choices: choices)
            } else { kind = .unsupported(type) }
        case "number":
            if let value = try? c.decode(Double.self, forKey: .value),
               let min = try? c.decode(Double.self, forKey: .min),
               let max = try? c.decode(Double.self, forKey: .max),
               [value, min, max].allSatisfy({ $0.isFinite && abs($0) <= Self.numberLimit }), min <= max {
                kind = .number(value: value, min: min, max: max)
            } else { kind = .unsupported(type) }
        default:
            kind = .unsupported(type)
        }
    }
}
