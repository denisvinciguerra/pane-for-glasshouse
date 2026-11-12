import XCTest
import os
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

    func testBatchesMovementBeforeClickAndScroll() async {
        let batches = OSAllocatedUnfairLock(initialState: [PointerBatch]())
        let done = expectation(description: "three batches")
        let controller = PointerController(updatesPerSecond: 120, sleep: { _ in }, sender: { batch in
            batches.withLock { $0.append(batch) }
            if batches.withLock({ $0.count }) == 3 { done.fulfill() }
        })
        controller.open()
        controller.move(dx: 4, dy: -2)
        controller.move(dx: 3, dy: 1)
        controller.click()
        controller.scroll(dx: 0, dy: 2)
        await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(batches.withLock { $0 }, [
            PointerBatch(move: [PointerDelta(dx: 4, dy: -2), PointerDelta(dx: 3, dy: 1)]),
            PointerBatch(click: true),
            PointerBatch(scroll: PointerDelta(dx: 0, dy: 2)),
        ])
        controller.close()
    }

    func testReopensAfterBackgroundClose() async {
        let sent = expectation(description: "sent after reopening")
        let controller = PointerController(updatesPerSecond: 120, sleep: { _ in }, sender: { batch in
            XCTAssertEqual(batch, PointerBatch(click: true))
            sent.fulfill()
        })
        controller.open()
        controller.close()
        controller.open()
        controller.click()
        await fulfillment(of: [sent], timeout: 1)
        controller.close()
    }

    func testCloseDropsPendingMovement() async {
        let controller = PointerController(updatesPerSecond: 120, sleep: parked, sender: { _ in
            XCTFail("a closed controller sent an event")
        })
        controller.open()
        controller.move(dx: 1, dy: 1)
        controller.close()
        controller.click()
    }
}
