import Foundation

/// `GET /api/stats`. Every field is optional: the server omits what the TV cannot report. Decoding
/// is lenient, field by field: a field of an unexpected type is dropped (`nil`) and the rest
/// stays, so a server change hides a readout instead of making the TV look unreachable. An integer
/// field also takes a number with a fraction, rounded.
public struct Stats: Decodable, Sendable {
    public struct Device: Decodable, Sendable {
        public let model: String?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            model = c.lenient(.model)
        }
        private enum CodingKeys: String, CodingKey { case model }
    }

    public struct Power: Decodable, Sendable {
        public let raw: String?; public let label: String?; public let systemOn: Bool?; public let screenOn: Bool?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            raw = c.lenient(.raw); label = c.lenient(.label)
            systemOn = c.lenient(.systemOn); screenOn = c.lenient(.screenOn)
        }
        private enum CodingKeys: String, CodingKey { case raw, label, systemOn, screenOn }
    }

    public struct SignalFormat: Decodable, Sendable {
        public let typeDisplay: String?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            typeDisplay = c.lenient(.typeDisplay)
        }
        private enum CodingKeys: String, CodingKey { case typeDisplay = "type_display" }
    }

    public struct HDMIDiag: Decodable, Sendable {
        public let port: Int?; public let phyMode: String?; public let chroma: String?
        public let hdcp: String?; public let allm: Bool?; public let vrr: Bool?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            port = c.lenientInt(.port); phyMode = c.lenient(.phyMode); chroma = c.lenient(.chroma)
            hdcp = c.lenient(.hdcp); allm = c.lenient(.allm); vrr = c.lenient(.vrr)
        }
        private enum CodingKeys: String, CodingKey { case port, chroma, hdcp, allm, vrr; case phyMode = "phy_mode" }
    }

    /// kB.
    public struct Mem: Decodable, Sendable {
        public let total: Double?; public let avail: Double?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            total = c.lenient(.total); avail = c.lenient(.avail)
        }
        private enum CodingKeys: String, CodingKey { case total, avail }
    }

    public struct Swap: Decodable, Sendable {
        public let total: Double?; public let free: Double?; public let backing: String?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            total = c.lenient(.total); free = c.lenient(.free); backing = c.lenient(.backing)
        }
        private enum CodingKeys: String, CodingKey { case total, free, backing }
    }

    /// Octets/s.
    public struct Net: Decodable, Sendable {
        public let rx: Double?; public let tx: Double?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rx = c.lenient(.rx); tx = c.lenient(.tx)
        }
        private enum CodingKeys: String, CodingKey { case rx, tx }
    }

    public struct Wifi: Decodable, Sendable {
        public let level: Int?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            level = c.lenientInt(.level)
        }
        private enum CodingKeys: String, CodingKey { case level }
    }

    public struct Oled: Decodable, Sendable {
        public let panelHours: Int?; public let compStatus: String?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            panelHours = c.lenientInt(.panelHours); compStatus = c.lenient(.compStatus)
        }
        private enum CodingKeys: String, CodingKey { case panelHours = "panel_hours"; case compStatus = "comp_status" }
    }

    public struct Sound: Decodable, Sendable {
        public let output: String?; public let mode: String?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            output = c.lenient(.output); mode = c.lenient(.mode)
        }
        private enum CodingKeys: String, CodingKey { case output, mode }
    }

    /// An app installed on the TV; an entry without an id or a title is not decoded.
    public struct App: Decodable, Equatable, Sendable {
        public let id: String; public let title: String

        public init(id: String, title: String) { self.id = id; self.title = title }
        private enum CodingKeys: String, CodingKey { case id, title }
    }

    public let tvwebVersion: String?; public let device: Device?; public let powerState: Power?
    public internal(set) var volume: Int?; public internal(set) var muted: Bool?; public let audioOutput: String?; public let sound: Sound?
    public internal(set) var app: String?; public let appId: String?; public let appName: String?; public let displayTitle: String?
    public let signal: String?; public let signalFormat: SignalFormat?; public let hdmiDiag: HDMIDiag?
    public let inputs: [String: String]?; public let mac: String?; public let wakeOnLan: Bool?
    public let load: Int?; public let cores: [Int]?; public let mem: Mem?; public let swap: Swap?
    public let net: Net?; public let wifi: Wifi?; public let ssid: String?; public let temp: Int?
    public let uptime: Double?; public let oled: Oled?; public let sleepTimer: String?
    public let apps: [App]?

    enum CodingKeys: String, CodingKey {
        case tvwebVersion, device, powerState, volume, muted, sound, app, signal, inputs, mac, wakeOnLan
        case load, cores, mem, swap, net, wifi, ssid, temp, uptime, oled, sleepTimer, apps
        case audioOutput = "audio_output", appId = "app_id", appName = "app_name", displayTitle = "display_title"
        case signalFormat = "signal_format", hdmiDiag = "hdmi_diag"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tvwebVersion = c.lenient(.tvwebVersion); device = c.lenient(.device); powerState = c.lenient(.powerState)
        volume = c.lenientInt(.volume); muted = c.lenient(.muted); audioOutput = c.lenient(.audioOutput)
        sound = c.lenient(.sound)
        app = c.lenient(.app); appId = c.lenient(.appId); appName = c.lenient(.appName)
        displayTitle = c.lenient(.displayTitle)
        signal = c.lenient(.signal); signalFormat = c.lenient(.signalFormat); hdmiDiag = c.lenient(.hdmiDiag)
        inputs = c.lenient(.inputs); mac = c.lenient(.mac); wakeOnLan = c.lenient(.wakeOnLan)
        load = c.lenientInt(.load)
        cores = c.lenient(.cores, as: [LenientInt].self)?.compactMap(\.value)
        mem = c.lenient(.mem); swap = c.lenient(.swap)
        net = c.lenient(.net); wifi = c.lenient(.wifi); ssid = c.lenient(.ssid); temp = c.lenientInt(.temp)
        uptime = c.lenient(.uptime); oled = c.lenient(.oled); sleepTimer = c.lenient(.sleepTimer)
        apps = c.lenient(.apps, as: LossyArray<App>.self)?.elements
    }

    /// The nearest integer; `nil` for a value no `Int` can hold.
    static func whole(_ x: Double) -> Int? {
        x.isFinite && abs(x) < 1e15 ? Int(x.rounded()) : nil
    }
}

/// An array element that is an integer, a number with a fraction (rounded), or anything else (`nil`).
private struct LenientInt: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i } else { value = (try? c.decode(Double.self)).flatMap(Stats.whole) }
    }
}

extension KeyedDecodingContainer {
    /// The field, or `nil` when it is missing, null or of another type.
    func lenient<T: Decodable>(_ key: Key, as type: T.Type = T.self) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    /// An integer field, also from a number with a fraction (rounded).
    func lenientInt(_ key: Key) -> Int? {
        if let i = lenient(key, as: Int.self) { return i }
        return lenient(key, as: Double.self).flatMap(Stats.whole)
    }
}
