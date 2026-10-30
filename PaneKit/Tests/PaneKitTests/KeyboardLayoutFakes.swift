import XCTest
@testable import PaneKit

struct FakeLayout: KeyboardLayout {
    let map: [UInt16: String]
    func character(for keyCode: UInt16) -> String? { map[keyCode] }
}
let qwerty = FakeLayout(map: [0: "a", 1: "s", 2: "d", 12: "q", 13: "w", 14: "e", 4: "h"])
let azerty = FakeLayout(map: [0: "q", 1: "s", 2: "d", 12: "a", 13: "z", 14: "e", 4: "h"])
