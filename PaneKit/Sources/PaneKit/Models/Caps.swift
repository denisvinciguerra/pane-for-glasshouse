/// `GET /api/caps`. Decoding is lenient: a missing or mistyped field allows what it governs, the
/// server enforcing its own rules anyway. A server without caps (404) allows everything.
public struct Caps: Decodable, Sendable {
    public let allowControl: Bool
    public let allowPower: Bool
    public let version: String
    /// Present and true on a Glasshouse server; tells a real answer from any other web server's 200.
    public let ok: Bool

    static let permissive = Caps(allowControl: true, allowPower: true, version: "", ok: true)

    init(allowControl: Bool, allowPower: Bool, version: String, ok: Bool = false) {
        self.allowControl = allowControl
        self.allowPower = allowPower
        self.version = version
        self.ok = ok
    }

    private enum CodingKeys: String, CodingKey { case allowControl, allowPower, version, ok }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        allowControl = (try? c.decodeIfPresent(Bool.self, forKey: .allowControl)) ?? true
        allowPower = (try? c.decodeIfPresent(Bool.self, forKey: .allowPower)) ?? true
        version = (try? c.decodeIfPresent(String.self, forKey: .version)) ?? ""
        ok = (try? c.decodeIfPresent(Bool.self, forKey: .ok)) ?? false
    }
}
