import XCTest
@testable import PaneKit

final class DashboardTabsTests: XCTestCase {
    func testParsesServedPage() throws {
        let html = String(decoding: Fixture.data("ui.html"), as: UTF8.self)
        let tabs = DashboardTabs.parse(html: html)
        XCTAssertEqual(tabs.prefix(2).map(\.id), ["control", "metrics"])
        let ids = tabs.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(tabs.first { $0.id == "metrics" }?.label, "Metrics")
        XCTAssertEqual(tabs.first { $0.id == "oledcare" }?.label, "OLED Care")
        // MQTT's button has no data-t span: it must neither borrow the next button's label nor swallow it.
        XCTAssertEqual(tabs.first { $0.id == "mqtt" }?.label, "MQTT")
        XCTAssertEqual(tabs.first { $0.id == "server" }?.label, "Server")
        XCTAssertEqual(Set(ids), Set(DashboardTabs.fallback.map(\.id)))
    }

    func testGarbageGivesEmpty() {
        XCTAssertEqual(DashboardTabs.parse(html: "<html></html>"), [])
    }

    func testDuplicateIdsKeepFirst() {
        let html = #"<button role="tab" data-tab="a"><span data-t="tab.a">One</span></button><button role="tab" data-tab="a"><span data-t="tab.a">Two</span></button>"#
        XCTAssertEqual(DashboardTabs.parse(html: html), [DashboardTab(id: "a", label: "One")])
    }

    func testFallbackOrderAndLanguages() {
        XCTAssertEqual(DashboardTabs.fallback(bundle: lproj("en")).map(\.id),
                       ["control", "metrics", "apps", "home", "oledcare", "game", "picture", "audio", "servicemenu",
                        "screensaver", "privacy", "advanced", "mqtt", "server", "tools"])
        XCTAssertEqual(DashboardTabs.fallback(bundle: lproj("en")).map(\.label).prefix(2), ["Control", "Metrics"])
        XCTAssertEqual(DashboardTabs.fallback(bundle: lproj("fr")).map(\.label),
                       ["Contrôle", "Métriques", "Apps", "Maison", "Soin OLED", "Jeu", "Image", "Audio", "Menu service",
                        "Économiseur d’écran", "Confidentialité", "Avancé", "MQTT", "Serveur", "Outils"])
    }
}
