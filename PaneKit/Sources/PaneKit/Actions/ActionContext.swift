import Foundation

/// What the TV offers, from the latest reads. `nil` (not read yet) means unknown, never unavailable.
public struct ActionContext: Sendable {
    private let stats: Stats?
    private let rows: [SettingRow]

    /// `rows`: every row loaded so far (picture, game, audio, hdmi).
    public init(stats: Stats?, rows: [SettingRow]) {
        self.stats = stats; self.rows = rows
    }

    public var sources: [Source] { stats.map(PaneKit.sources(from:)) ?? [] }

    public var apps: [Stats.App] {
        (stats?.apps ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The choices of the "pictureMode" row; `nil` while it is not loaded.
    public var pictureModes: [Choice]? {
        guard let row = rows.first(where: { $0.id == "pictureMode" }), case .choice(_, let choices) = row.kind else { return nil }
        return choices
    }

    /// The switch, choice and number rows of a section.
    public func rows(section: String) -> [SettingRow] {
        rows.filter {
            guard $0.section == section else { return false }
            if case .unsupported = $0.kind { return false }
            return true
        }
    }

    /// Why the step cannot run; `nil` if it can, or if that is not known yet.
    public func unavailableReason(_ step: ActionStep) -> String? { unavailableReason(step, bundle: .module) }

    func unavailableReason(_ step: ActionStep, bundle: Bundle) -> String? {
        switch step {
        case .button(let id):
            if step.command(stats: nil) == nil { return String(localized: "Unknown button", bundle: bundle) }
            guard let source = id.sourceID, let stats, stats.inputs != nil else { return nil }
            return PaneKit.sources(from: stats).contains { $0.id == source }
                ? nil : String(localized: "Input not found on this TV", bundle: bundle)
        case .launchApp(let id, _):
            guard let apps = stats?.apps else { return nil }
            return apps.contains { $0.id == id } ? nil : String(localized: "App not installed on this TV", bundle: bundle)
        case .pictureMode(let value, _):
            guard let modes = pictureModes else { return nil }
            return modes.contains { $0.value == value } ? nil : String(localized: "Picture mode not available for this signal", bundle: bundle)
        case .setting(let id, let section, _, _, _):
            guard rows.contains(where: { $0.section == section }) else { return nil }
            guard let row = rows.first(where: { $0.id == id && $0.section == section }) else {
                return String(localized: "Setting not found on this TV", bundle: bundle)
            }
            guard !row.active else { return nil }
            return RowLayout.inactiveReason(row, bundle: bundle) ?? String(localized: "Setting unavailable right now", bundle: bundle)
        case .screenOff, .screenOn, .sleepTimer:
            return nil
        }
    }

    /// The reason of the first blocked step; "This action has no steps" when it has none.
    public func unavailableReason(_ action: CustomAction) -> String? { unavailableReason(action, bundle: .module) }

    func unavailableReason(_ action: CustomAction, bundle: Bundle) -> String? {
        if action.steps.isEmpty { return String(localized: "This action has no steps", bundle: bundle) }
        return action.steps.lazy.compactMap { unavailableReason($0, bundle: bundle) }.first
    }
}
