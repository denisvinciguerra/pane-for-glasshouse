import PaneKit
import SwiftUI

/// The dashboard's masthead: the TV's name and model on the left; on the right its state, what is
/// on screen, and the signal with its range badge. Off the "on" state, what is on screen is the
/// last thing seen, so it is dimmed. On iOS (mockups/2026-11-02-ios/iphone-compact.html, B1): the
/// make and model over what is on screen, large, and the signal; on the right the state over Power,
/// which the Mac has in its footer. The chips above name the TV and choose it.
struct HeaderView: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.palette) private var palette

    #if os(macOS)
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
    #else
    var body: some View {
        let header = Header(stats: session.stats)
        // Back from the background, the last state is old until the first read lands.
        let waiting = session.connecting || session.stale
        let live = session.power == .on && !waiting
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                // The make alone while the model is unknown, as the Mac shows "—" for it.
                Text(verbatim: header.model.isEmpty ? "LG" : "LG · \(header.model)")
                    .sectionLabelStyle()
                    .frame(height: 16)
                Text(verbatim: header.nowShowing ?? "—")
                    .font(.manrope(points: 22, .light))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(live ? palette.fg : palette.fg.opacity(0.40))
                    .frame(height: 28)
                meta(header)
                    .font(.manrope(points: 12.5))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                    .frame(height: 18)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    if live { OnDot(size: 7) }
                    Text(waiting ? String(localized: "Connecting")
                         : session.localNetworkDenied ? String(localized: "Blocked") : session.power.title)
                        .font(.manrope(points: 11.5))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .foregroundStyle(live ? palette.fg : palette.label)
                }
                .frame(height: 16)
                PowerButton(model: model, session: session)
            }
        }
        .frame(height: 64, alignment: .bottom)
    }

    /// Why the commands are off (not while the local network block explains it), else the signal
    /// and its range badge.
    @ViewBuilder private func meta(_ header: Header) -> some View {
        if !session.localNetworkDenied, let reason = session.blockedReason {
            Text(verbatim: reason).truncationMode(.tail)
        } else {
            HStack(spacing: 6) {
                if let signal = header.signal { Text(verbatim: signal) }
                if let badge = header.rangeBadge { ValueBadge(text: badge).foregroundStyle(palette.fg) }
            }
        }
    }
    #endif
}

#if os(iOS)
/// Power under the state: a 44 pt key. It does nothing while the keys show, as on the Mac.
private struct PowerButton: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.keyboard) private var keyboard

    var body: some View {
        GHButton(nil, systemImage: "power", height: Metrics.minTouch) {
            model.noteCommandSent()
            Task { await session.togglePower() }
        }
        .frame(width: Metrics.minTouch)
        .disabled(!session.canPower || keyboard?.state.sendsCommands == false)
        .accessibilityLabel(Text("Power"))
        .accessibilityIdentifier("remote.power")
    }
}
#endif

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
