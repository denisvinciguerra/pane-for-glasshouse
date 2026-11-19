import Foundation

struct PointerDelta: Codable, Equatable, Sendable {
    let dx: Int
    let dy: Int
}

struct PointerBatch: Codable, Equatable, Sendable {
    var move: [PointerDelta]?
    var click: Bool?
    var scroll: PointerDelta?
}

/// What carries the batches to the TV: the dashboard's WebSocket, or a test's recorder.
@MainActor protocol PointerChannel: AnyObject {
    /// False once the server closed it or it failed: it is replaced, not written to.
    var isOpen: Bool { get }
    func send(_ text: String) async throws
    func close()
}

/// The dashboard's pointer WebSocket. Glasshouse only answers on it to refuse a batch; reading it
/// is how a closed connection (Glasshouse restarted, the TV rebooted) shows.
@MainActor final class WebSocketPointerChannel: PointerChannel {
    private(set) var isOpen = true
    private let task: URLSessionWebSocketTask
    private var reading: Task<Void, Never>?

    init(task: URLSessionWebSocketTask) {
        self.task = task
        task.resume()
        reading = Task { [weak self] in
            while true {
                do {
                    _ = try await task.receive()
                } catch {
                    self?.isOpen = false
                    return
                }
            }
        }
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func close() {
        isOpen = false
        reading?.cancel()
        task.cancel(with: .normalClosure, reason: nil)
    }
}

/// One dashboard pointer channel. Movement is batched at the server's advertised rate; taps and
/// scrolls stay behind the movement already queued. Closed, it drops what it is given, and a
/// connection that broke is replaced on the next batch. Nothing is retained after close().
@MainActor public final class PointerController {
    /// Glasshouse refuses a batch with more moves than this.
    static let maxMoves = 120

    public var onError: (@MainActor () -> Void)?
    /// The TV it sends to; nil in tests.
    public let endpoint: Endpoint?

    private let updatesPerSecond: Int
    private let sleep: @Sendable (Duration) async -> Void
    private let connect: @MainActor () throws -> PointerChannel
    private var channel: PointerChannel?
    private var sendTask: Task<Void, Never>?
    private var queued: [PointerBatch] = []
    private var active = false

    public convenience init(client: GlasshouseClient, updatesPerSecond: Int) {
        self.init(updatesPerSecond: updatesPerSecond, endpoint: client.endpoint,
                  sleep: { try? await Task.sleep(for: $0) },
                  connect: { WebSocketPointerChannel(task: try client.pointerTask()) })
    }

    init(updatesPerSecond: Int, endpoint: Endpoint? = nil, sleep: @escaping @Sendable (Duration) async -> Void,
         connect: @escaping @MainActor () throws -> PointerChannel) {
        // The server's figure, kept within reason: 0 would divide by zero.
        self.updatesPerSecond = min(max(updatesPerSecond, 1), 1000)
        self.endpoint = endpoint
        self.sleep = sleep
        self.connect = connect
    }

    public func open() {
        guard !active else { return }
        active = true
        // Connected ahead of the first gesture; a failure here is retried by the first batch.
        _ = liveChannel()
    }

    public func move(dx: Int, dy: Int) {
        queue(.move(PointerDelta(dx: dx, dy: dy)))
    }

    public func click() {
        queue(.click)
    }

    public func scroll(dx: Int, dy: Int) {
        queue(.scroll(PointerDelta(dx: dx, dy: dy)))
    }

    private func queue(_ event: PointerBatch) {
        // Closed, a gesture is dropped: replayed later, a click would land who knows where.
        guard active else { return }
        queued.append(event)
        guard sendTask == nil else { return }
        sendTask = Task { [weak self] in
            guard let self else { return }
            if event.move != nil { await self.sleep(.milliseconds(1000 / self.updatesPerSecond)) }
            await self.flush()
        }
    }

    private func flush() async {
        while active && !queued.isEmpty {
            let batch = nextBatch()
            let text = String(decoding: (try? JSONEncoder().encode(batch)) ?? Data(), as: UTF8.self)
            // Once more on a new connection: the first send is what finds an old one broken.
            if await !deliver(text), await !deliver(text) {
                onError?()
            }
        }
        sendTask = nil
    }

    /// The first queued event, with the moves right behind it up to the server's limit.
    private func nextBatch() -> PointerBatch {
        var batch = queued.removeFirst()
        guard batch.move != nil else { return batch }
        while let next = queued.first, let move = next.move, (batch.move?.count ?? 0) < Self.maxMoves {
            batch.move?.append(contentsOf: move)
            queued.removeFirst()
        }
        return batch
    }

    private func deliver(_ text: String) async -> Bool {
        guard active, let channel = liveChannel() else { return false }
        do {
            try await channel.send(text)
            return true
        } catch {
            channel.close()
            if self.channel === channel { self.channel = nil }
            return false
        }
    }

    /// The open connection, or a new one in place of one that closed.
    private func liveChannel() -> PointerChannel? {
        if let channel, channel.isOpen { return channel }
        channel?.close()
        channel = try? connect()
        return channel
    }

    public func close() {
        active = false
        sendTask?.cancel()
        sendTask = nil
        queued.removeAll()
        channel?.close()
        channel = nil
    }
}

private extension PointerBatch {
    static func move(_ delta: PointerDelta) -> PointerBatch { PointerBatch(move: [delta]) }
    static var click: PointerBatch { PointerBatch(click: true) }
    static func scroll(_ delta: PointerDelta) -> PointerBatch { PointerBatch(scroll: delta) }
}
