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

/// One dashboard pointer channel. Movement is batched at the server's advertised rate; taps and
/// scrolls stay behind the movement already queued. Nothing is retained after close().
@MainActor public final class PointerController {
    public var onError: (@MainActor () -> Void)?

    private let client: GlasshouseClient?
    private let updatesPerSecond: Int
    private let sleep: @Sendable (Duration) async -> Void
    private let testSender: (@MainActor (PointerBatch) async -> Void)?
    private var socket: URLSessionWebSocketTask?
    private var sendTask: Task<Void, Never>?
    private var queued: [PointerBatch] = []
    private var active = false

    public init(client: GlasshouseClient, updatesPerSecond: Int) {
        self.client = client
        self.updatesPerSecond = updatesPerSecond
        self.sleep = { try? await Task.sleep(for: $0) }
        self.testSender = nil
    }

    init(updatesPerSecond: Int, sleep: @escaping @Sendable (Duration) async -> Void,
         sender: @escaping @MainActor (PointerBatch) async -> Void) {
        self.client = nil
        self.updatesPerSecond = updatesPerSecond
        self.sleep = sleep
        self.testSender = sender
    }

    public func open() {
        guard !active else { return }
        active = true
        if testSender != nil { return }
        do {
            socket = try client?.pointerTask()
            socket?.resume()
        } catch {
            active = false
            onError?()
        }
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
        queued.append(event)
        guard active, sendTask == nil else { return }
        sendTask = Task { [weak self] in
            guard let self else { return }
            if event.move != nil { await self.sleep(.milliseconds(1000 / self.updatesPerSecond)) }
            await self.flush()
        }
    }

    private func flush() async {
        while active && !queued.isEmpty {
            var batch = queued.removeFirst()
            if batch.move != nil {
                while let next = queued.first, let move = next.move {
                    batch.move?.append(contentsOf: move)
                    queued.removeFirst()
                }
            }
            do {
                let text = String(decoding: try JSONEncoder().encode(batch), as: UTF8.self)
                if let testSender {
                    await testSender(batch)
                } else if let socket {
                    try await socket.send(.string(text))
                }
            } catch {
                onError?()
            }
        }
        sendTask = nil
    }

    public func close() {
        active = false
        sendTask?.cancel()
        sendTask = nil
        queued.removeAll()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }
}

private extension PointerBatch {
    static func move(_ delta: PointerDelta) -> PointerBatch { PointerBatch(move: [delta]) }
    static var click: PointerBatch { PointerBatch(click: true) }
    static func scroll(_ delta: PointerDelta) -> PointerBatch { PointerBatch(scroll: delta) }
}
