import Foundation

/// Where a TV's Glasshouse server answers, read from what the user typed or pasted.
public struct TVAddress: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var token: String?

    public static let defaultPort = 8080

    public init(host: String, port: Int, token: String?) {
        self.host = host
        self.port = port
        self.token = token
    }

    /// A bare address ("192.0.2.10", "tv.local:8081") takes port 8080. A full link
    /// ("http://…:8080/?k=…") keeps its port, or 80 without one, and its `k` as the token.
    /// `nil` for empty text, a scheme other than http, no host, an IPv6 host or a port outside 1...65535.
    public static func parse(_ input: String) -> TVAddress? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let bare = !text.contains("://")
        guard let parts = URLComponents(string: bare ? "http://" + text : text),
              parts.scheme?.lowercased() == "http",
              let host = parts.host, !host.isEmpty, !host.contains(where: \.isWhitespace),
              !host.contains(":") // an IPv6 literal: the client composes http://host:port without brackets
        else { return nil }
        let port = parts.port ?? (bare ? defaultPort : 80)
        guard (1...65535).contains(port) else { return nil }
        let token = parts.queryItems?.first { $0.name == "k" }?.value
        return TVAddress(host: host, port: port, token: token?.isEmpty == false ? token : nil)
    }
}
