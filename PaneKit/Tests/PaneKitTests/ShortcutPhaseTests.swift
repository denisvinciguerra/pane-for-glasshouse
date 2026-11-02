import XCTest
@testable import PaneKit

final class ShortcutPhaseTests: XCTestCase {
    func testPhaseAfterEachResult() {
        let en = lproj("en")
        XCTAssertEqual(ShortcutPhase.after(.sent, launchesApp: false, bundle: en), .done("Sent to the TV"))
        XCTAssertEqual(ShortcutPhase.after(.sent, launchesApp: true, bundle: en), .done("Launched on the TV"))
        XCTAssertEqual(ShortcutPhase.after(.failed("No way"), launchesApp: false, bundle: en), .failed("No way"))
        XCTAssertEqual(ShortcutPhase.after(.cancelled, launchesApp: true, bundle: en), .failed("Action cancelled"))
        XCTAssertNil(ShortcutPhase.after(.replaced, launchesApp: false, bundle: en), "the card already belongs to the next shortcut")
    }

    func testPhaseTextsAreFrench() {
        let fr = lproj("fr")
        XCTAssertEqual(ShortcutPhase.after(.sent, launchesApp: false, bundle: fr), .done("Envoyé à la TV"))
        XCTAssertEqual(ShortcutPhase.after(.sent, launchesApp: true, bundle: fr), .done("Lancé sur la TV"))
        XCTAssertEqual(ShortcutPhase.after(.cancelled, launchesApp: false, bundle: fr), .failed("Action annulée"))
    }

    func testPublicOverloadUsesTheModuleBundle() {
        XCTAssertEqual(ShortcutPhase.after(.cancelled, launchesApp: false), .failed(SessionText.cancelled()))
    }
}
