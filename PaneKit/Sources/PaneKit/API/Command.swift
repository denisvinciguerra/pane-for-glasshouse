import Foundation

public enum RemoteKey: String, Sendable, CaseIterable { case up, down, left, right, ok, back, home, settings }
public enum MediaKey: String, Sendable, CaseIterable { case rewind, playPause, stop, fastForward }
public enum SettingValue: Codable, Equatable, Sendable {
    case bool(Bool), string(String), number(Double)

    /// A bare JSON value; a boolean is tried before a number so `true` never reads as 1.
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else { self = .string(try c.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try c.encode(b)
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        }
    }
}

public enum Command: Equatable, Sendable {
    case rcu(RemoteKey), media(MediaKey)
    case volume(Int), volumeStep(Int), mute(Bool)
    case input(String)
    case launchApp(String), pictureMode(String)
    case lgSetting(id: String, SettingValue)
    case screenOff, screenOn, powerOff, powerOn
    case sleepTimer(String)

    /// `{"action": …, "value": …}`; `value` is absent for actions that take none.
    public var body: JSONValue {
        switch self {
        case .rcu(let k): return Self.make("rcu", .string(k.rawValue))
        case .media(let k): return Self.make("media", .string(k.rawValue))
        case .volume(let v): return Self.make("volume", .number(Double(v)))
        case .volumeStep(let v): return Self.make("volumeStep", .number(Double(v)))
        case .mute(let m): return Self.make("mute", .bool(m))
        case .input(let s): return Self.make("input", .string(s))
        case .launchApp(let s): return Self.make("launchApp", .string(s))
        case .pictureMode(let s): return Self.make("pictureMode", .string(s))
        case .lgSetting(let id, let value):
            switch value {
            case .bool(let on): return Self.make("lgSetting", .object(["id": .string(id), "on": .bool(on)]))
            case .string(let s): return Self.make("lgSetting", .object(["id": .string(id), "value": .string(s)]))
            case .number(let n): return Self.make("lgSetting", .object(["id": .string(id), "value": .number(n)]))
            }
        case .screenOff: return Self.make("screenOff")
        case .screenOn: return Self.make("screenOn")
        case .powerOff: return Self.make("powerOff")
        case .powerOn: return Self.make("powerOn")
        case .sleepTimer(let s): return Self.make("sleepTimer", .string(s))
        }
    }

    private static func make(_ action: String, _ value: JSONValue? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["action": .string(action)]
        if let value { o["value"] = value }
        return .object(o)
    }
}
