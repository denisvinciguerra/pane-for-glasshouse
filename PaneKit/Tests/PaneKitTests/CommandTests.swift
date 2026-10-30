import XCTest
@testable import PaneKit

final class CommandTests: XCTestCase {
    func testRcuBody() {
        XCTAssertEqual(Command.rcu(.up).body, ["action": "rcu", "value": "up"])
    }
    func testMediaBody() {
        XCTAssertEqual(Command.media(.playPause).body, ["action": "media", "value": "playPause"])
    }
    func testVolumeStepBody() {
        XCTAssertEqual(Command.volumeStep(-1).body, ["action": "volumeStep", "value": -1])
    }
    func testMuteBody() {
        XCTAssertEqual(Command.mute(true).body, ["action": "mute", "value": true])
    }
    func testLgSettingSwitchBody() {
        XCTAssertEqual(Command.lgSetting(id: "eyeComfortMode", .bool(true)).body,
                       ["action": "lgSetting", "value": ["id": "eyeComfortMode", "on": true]])
    }
    func testLgSettingValueBody() {
        XCTAssertEqual(Command.lgSetting(id: "backlight", .number(80)).body,
                       ["action": "lgSetting", "value": ["id": "backlight", "value": 80]])
        XCTAssertEqual(Command.lgSetting(id: "x", .string("off")).body,
                       ["action": "lgSetting", "value": ["id": "x", "value": "off"]])
    }
    func testScreenOffHasNoValue() {
        XCTAssertEqual(Command.screenOff.body, ["action": "screenOff"])
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}
