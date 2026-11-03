import XCTest
@testable import PaneKit

final class HIDKeyCodesTests: XCTestCase {
    func testLettersByPosition() {
        XCTAssertEqual(HIDKeyCodes.macKeyCode(hidUsage: 0x04), 0x00)   // A → kVK_ANSI_A
        XCTAssertEqual(HIDKeyCodes.macKeyCode(hidUsage: 0x1A), 0x0D)   // W → kVK_ANSI_W
        XCTAssertEqual(HIDKeyCodes.macKeyCode(hidUsage: 0x1D), 0x06)   // Z → kVK_ANSI_Z
    }

    func testSpecialKeys() {
        XCTAssertEqual(HIDKeyCodes.macKeyCode(hidUsage: 0x52), 0x7E)   // ↑
        XCTAssertEqual(HIDKeyCodes.macKeyCode(hidUsage: 0x28), 0x24)   // Return
        XCTAssertEqual(HIDKeyCodes.macKeyCode(hidUsage: 0x29), 0x35)   // Escape
        XCTAssertEqual(HIDKeyCodes.macKeyCode(hidUsage: 0x2C), 0x31)   // Space
        XCTAssertEqual(HIDKeyCodes.macKeyCode(hidUsage: 0x2A), 51)     // ⌫, which clears a recorder
        XCTAssertEqual(HIDKeyCodes.macKeyCode(hidUsage: 0x58), KeyCode.keypadEnter)
    }

    func testFunctionKeys() {
        XCTAssertEqual(HIDKeyCodes.macKeyCode(hidUsage: 0x3A), 122)    // F1
        XCTAssertEqual(HIDKeyCodes.macKeyCode(hidUsage: 0x45), 111)    // F12
    }

    /// Every key the profiles hold by position has its HID usage.
    func testProfilesPositionalKeysAreReachable() {
        let reachable = Set((0..<0x100).compactMap { HIDKeyCodes.macKeyCode(hidUsage: $0) })
        for profile in KeyProfile.allCases {
            for slot in profile.slots.values {
                for binding in [slot.primary, slot.alternate].compactMap({ $0 }) {
                    if case .keyCode(let code) = binding.trigger { XCTAssertTrue(reachable.contains(code), "\(code)") }
                }
            }
        }
    }

    func testUnknownAndModifierUsagesHaveNoCode() {
        XCTAssertNil(HIDKeyCodes.macKeyCode(hidUsage: 0xFFFF))
        XCTAssertNil(HIDKeyCodes.macKeyCode(hidUsage: 0xE2))           // left Option alone
        XCTAssertNil(HIDKeyCodes.macKeyCode(hidUsage: -1))
    }
}
