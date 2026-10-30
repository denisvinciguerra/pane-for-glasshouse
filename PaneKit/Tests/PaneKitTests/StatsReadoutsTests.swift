import XCTest
@testable import PaneKit

final class StatsReadoutsTests: XCTestCase {
    private let en = lproj("en"), fr = lproj("fr")
    private let us = Locale(identifier: "en_US"), fra = Locale(identifier: "fr_FR")

    private func stats(_ name: String = "stats") throws -> Stats {
        try JSONDecoder().decode(Stats.self, from: Fixture.data(name))
    }
    private func stats(json: String) throws -> Stats { try JSONDecoder().decode(Stats.self, from: Data(json.utf8)) }

    func testGaugesG4() throws {
        let g = StatsReadouts.gauges(try stats(), bundle: en, locale: us)
        XCTAssertEqual(g.map(\.id), ["cpu", "memory", "swap", "network"])
        XCTAssertEqual(g.map(\.label), ["Processor", "Memory", "Swap", "Network"])
        XCTAssertEqual(g[0].value, "51"); XCTAssertEqual(g[0].unit, "%")
        XCTAssertEqual(g[0].detail, "54%  ·  43%  ·  63%  ·  44%")
        // mem total 1954696 kB, avail 537952 kB: 72.5 % used.
        XCTAssertEqual(g[1].value, "\(Int((100 * (1954696.0 - 537952.0) / 1954696.0).rounded()))")
        XCTAssertEqual(g[1].value, "72")
        XCTAssertEqual(g[1].detail, "1,384 / 1,909 MB")
        XCTAssertEqual(g[2].value, "67"); XCTAssertEqual(g[2].detail, "403 / 600 MB flash")
        XCTAssertEqual(g[3].unit, "kB/s"); XCTAssertEqual(g[3].value, "68")   // 69916 / 1024
        XCTAssertEqual(g[3].detail, "18 kB/s up")
        for r in g { XCTAssertTrue((0...1).contains(try XCTUnwrap(r.fraction))) }
        XCTAssertEqual(try XCTUnwrap(g[0].fraction), 0.51, accuracy: 0.0001)
    }

    func testFractionClampsAndZeroTotalHides() throws {
        let s = try stats(json: #"{"load":140,"mem":{"total":0,"avail":0},"swap":{"total":0,"free":0},"net":{"rx":9999999,"tx":0}}"#)
        let g = StatsReadouts.gauges(s, bundle: en, locale: us)
        XCTAssertEqual(g.map(\.id), ["cpu", "network"])
        XCTAssertEqual(g[0].fraction, 1); XCTAssertEqual(g[1].fraction, 1)
        XCTAssertEqual(g[1].detail, "Connected")
    }

    func testFactsG4() throws {
        let f = StatsReadouts.facts(try stats(), bundle: en, locale: us)
        XCTAssertEqual(f.map(\.id), ["temp", "panelHours", "uptime", "version"])
        XCTAssertEqual(f.map(\.label), ["Temperature", "Panel hours", "Uptime", "Glasshouse version"])
        XCTAssertEqual(f.map(\.value), ["43°C", "1,538 h", "14h 52m", "0.132.0"])   // 53561 s
        let long = try stats(json: #"{"uptime":200000}"#)
        XCTAssertEqual(StatsReadouts.facts(long, bundle: en, locale: us).first?.value, "2d 7h 33m")
    }

    func testFrench() throws {
        let g = StatsReadouts.gauges(try stats(), bundle: fr, locale: fra)
        XCTAssertEqual(g.map(\.label), ["Processeur", "Mémoire", "Swap", "Réseau"])
        XCTAssertEqual(g[3].detail, "18 ko/s émis")
        XCTAssertEqual(g[3].unit, "ko/s")
        let f = StatsReadouts.facts(try stats(), bundle: fr, locale: fra)
        XCTAssertEqual(f.map(\.label), ["Température", "Heures de dalle", "Durée de fonctionnement", "Version de Glasshouse"])
        XCTAssertEqual(f[2].value, "14 h 52 min")
        XCTAssertTrue(f[1].value.hasSuffix(" h")); XCTAssertTrue(f[1].value.hasPrefix("1"))
    }

    func testFrenchUsesMo() throws {
        let g = StatsReadouts.gauges(try stats(), bundle: fr, locale: fra)
        XCTAssertTrue(g[1].detail.hasSuffix(" Mo"), g[1].detail)
        XCTAssertTrue(g[2].detail.contains(" Mo"), g[2].detail)
        XCTAssertFalse(g[1].detail.contains("MB"))
    }

    func testMissingFieldsAreHidden() throws {
        let s = try stats(json: #"{"ok":true}"#)
        XCTAssertEqual(StatsReadouts.gauges(s), [])
        XCTAssertEqual(StatsReadouts.facts(s), [])
    }
}
