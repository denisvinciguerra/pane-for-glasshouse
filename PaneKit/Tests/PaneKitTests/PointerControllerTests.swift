import XCTest
@testable import PaneKit

@MainActor
final class PointerControllerTests: XCTestCase {
    func testCapsPointerIsOptIn() throws {
        let old = try JSONDecoder().decode(Caps.self, from: Data(#"{"allowControl":true}"#.utf8))
        XCTAssertFalse(old.pointer)
        XCTAssertEqual(old.pointerRate, 120)
        let enabled = try JSONDecoder().decode(Caps.self, from: Data(#"{"pointer":true,"pointerRate":240}"#.utf8))
        XCTAssertTrue(enabled.pointer)
        XCTAssertEqual(enabled.pointerRate, 240)
    }

    func testOfflineAcceptsEverythingWithoutError() async {
        let c = PointerController.offline(updatesPerSecond: 120)
        var errors = 0
        c.onError = { errors += 1 }
        c.open(); c.move(dx: 5, dy: -3); c.click(); c.scroll(dx: 0, dy: 2)
        try? await Task.sleep(for: .milliseconds(100))
        c.close(); c.open(); c.move(dx: 1, dy: 1)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(errors, 0)
        XCTAssertNil(c.endpoint)
    }

    func testOfflineIsReplacedForARealTV() {
        let c = PointerController.offline(updatesPerSecond: 120)
        XCTAssertFalse(c.needsReplacement(for: nil))
        XCTAssertTrue(c.needsReplacement(for: Endpoint(host: "192.0.2.1", port: 8080)))
    }

    func testBatchesMovementBeforeClickAndScroll() async {
        let channel = FakePointerChannel(expecting: 3)
        let controller = PointerController(updatesPerSecond: 120, sleep: { _ in }, connect: { channel })
        controller.open()
        controller.move(dx: 4, dy: -2)
        controller.move(dx: 3, dy: 1)
        controller.click()
        controller.scroll(dx: 0, dy: 2)
        await fulfillment(of: [channel.done], timeout: 1)
        XCTAssertEqual(channel.batches, [
            PointerBatch(move: [PointerDelta(dx: 4, dy: -2), PointerDelta(dx: 3, dy: 1)]),
            PointerBatch(click: true),
            PointerBatch(scroll: PointerDelta(dx: 0, dy: 2)),
        ])
        controller.close()
    }

    func testReleaseDropsUnsentMovesButPreservesClickAndScroll() async {
        let channel = FakePointerChannel(expecting: 2)
        let controller = PointerController(updatesPerSecond: 120, sleep: { _ in }, connect: { channel })
        controller.open()
        controller.move(dx: 9, dy: -4)
        controller.click()
        controller.move(dx: 2, dy: 1)
        controller.scroll(dx: 0, dy: 1)
        controller.discardPendingMoves()
        await fulfillment(of: [channel.done], timeout: 1)
        XCTAssertEqual(channel.batches, [PointerBatch(click: true), PointerBatch(scroll: PointerDelta(dx: 0, dy: 1))])
        controller.close()
    }

    func testNewHoldCanMoveAfterPendingMovesWereDiscarded() async {
        let channel = FakePointerChannel(expecting: 1)
        let controller = PointerController(updatesPerSecond: 120, sleep: { _ in }, connect: { channel })
        controller.open()
        controller.move(dx: 50, dy: 50)
        controller.discardPendingMoves()
        controller.move(dx: 1, dy: 2)
        await fulfillment(of: [channel.done], timeout: 1)
        XCTAssertEqual(channel.batches, [PointerBatch(move: [PointerDelta(dx: 1, dy: 2)])])
        controller.close()
    }

    func testReopensAfterBackgroundClose() async {
        let first = FakePointerChannel(expecting: 1)
        let second = FakePointerChannel(expecting: 1)
        var channels = [first, second]
        let controller = PointerController(updatesPerSecond: 120, sleep: { _ in },
                                           connect: { channels.removeFirst() })
        controller.open()
        controller.close()
        XCTAssertTrue(first.closed)
        controller.open()
        controller.click()
        await fulfillment(of: [second.done], timeout: 1)
        XCTAssertEqual(second.batches, [PointerBatch(click: true)])
        controller.close()
    }

    func testCloseDropsPendingMovement() async {
        let channel = FakePointerChannel(expecting: 0)
        let controller = PointerController(updatesPerSecond: 120, sleep: parked, connect: { channel })
        controller.open()
        controller.move(dx: 1, dy: 1)
        controller.close()
        controller.click()
        XCTAssertEqual(channel.batches, [])
    }

    /// A gesture made while closed (the pins' edit, controls off) is not sent once it reopens.
    func testEventsWhileClosedAreNotReplayed() async {
        let channel = FakePointerChannel(expecting: 1)
        let controller = PointerController(updatesPerSecond: 120, sleep: { _ in }, connect: { channel })
        controller.click()
        controller.move(dx: 9, dy: 9)
        controller.open()
        controller.scroll(dx: 0, dy: 1)
        await fulfillment(of: [channel.done], timeout: 1)
        XCTAssertEqual(channel.batches, [PointerBatch(scroll: PointerDelta(dx: 0, dy: 1))])
        controller.close()
    }

    /// Glasshouse restarted: the send fails, the batch goes again on a new connection.
    func testFailedSendReconnectsAndResends() async {
        let broken = FakePointerChannel(expecting: 0)
        broken.failsSends = true
        let fresh = FakePointerChannel(expecting: 1)
        var channels = [broken, fresh]
        let controller = PointerController(updatesPerSecond: 120, sleep: { _ in },
                                           connect: { channels.removeFirst() })
        controller.open()
        controller.click()
        await fulfillment(of: [fresh.done], timeout: 1)
        XCTAssertTrue(broken.closed)
        XCTAssertEqual(fresh.batches, [PointerBatch(click: true)])
        controller.close()
    }

    /// A connection the server closed is replaced before the next batch, not written to.
    func testClosedChannelIsReplacedBeforeSending() async {
        let first = FakePointerChannel(expecting: 1)
        let second = FakePointerChannel(expecting: 1)
        var channels = [first, second]
        let controller = PointerController(updatesPerSecond: 120, sleep: { _ in },
                                           connect: { channels.removeFirst() })
        controller.open()
        controller.click()
        await fulfillment(of: [first.done], timeout: 1)
        first.isOpen = false
        controller.click()
        await fulfillment(of: [second.done], timeout: 1)
        XCTAssertEqual(first.batches.count, 1)
        XCTAssertEqual(second.batches, [PointerBatch(click: true)])
        controller.close()
    }

    /// Glasshouse refuses a batch of more than 120 moves whole.
    func testSplitsMovesAtTheServerLimit() async {
        let channel = FakePointerChannel(expecting: 2)
        let controller = PointerController(updatesPerSecond: 120, sleep: { _ in }, connect: { channel })
        controller.open()
        for _ in 0..<130 { controller.move(dx: 1, dy: 0) }
        await fulfillment(of: [channel.done], timeout: 1)
        XCTAssertEqual(channel.batches.map { $0.move?.count }, [120, 10])
        controller.close()
    }

    func testZeroRateStillSends() async {
        let channel = FakePointerChannel(expecting: 1)
        let controller = PointerController(updatesPerSecond: 0, sleep: { _ in }, connect: { channel })
        controller.open()
        controller.move(dx: 1, dy: 1)
        await fulfillment(of: [channel.done], timeout: 1)
        controller.close()
    }
}

/// Records the batches it carries; `failsSends` makes every send throw.
@MainActor private final class FakePointerChannel: PointerChannel {
    let done: XCTestExpectation
    var isOpen = true
    var failsSends = false
    private(set) var closed = false
    private(set) var batches: [PointerBatch] = []

    init(expecting count: Int) {
        done = XCTestExpectation(description: "\(count) batches")
        done.expectedFulfillmentCount = max(count, 1)
        done.isInverted = count == 0
    }

    func send(_ text: String) async throws {
        if failsSends { throw URLError(.networkConnectionLost) }
        batches.append(try JSONDecoder().decode(PointerBatch.self, from: Data(text.utf8)))
        done.fulfill()
    }

    func close() {
        closed = true
        isOpen = false
    }
}
