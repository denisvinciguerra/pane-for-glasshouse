import Foundation

/// PaneKit's own bundle, for the tests to reach its localizations.
enum PaneKitResources {
    static let bundle = Bundle.module
}

public struct RowGroup: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String?
    public let rows: [SettingRow]
}

/// Orders and words the setting rows like the web dashboard (picture.js, lgsettings.js).
public enum RowLayout {
    private static let minus = "\u{2212}"

    /// The Picture tab: the mode lifted out, then LG's groups in LG's order, then white balance,
    /// then the groups this app does not know. Colour-management rows are dropped.
    public static func picture(_ rows: [SettingRow]) -> (mode: SettingRow?, groups: [RowGroup]) {
        picture(rows, bundle: .module)
    }

    static func picture(_ rows: [SettingRow], bundle: Bundle) -> (mode: SettingRow?, groups: [RowGroup]) {
        let mode = rows.first { $0.id == "pictureMode" }
        var order: [String] = []
        var byGroup: [String: [SettingRow]] = [:]
        for row in rows where row.id != "pictureMode" && row.cms == nil {
            // The colour-management switch carries group "cms" but no `cms`: it belongs to Colour.
            let group = row.group == "cms" ? "colour" : (row.group ?? "other")
            if byGroup[group] == nil { order.append(group) }
            byGroup[group, default: []].append(row)
        }
        let known = ["mode", "brightness", "colour", "clarity", "motion", "aspect", "whiteBalance"]
        let sequence = known + order.filter { !known.contains($0) }
        let groups = sequence.compactMap { id -> RowGroup? in
            guard let list = byGroup[id] else { return nil }
            return RowGroup(id: id, title: groupTitle(id, bundle: bundle), rows: list)
        }
        return (mode, groups)
    }

    /// Audio ("sound") and Game ("game"): one untitled group, server order.
    public static func plain(_ rows: [SettingRow], section: String) -> [RowGroup] {
        let list = rows.filter { $0.section == section }
        return list.isEmpty ? [] : [RowGroup(id: section, title: nil, rows: list)]
    }

    /// A number typed for a number row: rounded to a whole step and kept within the row's range.
    /// The minus sign the app shows and a decimal comma are read too; `nil` when the text is not a
    /// number, or the row takes none.
    public static func typedNumber(_ text: String, row: SettingRow) -> Double? {
        guard case .number(_, let min, let max) = row.kind else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: minus, with: "-")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return Swift.min(Swift.max(value.rounded(), min), max)
    }

    /// The value as the web words it; a dash when it is not a number this app can show.
    public static func valueText(_ row: SettingRow, value: Double) -> String {
        guard value.isFinite, abs(value) <= SettingRow.numberLimit else { return "\u{2014}" }
        let n = Int(abs(value).rounded())
        guard case .number(_, let min, _) = row.kind else { return String(Int(value.rounded())) }
        if value == 0 { return "0" }
        switch row.track {
        case "tint": return value < 0 ? "R\(n)" : "G\(n)"
        case "temperature": return value < 0 ? "W\(n)" : "C\(n)"
        case "red", "green", "blue": return value < 0 ? "\(minus)\(n)" : "+\(n)"
        default: break
        }
        if min < 0 { return value < 0 ? "\(minus)\(n)" : "+\(n)" }
        return String(Int(value.rounded()))
    }

    public static func inactiveReason(_ row: SettingRow) -> String? {
        inactiveReason(row, bundle: .module)
    }

    static func inactiveReason(_ row: SettingRow, bundle: Bundle) -> String? {
        guard !row.active else { return nil }
        switch row.inactive {
        case "game": return String(localized: "Not used in Game mode.", bundle: bundle)
        case "colourAdjustment":
            return String(localized: "Set Colour adjustment to User Selection to use these.", bundle: bundle)
        default:
            return String(localized: "Not available with the TV’s current input or sound output.", bundle: bundle)
        }
    }

    private static func groupTitle(_ id: String, bundle: Bundle) -> String? {
        switch id {
        case "mode": return nil
        case "brightness": return String(localized: "Brightness", bundle: bundle)
        case "colour": return String(localized: "Colour", bundle: bundle)
        case "clarity": return String(localized: "Clarity", bundle: bundle)
        case "motion": return String(localized: "Motion", bundle: bundle)
        case "aspect": return String(localized: "Aspect ratio", bundle: bundle)
        case "whiteBalance": return String(localized: "White balance", bundle: bundle)
        case "other": return String(localized: "Other", bundle: bundle)
        default: return fallbackTitle(id)
        }
    }

    /// "toneCurve" -> "Tone curve".
    static func fallbackTitle(_ id: String) -> String {
        var words: [String] = []
        var current = ""
        for ch in id {
            if ch.isUppercase, !current.isEmpty { words.append(current); current = "" }
            current.append(ch)
        }
        if !current.isEmpty { words.append(current) }
        let text = words.joined(separator: " ").lowercased()
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
