import XCTest
@testable import PaneKit

@MainActor
final class ActionStoreTests: XCTestCase {
    private func scratchDefaults() -> UserDefaults {
        let name = "PaneKitTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    private func action(_ title: String = "A") -> CustomAction { CustomAction(title: title, steps: [.screenOff]) }

    func testActionsArePerTV() {
        let s = ActionStore(defaults: scratchDefaults())
        let a = UUID(), b = UUID()
        let act = action()
        s.save(act, for: a)
        XCTAssertEqual(s.actions(for: a), [act])
        XCTAssertEqual(s.actions(for: b), [])
    }

    func testSaveReplacesSameID() {
        let s = ActionStore(defaults: scratchDefaults())
        let tv = UUID()
        var act = action()
        s.save(act, for: tv)
        act.title = "B"
        s.save(act, for: tv)
        XCTAssertEqual(s.actions(for: tv).map(\.title), ["B"])
    }

    func testPinOrderPersists() {
        let d = scratchDefaults()
        let s = ActionStore(defaults: d)
        let tv = UUID()
        let acts = [action("1"), action("2"), action("3")]
        acts.forEach { s.save($0, for: tv); s.pin($0.id, for: tv) }
        s.movePin(for: tv, from: [2], to: 0)
        let expected = [acts[2], acts[0], acts[1]]
        XCTAssertEqual(s.pinned(for: tv), expected)
        XCTAssertEqual(ActionStore(defaults: d).pinned(for: tv), expected)
    }

    func testMovePinCountsOnlyTheShownPins() throws {
        let d = scratchDefaults()
        let tv = UUID()
        let acts = [action("1"), action("2")]
        let saved = try JSONEncoder().encode([tv.uuidString: acts])
        d.set(saved, forKey: "actions")
        // A pin whose action is gone (unreadable, say) sits between the two shown ones.
        let pins = try JSONEncoder().encode([tv.uuidString: [acts[0].id, UUID(), acts[1].id]])
        d.set(pins, forKey: "pins")
        let s = ActionStore(defaults: d)
        s.movePin(for: tv, from: [1], to: 0)
        XCTAssertEqual(s.pinned(for: tv), [acts[1], acts[0]])
    }

    func testDeleteAlsoUnpins() {
        let s = ActionStore(defaults: scratchDefaults())
        let tv = UUID(), act = action()
        s.save(act, for: tv); s.pin(act.id, for: tv)
        s.delete(act.id, for: tv)
        XCTAssertEqual(s.actions(for: tv), [])
        XCTAssertFalse(s.isPinned(act.id, for: tv))
        s.save(act, for: tv)
        XCTAssertEqual(s.pinned(for: tv), [])
    }

    func testPinTwiceKeepsOne() {
        let s = ActionStore(defaults: scratchDefaults())
        let tv = UUID(), act = action()
        s.save(act, for: tv)
        s.pin(act.id, for: tv); s.pin(act.id, for: tv)
        XCTAssertEqual(s.pinned(for: tv), [act])
        s.unpin(act.id, for: tv)
        XCTAssertFalse(s.isPinned(act.id, for: tv))
    }

    func testKeySlots() {
        let s = ActionStore(defaults: scratchDefaults())
        let tv = UUID(), act = action(), other = action("other")
        s.save(act, for: tv); s.save(other, for: tv)
        let key = KeyBinding(.character("1"), modifiers: .command)
        s.setKey(key, action: act.id, for: tv)
        XCTAssertEqual(s.keySlots(for: tv)[.action(act.id)]?.primary, key)
        XCTAssertNil(s.keySlots(for: tv)[.action(other.id)])
        s.setKey(nil, action: act.id, for: tv)
        XCTAssertNil(s.keySlots(for: tv)[.action(act.id)])
    }

    func testForgetTVRemovesItsActionsOnly() {
        let s = ActionStore(defaults: scratchDefaults())
        let a = UUID(), b = UUID(), x = action("x"), y = action("y")
        s.save(x, for: a); s.pin(x.id, for: a); s.save(y, for: b); s.pin(y.id, for: b)
        s.forget(tv: a)
        XCTAssertEqual(s.actions(for: a), [])
        XCTAssertEqual(s.pinned(for: a), [])
        XCTAssertEqual(s.pinned(for: b), [y])
    }

    func testUndecodableActionIsSkipped() throws {
        let d = scratchDefaults()
        let a = UUID(), b = UUID(), good = action("good")
        let goodJSON = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
        let bad = "{\"id\":\"\(UUID().uuidString)\",\"title\":\"x\",\"steps\":[{\"kind\":\"teleport\"}]}"
        let json = "{\"\(a.uuidString)\":[\(goodJSON),\(bad)],\"\(b.uuidString)\":[\(goodJSON)]}"
        d.set(Data(json.utf8), forKey: "actions")
        let s = ActionStore(defaults: d)
        XCTAssertEqual(s.actions(for: a), [good])
        XCTAssertEqual(s.actions(for: b), [good])
    }

    func testCorruptTopLevelIsEmpty() {
        let d = scratchDefaults()
        d.set(Data("garbage".utf8), forKey: "actions")
        d.set(Data("[1,2".utf8), forKey: "pins")
        let s = ActionStore(defaults: d)
        let tv = UUID()
        XCTAssertEqual(s.actions(for: tv), [])
        s.save(action(), for: tv)
        XCTAssertEqual(s.actions(for: tv).count, 1)
    }

    func testDuplicateIDsInStoredDataAreDeduped() throws {
        let d = scratchDefaults()
        let tv = UUID()
        let key = KeyBinding(.character("1"), modifiers: .command)
        let act = CustomAction(title: "dup", steps: [.screenOff], key: key)
        let json = String(decoding: try JSONEncoder().encode(act), as: UTF8.self)
        d.set(Data("{\"\(tv.uuidString)\":[\(json),\(json)]}".utf8), forKey: "actions")
        d.set(Data("{\"\(tv.uuidString)\":[\"\(act.id.uuidString)\",\"\(act.id.uuidString)\"]}".utf8), forKey: "pins")
        let s = ActionStore(defaults: d)
        XCTAssertEqual(s.actions(for: tv).count, 1)
        XCTAssertEqual(s.keySlots(for: tv)[.action(act.id)]?.primary, key)
        XCTAssertEqual(s.pinned(for: tv).count, 1)
    }

    func testIsPinnedOnlyStepWantsAPinnedSingleStepAction() {
        let s = ActionStore(defaults: scratchDefaults())
        let tv = UUID()
        let step = ActionStep.setting(id: "g", section: "game", title: "G", value: .bool(true), valueLabel: "ON")
        let same = ActionStep.setting(id: "g", section: "game", title: "Game", value: .bool(true), valueLabel: "Oui")
        let pair = CustomAction(title: "Pair", steps: [.button(.source("hdmi4")), step])
        s.save(pair, for: tv); s.pin(pair.id, for: tv)
        XCTAssertFalse(s.isPinned(onlyStep: same, for: tv), "an action of two steps is not this step")
        let single = CustomAction(title: "Single", steps: [step])
        s.save(single, for: tv)
        XCTAssertFalse(s.isPinned(onlyStep: same, for: tv), "saved but not pinned")
        s.pin(single.id, for: tv)
        XCTAssertTrue(s.isPinned(onlyStep: same, for: tv))
        XCTAssertFalse(s.isPinned(onlyStep: same, for: UUID()), "pins are per TV")
    }
}
