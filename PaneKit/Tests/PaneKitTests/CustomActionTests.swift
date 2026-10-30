import XCTest
@testable import PaneKit

final class CustomActionTests: XCTestCase {
    private func stats(muted: Bool? = nil) throws -> Stats {
        var s = try JSONDecoder().decode(Stats.self, from: Fixture.data("stats"))
        if let muted { s.muted = muted }
        return s
    }

    private func json(_ step: ActionStep) throws -> [String: Any] {
        let data = try JSONEncoder().encode(step)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testStepJSONShape() throws {
        let steps: [(ActionStep, [String: Any])] = [
            (.button(.rcu(.up)), ["kind": "button", "button": "rcu.up"]),
            (.launchApp(id: "x", title: "X"), ["kind": "app", "id": "x", "title": "X"]),
            (.pictureMode(value: "hdrGame", label: "Game"), ["kind": "pictureMode", "value": "hdrGame", "label": "Game"]),
            (.setting(id: "a", section: "game", title: "T", value: .bool(true), valueLabel: "ON"),
             ["kind": "setting", "id": "a", "section": "game", "title": "T", "value": true, "valueLabel": "ON"]),
            (.screenOff, ["kind": "screenOff"]),
            (.screenOn, ["kind": "screenOn"]),
            (.sleepTimer("30"), ["kind": "sleepTimer", "value": "30"]),
        ]
        for (step, expected) in steps {
            let object = try json(step)
            XCTAssertEqual(NSDictionary(dictionary: object), NSDictionary(dictionary: expected), "\(step)")
            let back = try JSONDecoder().decode(ActionStep.self, from: JSONEncoder().encode(step))
            XCTAssertEqual(back, step)
        }
        let text = String(decoding: try JSONEncoder().encode(steps[3].0), as: UTF8.self)
        XCTAssertTrue(text.contains(#""value":true"#), text)
    }

    func testSettingValueDecodesBoolBeforeNumber() throws {
        func decode(_ s: String) throws -> SettingValue { try JSONDecoder().decode(SettingValue.self, from: Data(s.utf8)) }
        XCTAssertEqual(try decode("true"), .bool(true))
        XCTAssertEqual(try decode("1"), .number(1))
        XCTAssertEqual(try decode(#""1""#), .string("1"))
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(SettingValue.number(12)), as: UTF8.self), "12")
    }

    func testCommands() throws {
        XCTAssertEqual(ActionStep.button(.rcu(.ok)).command(stats: nil), .rcu(.ok))
        XCTAssertEqual(ActionStep.button(.mute).command(stats: try stats(muted: true)), .mute(false))
        XCTAssertEqual(ActionStep.button(.mute).command(stats: try stats(muted: false)), .mute(true))
        XCTAssertEqual(ActionStep.button(.volumeUp).command(stats: nil), .volumeStep(1))
        XCTAssertEqual(ActionStep.button(.volumeDown).command(stats: nil), .volumeStep(-1))
        XCTAssertEqual(ActionStep.button(.media(.playPause)).command(stats: nil), .media(.playPause))
        XCTAssertEqual(ActionStep.button(.source("hdmi4")).command(stats: nil), .input("hdmi4"))
        XCTAssertEqual(ActionStep.setting(id: "eyeComfortMode", section: "picture", title: "E", value: .bool(true), valueLabel: "ON")
            .command(stats: nil), .lgSetting(id: "eyeComfortMode", .bool(true)))
        XCTAssertEqual(ActionStep.launchApp(id: "a", title: "A").command(stats: nil), .launchApp("a"))
        XCTAssertEqual(ActionStep.pictureMode(value: "v", label: "V").command(stats: nil), .pictureMode("v"))
        XCTAssertEqual(ActionStep.screenOff.command(stats: nil), .screenOff)
        XCTAssertEqual(ActionStep.screenOn.command(stats: nil), .screenOn)
        XCTAssertEqual(ActionStep.sleepTimer("off").command(stats: nil), .sleepTimer("off"))
        XCTAssertNil(ActionStep.button(.action(UUID())).command(stats: nil))
        XCTAssertNil(ActionStep.button(ButtonID(rawValue: "future.thing")).command(stats: nil))
    }

    func testDefaultTitles() throws {
        let sources = sources(from: try stats())
        let steps: [ActionStep] = [.button(.source("hdmi4")),
            .setting(id: "gameOptimization", section: "game", title: "Game Optimizer", value: .bool(true), valueLabel: "ON")]
        XCTAssertEqual(CustomAction.defaultTitle(steps, sources: sources), "PS5 Console de jeu + Game Optimizer · ON")
        XCTAssertEqual(ActionStep.sleepTimer("30").defaultTitle(sources: sources, bundle: lproj("en")), "Sleep 30 min")
        XCTAssertEqual(ActionStep.sleepTimer("30").defaultTitle(sources: sources, bundle: lproj("fr")), "Veille 30 min")
        XCTAssertEqual(ActionStep.sleepTimer("off").defaultTitle(sources: sources, bundle: lproj("en")), "Sleep off")
        XCTAssertEqual(ActionStep.sleepTimer("off").defaultTitle(sources: sources, bundle: lproj("fr")), "Veille désactivée")
        XCTAssertEqual(ActionStep.screenOff.defaultTitle(sources: sources, bundle: lproj("fr")), "Écran éteint")
        XCTAssertEqual(ActionStep.screenOn.defaultTitle(sources: sources, bundle: lproj("fr")), "Écran allumé")
        XCTAssertEqual(ActionStep.screenOn.defaultTitle(sources: sources, bundle: lproj("en")), "Screen on")
        XCTAssertEqual(ActionStep.launchApp(id: "a", title: "Apple TV").defaultTitle(sources: sources), "Apple TV")
        XCTAssertEqual(ActionStep.pictureMode(value: "v", label: "Game").defaultTitle(sources: sources), "Game")
    }

    func testButtonTitle() throws {
        let sources = sources(from: try stats())
        let a = CustomAction(title: "Mine", steps: [])
        XCTAssertEqual(ButtonID.rcu(.ok).title(sources: sources, actions: []), "OK")
        XCTAssertEqual(ButtonID.source("hdmi4").title(sources: sources, actions: []), "PS5 Console de jeu")
        XCTAssertEqual(ButtonID.source("hdmi9").title(sources: sources, actions: []), "hdmi9")
        XCTAssertEqual(ButtonID.action(a.id).title(sources: sources, actions: [a]), "Mine")
        XCTAssertEqual(ButtonID(rawValue: "weird").title(sources: sources, actions: [a]), "weird")
    }

    func testCustomActionRoundTrip() throws {
        let a = CustomAction(title: "T", steps: [.screenOn, .sleepTimer("10")])
        let back = try JSONDecoder().decode(CustomAction.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back, a)
    }

    func testTileDefaultsToTheIconForAnActionThatOnlyLaunchesAnApp() {
        let app = ActionStep.launchApp(id: "com.example.app", title: "App")
        XCTAssertEqual(CustomAction(title: "A", steps: [app]).shownTile, .icon)
        XCTAssertEqual(CustomAction(title: "A", steps: [app, .screenOff]).shownTile, .text)
        XCTAssertEqual(CustomAction(title: "A", steps: [.screenOff]).shownTile, .text)
    }

    func testChosenTileWinsWhenAnAppGivesTheIcon() {
        let app = ActionStep.launchApp(id: "com.example.app", title: "App")
        XCTAssertEqual(CustomAction(title: "A", steps: [app], tile: .text).shownTile, .text)
        XCTAssertEqual(CustomAction(title: "A", steps: [.screenOff, app], tile: .icon).shownTile, .icon)
        // No app, no icon: the text, whatever was chosen.
        XCTAssertEqual(CustomAction(title: "A", steps: [.screenOff], tile: .icon).shownTile, .text)
    }

    func testIconAppIsTheFirstAppLaunched() {
        let steps: [ActionStep] = [.screenOn, .launchApp(id: "first", title: "1"), .launchApp(id: "second", title: "2")]
        XCTAssertEqual(CustomAction(title: "A", steps: steps).iconAppID, "first")
        XCTAssertNil(CustomAction(title: "A", steps: [.screenOn]).iconAppID)
    }

    func testTileRoundTripsAndIsLeftOutWhenUnset() throws {
        let a = CustomAction(title: "T", steps: [.screenOn], tile: .icon)
        XCTAssertEqual(try JSONDecoder().decode(CustomAction.self, from: JSONEncoder().encode(a)), a)
        let text = String(decoding: try JSONEncoder().encode(CustomAction(title: "T", steps: [.screenOn])), as: UTF8.self)
        XCTAssertFalse(text.contains("tile"), text)
        // Actions saved before the choice existed.
        let old = #"{"id":"8C2F0B6E-4A57-4E0B-9C1D-2B7F6A1E3D40","title":"T","steps":[{"kind":"screenOn"}]}"#
        XCTAssertNil(try JSONDecoder().decode(CustomAction.self, from: Data(old.utf8)).tile)
    }

    private func row(_ json: String) throws -> SettingRow { try JSONDecoder().decode(SettingRow.self, from: Data(json.utf8)) }

    func testSettingStepAtRowsCurrentValue() throws {
        let toggle = try row(#"{"id":"t","section":"game","title":"Game Optimizer","type":"switch","on":true}"#)
        XCTAssertEqual(ActionStep(currentValueOf: toggle),
                       .setting(id: "t", section: "game", title: "Game Optimizer", value: .bool(true), valueLabel: "ON"))
        let choice = try row(#"{"id":"c","section":"picture","title":"Gamma","type":"choice","value":"high2","choices":[{"value":"low","label":"Low"},{"value":"high2","label":"High 2"}]}"#)
        XCTAssertEqual(ActionStep(currentValueOf: choice),
                       .setting(id: "c", section: "picture", title: "Gamma", value: .string("high2"), valueLabel: "High 2"))
        let number = try row(#"{"id":"n","section":"picture","title":"Contrast","type":"number","value":85,"min":0,"max":100}"#)
        XCTAssertEqual(ActionStep(currentValueOf: number),
                       .setting(id: "n", section: "picture", title: "Contrast", value: .number(85), valueLabel: "85"))
        XCTAssertNil(ActionStep(currentValueOf: try row(#"{"id":"u","section":"s","title":"U","type":"weird"}"#)))
    }

    func testSettingStepAtChosenValueIsLabelledLikeTheRow() throws {
        let choice = try row(#"{"id":"c","section":"picture","title":"Gamma","type":"choice","value":"high2","choices":[{"value":"low","label":"Low"},{"value":"high2","label":"High 2"}]}"#)
        XCTAssertEqual(ActionStep(row: choice, value: .string("low")),
                       .setting(id: "c", section: "picture", title: "Gamma", value: .string("low"), valueLabel: "Low"))
        let signed = try row(#"{"id":"s","section":"picture","title":"Sharpness","type":"number","value":0,"min":-10,"max":10}"#)
        XCTAssertEqual(ActionStep(row: signed, value: .number(-3)),
                       .setting(id: "s", section: "picture", title: "Sharpness", value: .number(-3), valueLabel: "\u{2212}3"))
        let toggle = try row(#"{"id":"t","section":"game","title":"G","type":"switch","on":true}"#)
        XCTAssertEqual(ActionStep(row: toggle, value: .bool(false)),
                       .setting(id: "t", section: "game", title: "G", value: .bool(false), valueLabel: "OFF"))
    }

    func testSameEffectIgnoresTitlesAndLabels() {
        XCTAssertTrue(ActionStep.launchApp(id: "a", title: "A").hasSameEffect(as: .launchApp(id: "a", title: "Other")))
        XCTAssertFalse(ActionStep.launchApp(id: "a", title: "A").hasSameEffect(as: .launchApp(id: "b", title: "A")))
        XCTAssertTrue(ActionStep.pictureMode(value: "cinema", label: "Cinema").hasSameEffect(as: .pictureMode(value: "cinema", label: "Ciné")))
        XCTAssertFalse(ActionStep.pictureMode(value: "cinema", label: "Cinema").hasSameEffect(as: .pictureMode(value: "vivid", label: "Cinema")))
        let on = ActionStep.setting(id: "g", section: "game", title: "G", value: .bool(true), valueLabel: "ON")
        XCTAssertTrue(on.hasSameEffect(as: .setting(id: "g", section: "game", title: "Renamed", value: .bool(true), valueLabel: "Oui")))
        XCTAssertFalse(on.hasSameEffect(as: .setting(id: "g", section: "game", title: "G", value: .bool(false), valueLabel: "ON")))
        XCTAssertFalse(on.hasSameEffect(as: .setting(id: "h", section: "game", title: "G", value: .bool(true), valueLabel: "ON")))
        XCTAssertTrue(ActionStep.button(.rcu(.home)).hasSameEffect(as: .button(.rcu(.home))))
        XCTAssertFalse(ActionStep.button(.rcu(.home)).hasSameEffect(as: .button(.source("hdmi1"))))
        XCTAssertTrue(ActionStep.sleepTimer("30").hasSameEffect(as: .sleepTimer("30")))
        XCTAssertFalse(ActionStep.sleepTimer("30").hasSameEffect(as: .sleepTimer("60")))
        XCTAssertTrue(ActionStep.screenOff.hasSameEffect(as: .screenOff))
        XCTAssertFalse(ActionStep.screenOff.hasSameEffect(as: .screenOn))
        XCTAssertFalse(ActionStep.pictureMode(value: "x", label: "X").hasSameEffect(as: .launchApp(id: "x", title: "X")))
    }
}
