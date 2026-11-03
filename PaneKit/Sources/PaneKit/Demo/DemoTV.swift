import Foundation

/// An offline stand-in for a Glasshouse server, for the iOS demo mode (App Review, screenshots).
/// It serves the neutral JSON in `Resources/Demo` and changes its in-memory copy as commands
/// arrive, so the app behaves as if it controlled a real TV. It never touches the network.
public actor DemoTV: GlasshouseAPI {
    /// `TVConfig.host` of the demo TV; the reserved `.invalid` TLD never resolves.
    public static let host = "demo.invalid"

    private typealias JSON = [String: Any]

    private var documents: [String: JSON]

    /// `standby`: the TV starts in Active Standby, screen off, as after `.powerOff`.
    public init(standby: Bool = false) {
        var docs: [String: JSON] = [:]
        for name in ["stats", "caps", "picture", "audio", "game", "hdmi", "lgsettings-hdmi-devices"] {
            docs[name] = Self.load(name)
        }
        if standby, var stats = docs["stats"] {
            Self.setPower(&stats, raw: "Active Standby", label: "Standby", system: false, screen: false)
            docs["stats"] = stats
        }
        documents = docs
    }

    // MARK: GlasshouseAPI

    public func get<T: Decodable & Sendable>(_ path: String, as: T.Type) async throws(APIError) -> T {
        guard let name = Self.document(for: path), let json = documents[name] else { throw .http(404) }
        do {
            let data = try JSONSerialization.data(withJSONObject: json)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
    }

    /// The app never reads the dashboard page from a demo TV.
    public func getText(_ path: String) async throws(APIError) -> String { throw .http(404) }

    public func getData(_ path: String) async throws(APIError) -> Data {
        guard let components = URLComponents(string: path), components.path == "/api/apps/icon",
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let resource = Self.icons[id],
              let url = Bundle.module.url(forResource: resource, withExtension: "png", subdirectory: "Demo"),
              let data = try? Data(contentsOf: url)
        else { throw .http(404) }
        return data
    }

    public func send(_ command: Command) async throws(APIError) {
        switch command {
        case .input(let id): select(input: id)
        case .launchApp(let id): launch(app: id)
        case .volume(let v): setVolume(v)
        case .volumeStep(let step): setVolume((stats["volume"] as? Int ?? 0) + step)
        case .mute(let on): stats["muted"] = on
        case .powerOff: setPower(raw: "Active Standby", label: "Standby", system: false, screen: false)
        case .powerOn: setPower(raw: "Active", label: "On", system: true, screen: true)
        case .screenOff: setPower(raw: "Active", label: "On", system: true, screen: false)
        case .screenOn: setPower(raw: "Active", label: "On", system: true, screen: true)
        case .pictureMode(let mode): set(pictureMode: mode)
        case .lgSetting(let id, let value): set(setting: id, to: value)
        case .rcu, .media, .sleepTimer: break // accepted, no visible effect
        }
    }

    // MARK: Paths

    private static func document(for path: String) -> String? {
        switch path {
        case "/api/stats": "stats"
        case "/api/caps": "caps"
        case "/api/picture": "picture"
        case "/api/game": "game"
        case "/api/hdmi": "hdmi"
        case "/api/audio?with=settings": "audio"
        case "/api/lgsettings?section=hdmi,devices": "lgsettings-hdmi-devices"
        default: nil
        }
    }

    /// App id (as in `stats.apps`) to the bundled placeholder icon.
    private static let icons = [
        "com.apple.appletv": "app-icon-appletv", "netflix": "app-icon-netflix", "spotify-beehive": "app-icon-spotify",
    ]

    private static func load(_ name: String) -> JSON {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Demo"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? JSON
        else { return [:] }
        return json
    }

    // MARK: State changes

    private var stats: JSON {
        get { documents["stats"] ?? [:] }
        set { documents["stats"] = newValue }
    }

    private func select(input id: String) {
        var s = stats
        let inputs = s["inputs"] as? [String: String] ?? [:]
        let name = inputs[id] ?? (id == "livetv" ? "TV" : id)
        s["app"] = id
        s["app_id"] = "com.webos.app.\(id)"
        s["app_name"] = name
        s["display_title"] = id.hasPrefix("hdmi") ? "\(name) (HDMI\(id.dropFirst(4)))" : name
        stats = s
        markActive(port: id.hasPrefix("hdmi") ? Int(id.dropFirst(4)) : nil)
        mutate("picture", "dimension") { $0["input"] = id }
        mutate("game") { $0["input"] = id }
    }

    private func launch(app id: String) {
        guard let apps = stats["apps"] as? [JSON], let app = apps.first(where: { $0["id"] as? String == id }) else { return }
        var s = stats
        let title = app["title"] as? String ?? id
        s["app"] = id
        s["app_id"] = id
        s["app_name"] = title
        s["display_title"] = title
        stats = s
        markActive(port: nil)
    }

    /// Marks the HDMI input of that port as the active one in `/api/hdmi` (none when `nil`).
    private func markActive(port: Int?) {
        mutate("hdmi") { hdmi in
            hdmi["inputs"] = (hdmi["inputs"] as? [JSON])?.map { input in
                var input = input
                input["active"] = input["port"] as? Int == port
                return input
            }
        }
    }

    private func setVolume(_ v: Int) {
        stats["volume"] = min(max(v, 0), 100)
    }

    private func setPower(raw: String, label: String, system: Bool, screen: Bool) {
        var s = stats
        Self.setPower(&s, raw: raw, label: label, system: system, screen: screen)
        stats = s
    }

    private static func setPower(_ stats: inout JSON, raw: String, label: String, system: Bool, screen: Bool) {
        var power = stats["powerState"] as? JSON ?? [:]
        power["raw"] = raw
        power["label"] = label
        power["systemOn"] = system
        power["screenOn"] = screen
        stats["powerState"] = power
    }

    private func set(pictureMode mode: String) {
        var s = stats
        var picture = s["picture"] as? JSON ?? [:]
        let modes = picture["modes"] as? [JSON] ?? []
        picture["mode_raw"] = mode
        if let label = modes.first(where: { $0["value"] as? String == mode })?["label"] as? String { picture["mode"] = label }
        s["picture"] = picture
        stats = s
        set(setting: "pictureMode", to: .string(mode))
        mutate("picture", "dimension") { $0["pictureMode"] = mode }
        mutate("game") { $0["pictureMode"] = mode }
    }

    /// Switches carry their state in `on`, every other row in `value`.
    private func set(setting id: String, to value: SettingValue) {
        for (name, key) in [("picture", "rows"), ("game", "rows"), ("audio", "lgSettings"), ("lgsettings-hdmi-devices", "rows")] {
            mutate(name) { doc in
                doc[key] = (doc[key] as? [JSON])?.map { row in
                    guard row["id"] as? String == id else { return row }
                    var row = row
                    switch value {
                    case .bool(let on): row["on"] = on
                    case .string(let s): row["value"] = s
                    case .number(let n): row["value"] = n
                    }
                    return row
                }
            }
        }
    }

    private func mutate(_ name: String, _ transform: (inout JSON) -> Void) {
        guard var doc = documents[name] else { return }
        transform(&doc)
        documents[name] = doc
    }

    /// Same as above, on the nested object `key`.
    private func mutate(_ name: String, _ key: String, _ transform: (inout JSON) -> Void) {
        mutate(name) { doc in
            var inner = doc[key] as? JSON ?? [:]
            transform(&inner)
            doc[key] = inner
        }
    }
}
