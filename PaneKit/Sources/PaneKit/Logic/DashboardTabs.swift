import Foundation

public struct DashboardTab: Equatable, Sendable {
    public let id: String
    public let label: String
}

/// The tabs of the web dashboard, for the "Dashboard ↗" menu.
public enum DashboardTabs {
    public static var fallback: [DashboardTab] { fallback(bundle: .module) }

    static func fallback(bundle: Bundle) -> [DashboardTab] {
        [("control", String(localized: "Control", bundle: bundle)),
         ("metrics", String(localized: "Metrics", bundle: bundle)),
         ("apps", String(localized: "Apps", bundle: bundle)),
         ("home", String(localized: "Home", bundle: bundle)),
         ("oledcare", String(localized: "OLED Care", bundle: bundle)),
         ("game", String(localized: "Game", bundle: bundle)),
         ("picture", String(localized: "Picture", bundle: bundle)),
         ("audio", String(localized: "Audio", bundle: bundle)),
         ("servicemenu", String(localized: "Service menu", bundle: bundle)),
         ("screensaver", String(localized: "Screensaver", bundle: bundle)),
         ("privacy", String(localized: "Privacy", bundle: bundle)),
         ("advanced", String(localized: "Advanced", bundle: bundle)),
         ("mqtt", "MQTT"),
         ("server", String(localized: "Server", bundle: bundle)),
         ("tools", String(localized: "Tools", bundle: bundle))].map { DashboardTab(id: $0.0, label: $0.1) }
    }

    /// Reads the `<button role="tab" data-tab="…">` of the served page, in page order. The label is
    /// the button's first `<span>` (its translatable one when it has one: MQTT's has none).
    public static func parse(html: String) -> [DashboardTab] {
        guard let button = try? NSRegularExpression(
                pattern: #"<button[^>]*role="tab"[^>]*data-tab="([a-z]+)"[^>]*>(.*?)</button>"#,
                options: [.dotMatchesLineSeparators]),
              let translated = try? NSRegularExpression(pattern: #"<span data-t="[^"]*">([^<]+)</span>"#),
              let plain = try? NSRegularExpression(pattern: #"<span[^>]*>([^<]+)</span>"#)
        else { return [] }
        let ns = html as NSString
        var seen = Set<String>()
        var tabs: [DashboardTab] = []
        for m in button.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let id = ns.substring(with: m.range(at: 1))
            let inner = ns.substring(with: m.range(at: 2)) as NSString
            let whole = NSRange(location: 0, length: inner.length)
            guard let hit = translated.firstMatch(in: inner as String, range: whole) ?? plain.firstMatch(in: inner as String, range: whole)
            else { continue }
            let label = inner.substring(with: hit.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty, seen.insert(id).inserted { tabs.append(DashboardTab(id: id, label: label)) }
        }
        return tabs
    }
}
