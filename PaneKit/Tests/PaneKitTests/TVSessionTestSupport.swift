import XCTest
@testable import PaneKit

/// Serves the fixtures by path, records the commands, and fails on demand.
actor FakeAPI: GlasshouseAPI {
    private var bodies: [String: Data] = [
        "/api/stats": Fixture.data("stats"),
        "/api/caps": Fixture.data("caps"),
        "/api/picture": Fixture.data("picture"),
        "/api/game": Fixture.data("game"),
        "/api/audio?with=settings": Fixture.data("audio"),
        "/api/hdmi": Fixture.data("hdmi"),
        "/api/lgsettings?section=hdmi,devices": Fixture.data("lgsettings-hdmi-devices"),
        "/": Fixture.data("ui.html"),
    ]
    private var failures: [String: APIError] = [:]
    private var sendFailure: APIError?
    /// Cancels the calling task, then fails as URLSession does once cancelled.
    private var cancelOnStats = false
    private(set) var commands: [Command] = []
    private(set) var paths: [String] = []
    /// Paths whose next read answers what was served when it was asked, but only once released.
    private var holding: Set<String> = []
    private var held: [String: [CheckedContinuation<Void, Never>]] = [:]

    func serve(_ path: String, _ body: Data) { bodies[path] = body; failures[path] = nil }
    func fail(_ path: String, _ error: APIError) { failures[path] = error }
    func failSend(_ error: APIError?) { sendFailure = error }
    func cancelCallerOnStats() { cancelOnStats = true }
    func hold(_ path: String) { holding.insert(path) }
    func heldCount(_ path: String) -> Int { held[path]?.count ?? 0 }
    func release(_ path: String) { if let c = held[path]?.first { held[path]?.removeFirst(); c.resume() } }

    /// The answer is fixed when the read is asked; a held read delivers it when released.
    private func answer(_ path: String) async throws(APIError) -> Data {
        let outcome: Result<Data, APIError>
        do { outcome = .success(try body(path)) } catch { outcome = .failure(error) }
        if holding.remove(path) != nil {
            await withCheckedContinuation { held[path, default: []].append($0) }
        }
        return try outcome.get()
    }

    private func body(_ path: String) throws(APIError) -> Data {
        paths.append(path)
        if path == "/api/stats", cancelOnStats {
            withUnsafeCurrentTask { $0?.cancel() }
            throw .unreachable
        }
        if let error = failures[path] { throw error }
        guard let data = bodies[path] else { throw .http(404) }
        return data
    }

    func get<T: Decodable & Sendable>(_ path: String, as: T.Type) async throws(APIError) -> T {
        let data = try await answer(path)
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw .decoding("\(error)") }
    }

    func getText(_ path: String) async throws(APIError) -> String {
        String(decoding: try await answer(path), as: UTF8.self)
    }

    func getData(_ path: String) async throws(APIError) -> Data { try await answer(path) }

    func send(_ command: Command) async throws(APIError) {
        commands.append(command)
        if let sendFailure { throw sendFailure }
    }
}

/// Records the requested pauses and returns at once.
actor SleepLog {
    private(set) var durations: [Duration] = []
    func record(_ d: Duration) { durations.append(d) }
}

/// The stats fixture with the JSON fragment `from` replaced by `to`.
func stats(_ from: String, _ to: String) -> Data {
    let text = String(decoding: Fixture.data("stats"), as: UTF8.self)
    precondition(text.contains(from), from)
    return Data(text.replacingOccurrences(of: from, with: to).utf8)
}

/// Parks until cancelled, so a transient message stays up while a test looks at it.
let parked: @Sendable (Duration) async -> Void = { _ in try? await Task.sleep(for: .seconds(3600)) }


@MainActor
func makeSession(_ api: FakeAPI, mac: String? = nil,
                 sleep: @escaping @Sendable (Duration) async -> Void = parked,
                 wake: @escaping @Sendable (String) async throws -> Void = { _ in XCTFail("no Wake-on-LAN expected") },
                 lostContact: @escaping @MainActor () -> Void = {},
                 answered: @escaping @MainActor () -> Void = {}) -> TVSession {
    TVSession(api: api, mac: mac, sleep: sleep, wake: wake, lostContact: lostContact, answered: answered)
}
