import PaneKit
import SwiftUI

/// The dashboard's masthead: the TV's name and model on the left; on the right its state, what is
/// on screen, and the signal with its range badge. Off the "on" state, what is on screen is the
/// last thing seen, so it is dimmed.
struct HeaderView: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.palette) private var palette

    var body: some View {
        let header = Header(stats: session.stats)
        let live = session.power == .on && !session.connecting
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                TVMenu(model: model)
                Text(verbatim: header.model.isEmpty ? "—" : header.model)
                    .font(.manrope(19, .light))
                    .tracking(0.38)
                    .lineLimit(1)
                    .foregroundStyle(header.model.isEmpty ? palette.label : palette.fg)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 5) {
                    if live { OnDot(size: 6) }
                    Text(session.connecting ? String(localized: "Connecting")
                         : session.localNetworkDenied ? String(localized: "Blocked") : session.power.title)
                        .font(.manrope(Metrics.labelSize))
                        .tracking(Metrics.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(live ? palette.fg : palette.label)
                }
                .frame(height: 17)
                Group {
                    if let nowShowing = header.nowShowing {
                        Text(verbatim: nowShowing).frame(height: 17)
                    }
                    if header.signal != nil || header.rangeBadge != nil {
                        HStack(spacing: 3) {
                            if let signal = header.signal { Text(verbatim: signal) }
                            if let badge = header.rangeBadge { ValueBadge(text: badge) }
                        }
                        .frame(height: 17)
                    }
                }
                .font(.manrope(11))
                .lineLimit(1)
                .foregroundStyle(live ? palette.fg : palette.fg.opacity(0.40))
            }
        }
    }
}

extension PowerState {
    /// The state word of the header.
    var title: String {
        switch self {
        case .on: String(localized: "On")
        case .screenOff: String(localized: "Screen off")
        case .standby: String(localized: "Standby")
        case .maintenance: String(localized: "Maintenance")
        case .unreachable: String(localized: "Unreachable")
        }
    }
}
