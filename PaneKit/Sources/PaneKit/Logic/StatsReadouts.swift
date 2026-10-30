import Foundation

public struct Readout: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let detail: String
    public let value: String
    public let unit: String
    public let fraction: Double?
}

public struct KeyValue: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let value: String
}

/// The Metrics tab's System readouts, worded like the web dashboard (readouts.js).
public enum StatsReadouts {
    public static func gauges(_ s: Stats) -> [Readout] { gauges(s, bundle: .module, locale: .current) }
    public static func facts(_ s: Stats) -> [KeyValue] { facts(s, bundle: .module, locale: .current) }

    static func gauges(_ s: Stats, bundle: Bundle, locale: Locale) -> [Readout] {
        var out: [Readout] = []
        let mb = String(localized: "MB", bundle: bundle)
        if let load = s.load {
            let cores = (s.cores ?? []).map { "\($0)%" }.joined(separator: "  ·  ")
            out.append(Readout(id: "cpu", label: String(localized: "Processor", bundle: bundle), detail: cores,
                               value: "\(load)", unit: "%", fraction: clamp(Double(load) / 100)))
        }
        if let total = s.mem?.total, let avail = s.mem?.avail, total > 0 {
            let pct = 100 * (total - avail) / total
            out.append(Readout(id: "memory", label: String(localized: "Memory", bundle: bundle),
                               detail: megabytes(total - avail, locale) + " / " + megabytes(total, locale) + " " + mb,
                               value: "\(Int(pct.rounded()))", unit: "%", fraction: clamp(pct / 100)))
        }
        if let total = s.swap?.total, let free = s.swap?.free, total > 0 {
            let pct = 100 * (total - free) / total
            let backing = (s.swap?.backing).flatMap { $0.isEmpty ? nil : " " + $0 } ?? ""
            out.append(Readout(id: "swap", label: String(localized: "Swap", bundle: bundle),
                               detail: megabytes(total - free, locale) + " / " + megabytes(total, locale) + " " + mb + backing,
                               value: "\(Int(pct.rounded()))", unit: "%", fraction: clamp(pct / 100)))
        }
        if let rx = s.net?.rx {
            let rxK = rx / 1024, txK = (s.net?.tx ?? 0) / 1024
            let detail = txK > 0
                ? String(localized: "\(Int(txK.rounded())) kB/s up", bundle: bundle)
                : String(localized: "Connected", bundle: bundle)
            // The web's bar is full at 2 000 kB/s.
            out.append(Readout(id: "network", label: String(localized: "Network", bundle: bundle), detail: detail,
                               value: "\(Int(rxK.rounded()))", unit: String(localized: "kB/s", bundle: bundle), fraction: clamp(rxK / 2000)))
        }
        return out
    }

    static func facts(_ s: Stats, bundle: Bundle, locale: Locale) -> [KeyValue] {
        var out: [KeyValue] = []
        if let temp = s.temp {
            out.append(KeyValue(id: "temp", label: String(localized: "Temperature", bundle: bundle), value: "\(temp)°C"))
        }
        if let hours = s.oled?.panelHours {
            out.append(KeyValue(id: "panelHours", label: String(localized: "Panel hours", bundle: bundle),
                                value: String(localized: "\(grouped(Double(hours), locale)) h", bundle: bundle)))
        }
        if let up = s.uptime, up >= 0 {
            let days = Int(up) / 86400, hours = Int(up) % 86400 / 3600, mins = Int(up) % 3600 / 60
            let text = days > 0 ? String(localized: "\(days)d \(hours)h \(mins)m", bundle: bundle)
                : hours > 0 ? String(localized: "\(hours)h \(mins)m", bundle: bundle)
                : String(localized: "\(max(mins, 1))m", bundle: bundle)
            out.append(KeyValue(id: "uptime", label: String(localized: "Uptime", bundle: bundle), value: text))
        }
        if let v = s.tvwebVersion, !v.isEmpty {
            out.append(KeyValue(id: "version", label: String(localized: "Glasshouse version", bundle: bundle), value: v))
        }
        return out
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    private static func megabytes(_ kB: Double, _ locale: Locale) -> String { grouped((kB / 1024).rounded(), locale) }

    private static func grouped(_ x: Double, _ locale: Locale) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal; f.maximumFractionDigits = 0; f.locale = locale
        return f.string(from: NSNumber(value: x)) ?? "\(Int(x))"
    }
}
