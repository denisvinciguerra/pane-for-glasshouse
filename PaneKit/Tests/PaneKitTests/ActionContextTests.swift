import XCTest
@testable import PaneKit

final class ActionContextTests: XCTestCase {
    private func context() throws -> ActionContext {
        let stats = try JSONDecoder().decode(Stats.self, from: Fixture.data("stats"))
        let picture = try JSONDecoder().decode(PicturePayload.self, from: Fixture.data("picture"))
        let game = try JSONDecoder().decode(GamePayload.self, from: Fixture.data("game"))
        return ActionContext(stats: stats, rows: picture.rows + (game.rows ?? []))
    }

    private func row(_ json: String) throws -> SettingRow { try JSONDecoder().decode(SettingRow.self, from: Data(json.utf8)) }

    func testMissingAppIsUnavailable() throws {
        let c = try context()
        XCTAssertEqual(c.unavailableReason(.launchApp(id: "gone.app", title: "G"), bundle: lproj("en")), "App not installed on this TV")
        XCTAssertEqual(c.unavailableReason(.launchApp(id: "gone.app", title: "G"), bundle: lproj("fr")), "App non installée sur cette TV")
        XCTAssertNil(c.unavailableReason(.launchApp(id: "com.apple.appletv", title: "Apple TV")))
        XCTAssertEqual(c.apps.map(\.title), c.apps.map(\.title).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    func testMissingInputIsUnavailable() throws {
        let c = try context()
        XCTAssertEqual(c.unavailableReason(.button(.source("hdmi9")), bundle: lproj("en")), "Input not found on this TV")
        XCTAssertEqual(c.unavailableReason(.button(.source("hdmi9")), bundle: lproj("fr")), "Entrée introuvable sur cette TV")
        XCTAssertNil(c.unavailableReason(.button(.source("hdmi4"))))
        XCTAssertNil(c.unavailableReason(.button(.source("livetv"))))
    }

    func testPictureModeOfAnotherSignal() throws {
        let c = try context()
        XCTAssertEqual(c.unavailableReason(.pictureMode(value: "vivid", label: "Vivid"), bundle: lproj("en")),
                       "Picture mode not available for this signal")
        XCTAssertEqual(c.unavailableReason(.pictureMode(value: "vivid", label: "Vivid"), bundle: lproj("fr")),
                       "Mode d’image indisponible pour ce signal")
        XCTAssertNil(c.unavailableReason(.pictureMode(value: "hdrGame", label: "Game")))
        XCTAssertNotNil(c.pictureModes)
    }

    func testUnknownWhenNotLoaded() {
        let c = ActionContext(stats: nil, rows: [])
        XCTAssertNil(c.unavailableReason(.launchApp(id: "x", title: "X")))
        XCTAssertNil(c.unavailableReason(.button(.source("hdmi9"))))
        XCTAssertNil(c.unavailableReason(.pictureMode(value: "vivid", label: "V")))
        XCTAssertNil(c.unavailableReason(.setting(id: "x", section: "game", title: "X", value: .bool(true), valueLabel: "ON")))
        XCTAssertNil(c.pictureModes)
        XCTAssertTrue(c.apps.isEmpty)
    }

    func testSettingInLoadedSectionMissing() throws {
        let c = try context()
        let missing = ActionStep.setting(id: "nope", section: "game", title: "N", value: .bool(true), valueLabel: "ON")
        XCTAssertEqual(c.unavailableReason(missing, bundle: lproj("en")), "Setting not found on this TV")
        XCTAssertEqual(c.unavailableReason(missing, bundle: lproj("fr")), "Réglage introuvable sur cette TV")
        XCTAssertNil(c.unavailableReason(.setting(id: "gameOptimization", section: "game", title: "G", value: .bool(true), valueLabel: "ON")))
        XCTAssertNil(c.unavailableReason(.setting(id: "nope", section: "sound", title: "N", value: .bool(true), valueLabel: "ON")),
                     "a section that is not loaded is unknown")
        XCTAssertFalse(c.rows(section: "game").isEmpty)
    }

    func testInactiveRowGivesItsReason() throws {
        let r = try row(#"{"id":"r","section":"picture","title":"R","type":"switch","on":false,"active":false,"inactive":"game"}"#)
        let c = ActionContext(stats: nil, rows: [r])
        let step = ActionStep.setting(id: "r", section: "picture", title: "R", value: .bool(true), valueLabel: "ON")
        XCTAssertEqual(c.unavailableReason(step, bundle: lproj("en")), "Not used in Game mode.")
        let plain = try row(#"{"id":"r","section":"picture","title":"R","type":"switch","on":false,"active":false}"#)
        XCTAssertEqual(ActionContext(stats: nil, rows: [plain]).unavailableReason(step, bundle: lproj("en")),
                       "Not available with the TV’s current input or sound output.")
    }

    func testRowsOfSectionKeepsSupportedKindsOnly() throws {
        let t = try row(#"{"id":"t","section":"s","title":"T","type":"switch","on":true}"#)
        let u = try row(#"{"id":"u","section":"s","title":"U","type":"weird"}"#)
        XCTAssertEqual(ActionContext(stats: nil, rows: [t, u]).rows(section: "s").map(\.id), ["t"])
    }

    func testEmptyActionHasReason() throws {
        let c = try context()
        XCTAssertEqual(c.unavailableReason(CustomAction(title: "E", steps: []), bundle: lproj("en")), "This action has no steps")
        XCTAssertEqual(c.unavailableReason(CustomAction(title: "E", steps: []), bundle: lproj("fr")), "Cette action n’a pas d’étape")
        let blocked = CustomAction(title: "B", steps: [.screenOn, .button(.source("hdmi9")), .launchApp(id: "gone", title: "G")])
        XCTAssertEqual(c.unavailableReason(blocked, bundle: lproj("en")), "Input not found on this TV")
        XCTAssertNil(c.unavailableReason(CustomAction(title: "OK", steps: [.screenOn])))
    }

    func testUnknownButtonIsUnavailable() throws {
        let c = ActionContext(stats: nil, rows: [])
        let unknown = ActionStep.button(ButtonID(rawValue: "future.thing"))
        XCTAssertEqual(c.unavailableReason(unknown, bundle: lproj("en")), "Unknown button")
        XCTAssertEqual(c.unavailableReason(unknown, bundle: lproj("fr")), "Bouton inconnu")
        XCTAssertEqual(c.unavailableReason(.button(.action(UUID())), bundle: lproj("en")), "Unknown button")
    }
}
