import XCTest
@testable import PaneKit

final class RowLayoutTests: XCTestCase {
    /// The texts are asserted in English whatever the Mac's language is.
    private let en = RowLayoutTests.lproj("en")
    private let fr = RowLayoutTests.lproj("fr")

    private static func lproj(_ code: String) -> Bundle {
        guard let path = PaneKitResources.bundle.path(forResource: code, ofType: "lproj"), let b = Bundle(path: path)
        else { fatalError("Missing \(code).lproj") }
        return b
    }

    func testFrenchCatalog() throws {
        let rows = try picture() + [try make("loose")]
        let titles = RowLayout.picture(rows, bundle: fr).groups.compactMap(\.title)
        XCTAssertEqual(titles, ["Luminosité", "Couleur", "Netteté", "Mouvement", "Format d’image", "Balance des blancs", "Autres"])
        XCTAssertEqual(RowLayout.picture(rows, bundle: en).groups.last?.title, "Other")
        XCTAssertEqual(RowLayout.inactiveReason(try make("a", active: false, inactive: "game"), bundle: fr), "Inutilisé en mode Jeu.")
        XCTAssertEqual(RowLayout.inactiveReason(try make("a", active: false, inactive: "colourAdjustment"), bundle: fr),
                       "Réglez Ajustement des couleurs sur Sélection utilisateur pour les utiliser.")
        XCTAssertEqual(RowLayout.inactiveReason(try make("a", active: false), bundle: fr),
                       "Indisponible avec l’entrée ou la sortie son actuelle du téléviseur.")
    }

    private func picture() throws -> [SettingRow] {
        try JSONDecoder().decode(PicturePayload.self, from: Fixture.data("picture")).rows
    }

    private func make(_ id: String, group: String? = nil, track: String? = nil, min: Double = 0, active: Bool = true,
                      inactive: String? = nil) throws -> SettingRow {
        var d: [String: Any] = ["id": id, "section": "picture", "type": "number", "title": id, "value": 0, "min": min, "max": 100, "active": active]
        if let group { d["group"] = group }
        if let track { d["track"] = track }
        if let inactive { d["inactive"] = inactive }
        return try JSONDecoder().decode(SettingRow.self, from: JSONSerialization.data(withJSONObject: d))
    }

    func testPictureModeIsLiftedOut() throws {
        let r = RowLayout.picture(try picture(), bundle: en)
        XCTAssertEqual(r.mode?.id, "pictureMode")
        XCTAssertFalse(r.groups.flatMap(\.rows).contains { $0.id == "pictureMode" })
    }

    func testPictureGroupOrder() throws {
        let r = RowLayout.picture(try picture(), bundle: en)
        XCTAssertEqual(r.groups.map(\.id), ["mode", "brightness", "colour", "clarity", "motion", "aspect", "whiteBalance"])
        XCTAssertEqual(r.groups[0].rows.map(\.id), ["filmMakerMode"])
        XCTAssertNil(r.groups[0].title)
        XCTAssertEqual(r.groups[1].title, "Brightness")
        XCTAssertEqual(r.groups[5].title, "Aspect ratio")
        XCTAssertEqual(r.groups[6].title, "White balance")
        XCTAssertFalse(r.groups.contains { $0.id == "cms" })
    }

    func testUnknownGroupFallsBackToTitledId() throws {
        let rows = try picture() + [try make("curve", group: "toneCurve")]
        let last = RowLayout.picture(rows, bundle: en).groups.last
        XCTAssertEqual(last?.id, "toneCurve")
        XCTAssertEqual(last?.title, "Tone curve")
    }

    func testCmsRowsAreDropped() throws {
        let r = RowLayout.picture(try picture(), bundle: en)
        let all = r.groups.flatMap(\.rows)
        XCTAssertTrue(all.allSatisfy { $0.cms == nil })
        XCTAssertEqual(all.count, 54 - 18 - 1)
        let colour = try XCTUnwrap(r.groups.first { $0.id == "colour" })
        XCTAssertTrue(colour.rows.contains { $0.id == "dynamicColor" })
    }

    func testValueTextByTrack() throws {
        let tint = try make("tint", track: "tint", min: -50)
        XCTAssertEqual(RowLayout.valueText(tint, value: -10), "R10")
        XCTAssertEqual(RowLayout.valueText(tint, value: 10), "G10")
        XCTAssertEqual(RowLayout.valueText(tint, value: 0), "0")
        let temp = try make("t", track: "temperature", min: -50)
        XCTAssertEqual(RowLayout.valueText(temp, value: -20), "W20")
        XCTAssertEqual(RowLayout.valueText(temp, value: 20), "C20")
        let red = try make("r", track: "red", min: 0)
        XCTAssertEqual(RowLayout.valueText(red, value: 5), "+5")
        XCTAssertEqual(RowLayout.valueText(red, value: -5), "\u{2212}5")
        let signed = try make("s", min: -50)
        XCTAssertEqual(RowLayout.valueText(signed, value: 5), "+5")
        XCTAssertEqual(RowLayout.valueText(signed, value: -5), "\u{2212}5")
        XCTAssertEqual(RowLayout.valueText(try make("p"), value: 42), "42")
    }

    func testValueTextNeverTraps() throws {
        let signed = try make("s", min: -50)
        for row in [signed, try make("p"), try make("t", track: "tint", min: -50)] {
            for value in [Double.nan, .infinity, -.infinity, 1e300, -1e300] {
                XCTAssertEqual(RowLayout.valueText(row, value: value), "\u{2014}", "\(value)")
            }
        }
    }

    func testInactiveReasons() throws {
        XCTAssertEqual(RowLayout.inactiveReason(try make("a", active: false, inactive: "game"), bundle: en), "Not used in Game mode.")
        XCTAssertEqual(RowLayout.inactiveReason(try make("a", active: false, inactive: "colourAdjustment"), bundle: en),
                       "Set Colour adjustment to User Selection to use these.")
        XCTAssertEqual(RowLayout.inactiveReason(try make("a", active: false), bundle: en),
                       "Not available with the TV’s current input or sound output.")
        XCTAssertNil(RowLayout.inactiveReason(try make("a"), bundle: en))
    }

    func testPlainKeepsServerOrder() throws {
        let g = try JSONDecoder().decode(GamePayload.self, from: Fixture.data("game"))
        let rows = try XCTUnwrap(g.rows)
        let groups = RowLayout.plain(rows, section: "game")
        XCTAssertEqual(groups.count, 1)
        XCTAssertNil(groups[0].title)
        XCTAssertEqual(groups[0].rows.map(\.id), rows.map(\.id))
        XCTAssertEqual(groups[0].rows.count, 9)
    }

    func testPlainFiltersSection() throws {
        let a = try JSONDecoder().decode(AudioPayload.self, from: Fixture.data("audio"))
        let groups = RowLayout.plain(try XCTUnwrap(a.lgSettings), section: "sound")
        XCTAssertEqual(groups.first?.rows.count, 7)
    }

    func testTypedNumberIsRoundedAndKeptInRange() throws {
        let r = try JSONDecoder().decode(SettingRow.self, from: Data(
            #"{"id":"s","section":"picture","title":"S","type":"number","value":0,"min":-10,"max":50}"#.utf8))
        XCTAssertEqual(RowLayout.typedNumber("42", row: r), 42)
        XCTAssertEqual(RowLayout.typedNumber(" 7 ", row: r), 7)
        XCTAssertEqual(RowLayout.typedNumber("12.6", row: r), 13)
        XCTAssertEqual(RowLayout.typedNumber("12,4", row: r), 12, "a French decimal comma")
        XCTAssertEqual(RowLayout.typedNumber("-3", row: r), -3)
        XCTAssertEqual(RowLayout.typedNumber("\u{2212}3", row: r), -3, "the minus sign the app shows")
        XCTAssertEqual(RowLayout.typedNumber("+5", row: r), 5)
        XCTAssertEqual(RowLayout.typedNumber("999", row: r), 50)
        XCTAssertEqual(RowLayout.typedNumber("-999", row: r), -10)
        XCTAssertNil(RowLayout.typedNumber("", row: r))
        XCTAssertNil(RowLayout.typedNumber("-", row: r))
        XCTAssertNil(RowLayout.typedNumber("abc", row: r))
        XCTAssertNil(RowLayout.typedNumber("inf", row: r))
        let toggle = try JSONDecoder().decode(SettingRow.self, from: Data(
            #"{"id":"t","section":"game","title":"T","type":"switch","on":true}"#.utf8))
        XCTAssertNil(RowLayout.typedNumber("1", row: toggle), "only a number row takes a number")
    }
}
