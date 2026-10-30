import Foundation

/// Identifies a button that can carry a key; encoded as its raw string.
public struct ButtonID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }

    public static func rcu(_ k: RemoteKey) -> ButtonID { ButtonID(rawValue: "rcu.\(k.rawValue)") }
    public static func media(_ k: MediaKey) -> ButtonID { ButtonID(rawValue: "media.\(k.rawValue)") }
    public static let volumeDown = ButtonID(rawValue: "volume.down")
    public static let volumeUp = ButtonID(rawValue: "volume.up")
    public static let mute = ButtonID(rawValue: "mute")
    public static func source(_ id: String) -> ButtonID { ButtonID(rawValue: "source.\(id)") }
    public static func action(_ id: UUID) -> ButtonID { ButtonID(rawValue: "action.\(id.uuidString)") }

    public var actionID: UUID? { rawValue.hasPrefix("action.") ? UUID(uuidString: String(rawValue.dropFirst(7))) : nil }
    public var sourceID: String? { rawValue.hasPrefix("source.") ? String(rawValue.dropFirst(7)) : nil }

    /// Remote's fixed buttons, in screen order.
    public static let remote: [ButtonID] = [
        .rcu(.up), .rcu(.left), .rcu(.ok), .rcu(.right), .rcu(.down), .rcu(.back), .rcu(.home), .rcu(.settings),
        .media(.rewind), .media(.playPause), .media(.stop), .media(.fastForward), .volumeDown, .volumeUp, .mute,
    ]

    /// Localized name of a fixed button; nil for the others.
    public var fixedTitle: String? { fixedTitle(bundle: .module) }

    func fixedTitle(bundle: Bundle) -> String? {
        switch rawValue {
        case "rcu.up": String(localized: "Up", bundle: bundle)
        case "rcu.down": String(localized: "Down", bundle: bundle)
        case "rcu.left": String(localized: "Left", bundle: bundle)
        case "rcu.right": String(localized: "Right", bundle: bundle)
        case "rcu.ok": String(localized: "OK", bundle: bundle)
        case "rcu.back": String(localized: "Back", bundle: bundle)
        // Its own key: "Home" is the dashboard tab here (« Maison »).
        case "rcu.home": String(localized: "Home button", defaultValue: "Home", bundle: bundle,
                                comment: "Remote's Home button, named as the D-pad names it")
        case "rcu.settings": String(localized: "Settings", bundle: bundle)
        case "media.rewind": String(localized: "Rewind", bundle: bundle)
        case "media.playPause": String(localized: "Play/Pause", bundle: bundle)
        case "media.stop": String(localized: "Stop", bundle: bundle)
        case "media.fastForward": String(localized: "Fast forward", bundle: bundle)
        case "volume.down": String(localized: "Volume −", bundle: bundle)
        case "volume.up": String(localized: "Volume +", bundle: bundle)
        case "mute": String(localized: "Mute", bundle: bundle)
        default: nil
        }
    }
}
