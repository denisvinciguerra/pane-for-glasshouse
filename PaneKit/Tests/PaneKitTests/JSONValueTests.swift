import XCTest
@testable import PaneKit

final class JSONValueTests: XCTestCase {
    func testDecodesNestedAndSubscripts() throws {
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":{"b":[1,"x",true,null]}}"#.utf8))
        XCTAssertEqual(v["a"]?["b"], .array([.number(1), .string("x"), .bool(true), .null]))
    }

    func testRoundTripsObject() throws {
        let v: JSONValue = .object(["id": .string("backlight"), "value": .number(80)])
        let back = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(v))
        XCTAssertEqual(back, v)
    }
}
