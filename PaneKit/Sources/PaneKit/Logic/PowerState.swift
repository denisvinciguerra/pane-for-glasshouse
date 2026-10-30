public enum PowerState: Equatable, Sendable { case on, screenOff, standby, maintenance, unreachable }

public extension PowerState {
    /// Same precedence as the web dashboard (readouts.js): maintenance, standby, screen off, on.
    /// `.unreachable` is strictly for `nil` stats; a reply matching no rule (older TV) counts as on.
    static func from(_ stats: Stats?) -> PowerState {
        guard let stats else { return .unreachable }
        let power = stats.powerState
        if stats.oled?.compStatus == "Running" { return .maintenance }
        if power?.systemOn == false || power?.raw == "Standby" || power?.raw == "Active Standby" { return .standby }
        if power?.screenOn == false { return .screenOff }
        if power?.systemOn == true || power?.label == "On" { return .on }
        return .on
    }
}
