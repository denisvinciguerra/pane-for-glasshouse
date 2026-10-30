import XCTest
@testable import PaneKit

@MainActor
final class KeymapStoreTests: XCTestCase {
    private func scratchDefaults() -> UserDefaults {
        let name = "PaneKitTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    private func editing(_ slots: [ButtonID: KeySlot], home: String = "j") -> [ButtonID: KeySlot] {
        var slots = slots
        slots[.rcu(.home)] = KeySlot(primary: KeyBinding(.character(home)))
        return slots
    }

    private func legacy(_ d: UserDefaults, profile: KeyProfile, slots: [ButtonID: KeySlot]) {
        d.set(profile.rawValue, forKey: "keyProfile")
        let encodable = Dictionary(uniqueKeysWithValues: slots.map { ($0.key.rawValue, $0.value) })
        d.set(try! JSONEncoder().encode(encodable), forKey: "keymap")
    }

    func testDefaultsToArrowsWithoutCustom() {
        let s = KeymapStore(defaults: scratchDefaults())
        XCTAssertEqual(s.choice, .profile(.arrows))
        XCTAssertNil(s.custom)
        XCTAssertEqual(s.slots, KeyProfile.arrows.slots)
    }

    func testEditingAProfileMakesCustomFromItAndPersists() {
        let d = scratchDefaults()
        let s = KeymapStore(defaults: d)
        s.choose(.profile(.gaming))
        let edited = editing(KeyProfile.gaming.slots)
        XCTAssertFalse(s.replacesCustom(with: edited))
        s.set(edited)
        XCTAssertEqual(s.choice, .custom)
        XCTAssertEqual(s.custom, CustomKeymap(base: .gaming, slots: edited))
        XCTAssertEqual(s.slots, edited)
        let t = KeymapStore(defaults: d)
        XCTAssertEqual(t.choice, .custom)
        XCTAssertEqual(t.custom, CustomKeymap(base: .gaming, slots: edited))
        XCTAssertEqual(t.slots, edited)
    }

    func testChoosingAProfileKeepsCustomAndChoosingCustomBringsItBack() {
        let d = scratchDefaults()
        let s = KeymapStore(defaults: d)
        let edited = editing(KeyProfile.arrows.slots)
        s.set(edited)
        s.choose(.profile(.gaming))
        XCTAssertEqual(s.slots, KeyProfile.gaming.slots)
        XCTAssertEqual(s.custom?.slots, edited)
        let t = KeymapStore(defaults: d)
        XCTAssertEqual(t.choice, .profile(.gaming))
        XCTAssertEqual(t.slots, KeyProfile.gaming.slots)
        t.choose(.custom)
        XCTAssertEqual(t.choice, .custom)
        XCTAssertEqual(t.slots, edited)
    }

    func testChoosingCustomWithoutOneDoesNothing() {
        let s = KeymapStore(defaults: scratchDefaults())
        s.choose(.custom)
        XCTAssertEqual(s.choice, .profile(.arrows))
        XCTAssertEqual(s.slots, KeyProfile.arrows.slots)
    }

    func testOnlyAChangeFromAProfileReplacesAnExistingCustom() {
        let s = KeymapStore(defaults: scratchDefaults())
        s.set(editing(KeyProfile.arrows.slots))
        XCTAssertFalse(s.replacesCustom(with: editing(s.slots, home: "y")), "already on Custom")
        s.choose(.profile(.gaming))
        XCTAssertTrue(s.replacesCustom(with: editing(KeyProfile.gaming.slots)))
        XCTAssertFalse(s.replacesCustom(with: KeyProfile.gaming.slots), "nothing changes")
        var actionOnly = KeyProfile.gaming.slots
        actionOnly[.action(UUID())] = KeySlot(primary: KeyBinding(.character("1"), modifiers: .command))
        XCTAssertFalse(s.replacesCustom(with: actionOnly), "an action's key is not the profile's")
    }

    func testEditingAProfileReplacesCustomFromThatProfile() {
        let s = KeymapStore(defaults: scratchDefaults())
        s.set(editing(KeyProfile.arrows.slots))
        s.choose(.profile(.gaming))
        let edited = editing(KeyProfile.gaming.slots, home: "y")
        s.set(edited)
        XCTAssertEqual(s.choice, .custom)
        XCTAssertEqual(s.custom, CustomKeymap(base: .gaming, slots: edited))
    }

    func testUnchangedKeysLeaveTheProfile() {
        let s = KeymapStore(defaults: scratchDefaults())
        var slots = KeyProfile.arrows.slots
        slots[.action(UUID())] = KeySlot(primary: KeyBinding(.character("1"), modifiers: .command))
        s.set(slots)
        XCTAssertEqual(s.choice, .profile(.arrows))
        XCTAssertNil(s.custom)
    }

    func testSetDropsActionIDs() {
        let s = KeymapStore(defaults: scratchDefaults())
        var slots = KeyProfile.arrows.slots
        slots[.action(UUID())] = KeySlot(primary: KeyBinding(.character("1"), modifiers: .command))
        slots[.source("hdmi1")] = KeySlot(primary: KeyBinding(.character("2")))
        s.set(slots)
        XCTAssertTrue(s.slots.keys.allSatisfy { $0.actionID == nil })
        XCTAssertNotNil(s.slots[.source("hdmi1")])
        XCTAssertEqual(s.choice, .custom)
    }

    func testResetPutsCustomBackToItsProfile() {
        let d = scratchDefaults()
        let s = KeymapStore(defaults: d)
        XCTAssertFalse(s.canReset)
        s.choose(.profile(.gaming))
        s.set(editing(KeyProfile.gaming.slots))
        XCTAssertTrue(s.canReset)
        s.reset()
        XCTAssertEqual(s.choice, .custom)
        XCTAssertEqual(s.custom, CustomKeymap(base: .gaming, slots: KeyProfile.gaming.slots))
        XCTAssertFalse(s.canReset)
        XCTAssertEqual(KeymapStore(defaults: d).slots, KeyProfile.gaming.slots)
    }

    func testResetIsOffOnAProfile() {
        let s = KeymapStore(defaults: scratchDefaults())
        let edited = editing(KeyProfile.arrows.slots)
        s.set(edited)
        s.choose(.profile(.arrows))
        XCTAssertFalse(s.canReset)
        s.reset()
        XCTAssertEqual(s.custom?.slots, edited)
    }

    func testLegacyCustomisedKeymapBecomesCustom() {
        let d = scratchDefaults()
        let edited = editing(KeyProfile.gaming.slots)
        legacy(d, profile: .gaming, slots: edited)
        let s = KeymapStore(defaults: d)
        XCTAssertEqual(s.choice, .custom)
        XCTAssertEqual(s.custom, CustomKeymap(base: .gaming, slots: edited))
        s.choose(.profile(.arrows))
        let t = KeymapStore(defaults: d)
        XCTAssertNil(d.object(forKey: "keymap"))
        XCTAssertEqual(t.choice, .profile(.arrows))
        XCTAssertEqual(t.custom, CustomKeymap(base: .gaming, slots: edited))
    }

    func testLegacyKeymapEqualToItsProfileIsThatProfile() {
        let d = scratchDefaults()
        legacy(d, profile: .gaming, slots: KeyProfile.gaming.slots)
        let s = KeymapStore(defaults: d)
        XCTAssertEqual(s.choice, .profile(.gaming))
        XCTAssertNil(s.custom)
    }

    func testCorruptDataFallsBackToArrows() {
        let d = scratchDefaults()
        d.set(Data("x".utf8), forKey: "keymap")
        d.set("azerty", forKey: "keyProfile")
        let s = KeymapStore(defaults: d)
        XCTAssertEqual(s.choice, .profile(.arrows))
        XCTAssertNil(s.custom)
        XCTAssertEqual(s.slots, KeyProfile.arrows.slots)
    }

    func testUnreadableCustomFallsBackToArrows() {
        let d = scratchDefaults()
        d.set("custom", forKey: "keyProfile")
        d.set(Data("x".utf8), forKey: "customKeymap")
        let s = KeymapStore(defaults: d)
        XCTAssertEqual(s.choice, .profile(.arrows))
        XCTAssertNil(s.custom)
        XCTAssertEqual(s.slots, KeyProfile.arrows.slots)
    }
}
