import Foundation

public struct Endpoint: Equatable, Sendable, Codable {
    public var host: String
    public var port: Int
    public var token: String?

    public init(host: String, port: Int, token: String? = nil) {
        self.host = host
        self.port = port
        self.token = token
    }
}

public enum APIError: Error, Equatable, Sendable {
    case unreachable, badToken, http(Int), decoding(String), rejected(String), localNetworkDenied
}

public struct ControlResult: Decodable, Sendable {
    public let ok: Bool
    public let error: String?
}

public protocol GlasshouseAPI: Sendable {
    func get<T: Decodable & Sendable>(_ path: String, as: T.Type) async throws(APIError) -> T
    func getText(_ path: String) async throws(APIError) -> String
    func getData(_ path: String) async throws(APIError) -> Data
    /// Throws `.rejected(error)` when the server answers `ok == false`.
    func send(_ command: Command) async throws(APIError)
}

public struct GlasshouseClient: GlasshouseAPI {
    private let endpoint: Endpoint
    private let session: URLSession
    private let language: String
    private let timeout: TimeInterval
    private let localNetworkDenied: @Sendable (String, Int) async -> Bool

    public init(
        endpoint: Endpoint,
        session: URLSession = .shared,
        language: String = Locale.current.language.languageCode?.identifier ?? "en",
        timeout: TimeInterval = 4,
        localNetworkDenied: @escaping @Sendable (String, Int) async -> Bool = { await LocalNetworkCheck.isDenied(host: $0, port: $1) }
    ) {
        self.endpoint = endpoint
        self.session = session
        self.language = language
        self.timeout = timeout
        self.localNetworkDenied = localNetworkDenied
    }

    /// `nil` when the host cannot form a valid URL.
    public func dashboardURL(tab: String?) -> URL? {
        var items: [URLQueryItem] = []
        if let tab { items.append(URLQueryItem(name: "tab", value: tab)) }
        if let token = endpoint.token { items.append(URLQueryItem(name: "k", value: token)) }
        return url(path: "/", queryItems: items)
    }

    private func url(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        let host = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "http"
        c.host = host
        c.port = endpoint.port
        c.path = path
        if !queryItems.isEmpty { c.queryItems = queryItems }
        return c.url
    }

    public func get<T: Decodable & Sendable>(_ path: String, as: T.Type) async throws(APIError) -> T {
        let data = try await perform(try request(path))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
    }

    public func getText(_ path: String) async throws(APIError) -> String {
        let data = try await perform(try request(path))
        guard let text = String(data: data, encoding: .utf8) else { throw .decoding("response is not UTF-8") }
        return text
    }

    public func getData(_ path: String) async throws(APIError) -> Data {
        try await perform(try request(path))
    }

    public func send(_ command: Command) async throws(APIError) {
        var req = try request("/api/control")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONEncoder().encode(command.body)
        } catch {
            throw .decoding(String(describing: error))
        }
        let data = try await perform(req)
        let result: ControlResult
        do {
            result = try JSONDecoder().decode(ControlResult.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
        if !result.ok { throw .rejected(result.error ?? "") }
    }

    private func request(_ path: String) throws(APIError) -> URLRequest {
        let slash = path.hasPrefix("/") ? "" : "/"
        // A path may carry a query string; split it so URLComponents does not escape the "?".
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let items = parts.count > 1 ? URLComponents(string: "?" + parts[1])?.queryItems ?? [] : []
        guard let url = url(path: slash + parts[0], queryItems: items) else { throw .unreachable }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue(language, forHTTPHeaderField: "X-Glasshouse-Lang")
        if let token = endpoint.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private func perform(_ req: URLRequest) async throws(APIError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw await transportError(error)
        }
        guard let http = response as? HTTPURLResponse else { throw .unreachable }
        switch http.statusCode {
        case 200..<300: return data
        case 401:
            // Only Glasshouse's own 401 speaks of the token; another server's login page is a plain HTTP error.
            let body = String(decoding: data, as: UTF8.self)
            throw body.isEmpty || body.localizedCaseInsensitiveContains("token") ? .badToken : .http(401)
        default: throw .http(http.statusCode)
        }
    }

    /// A cancelled request is just unreachable; any other transport failure is `.localNetworkDenied`
    /// when a trial connection says macOS refuses the local network, else `.unreachable`.
    private func transportError(_ error: Error) async -> APIError {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return .unreachable }
        let host = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines)
        return await localNetworkDenied(host, endpoint.port) ? .localNetworkDenied : .unreachable
    }
}
