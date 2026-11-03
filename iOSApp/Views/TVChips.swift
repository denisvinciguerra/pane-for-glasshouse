import PaneKit
import SwiftUI

/// One chip per saved TV, in the order of the TV list, the active one ringed: its name, a dot for
/// its state, and what it shows when it is on (« Bedroom · PS5 »). A touch makes it the active TV.
/// The active TV's chip follows the session, the others the glance. During the demo, its chip comes
/// first. Hidden with a single TV.
struct TVChips: View {
    let model: MobileModel

    /// Whether there are chips to show: two at least.
    static func shown(for model: MobileModel) -> Bool {
        model.app.store.tvs.count + (model.app.isDemo ? 1 : 0) > 1
    }

    var body: some View {
        let chips = self.chips
        if chips.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        Button { model.app.activate(chip.id) } label: { ChipLabel(chip: chip) }
                            .buttonStyle(ChipStyle(current: chip.current))
                            .disabled(chip.current)
                            .accessibilityAddTraits(chip.current ? .isSelected : [])
                    }
                }
                .padding(.leading, Metrics.gutter)
            }
            .scrollIndicators(.hidden)
            // The chips reach the screen's left edge while they scroll.
            .padding(.leading, -Metrics.gutter)
        }
    }

    private var chips: [TVChip] {
        let app = model.app
        var chips: [TVChip] = []
        if let demo = app.demo, let session = app.session {
            chips.append(TVChip(id: demo.id, name: demo.name, current: true, state: .live(session)))
        }
        for tv in app.store.tvs {
            if tv.id == app.activeID, let session = app.session {
                chips.append(TVChip(id: tv.id, name: tv.name, current: true, state: .live(session)))
            } else {
                chips.append(TVChip(id: tv.id, name: tv.name, current: false, state: .glance(model.glance.states[tv.id])))
            }
        }
        return chips
    }
}

/// What a chip shows.
@MainActor private struct TVChip: Identifiable {
    let id: UUID
    let name: String
    let current: Bool
    let state: Reading

    enum Reading {
        case live(TVSession)
        case glance(TVGlanceState?)
    }

    enum Dot { case on, off, unknown, none }

    /// Green: on; grey: standby or the screen off; "?": not reached, refused, or a wrong token, never
    /// shown as off; nothing before the first answer.
    var dot: Dot {
        switch state {
        case .live(let session):
            // Back from the background: nothing until the first read on return.
            if session.stale { return .none }
            if session.localNetworkDenied || session.lastError == .badToken { return .unknown }
            if session.connecting { return .none }
            return Self.dot(session.power)
        case .glance(let glance):
            guard let glance else { return .none }
            switch glance.reach {
            case .unknown: return .none
            case .unreachable, .localNetworkDenied, .badToken: return .unknown
            case .reached: return glance.state.map(Self.dot) ?? .none
            }
        }
    }

    private static func dot(_ power: PowerState) -> Dot {
        switch power {
        case .on: .on
        case .screenOff, .standby, .maintenance: .off
        case .unreachable: .unknown
        }
    }

    /// What the TV shows, only while it is on.
    var nowShowing: String? {
        guard dot == .on else { return nil }
        switch state {
        case .live(let session): return Header(stats: session.stats).nowShowing
        case .glance(let glance): return glance?.nowShowing
        }
    }
}

private struct ChipLabel: View {
    let chip: TVChip
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            switch chip.dot {
            case .on: OnDot(size: 7)
            case .off: Circle().fill(palette.fg.opacity(0.35)).frame(width: 7, height: 7)
            case .unknown:
                Text(verbatim: "?")
                    .font(.manrope(points: 12, .semibold))
                    .foregroundStyle(palette.label)
                    .accessibilityLabel(Text("State unknown"))
            case .none: EmptyView()
            }
            Text(verbatim: chip.nowShowing.map { "\(chip.name) · \($0)" } ?? chip.name)
                .lineLimit(1)
        }
        .font(.manrope(points: 14, .medium))
        .padding(.horizontal, 14)
        .frame(height: 34)
    }
}

/// A rounded chip on a key's face: a divider-coloured edge, the foreground's for the current TV;
/// the whole row's height takes the touch.
private struct ChipStyle: ButtonStyle {
    let current: Bool
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.fg)
            .background(Capsule().fill(palette.fg.opacity(configuration.isPressed ? 0.12 : 0)))
            .background(Capsule().fill(palette.key))
            .overlay(Capsule().strokeBorder(current ? palette.fg : palette.divider,
                                            lineWidth: current ? palette.activeLineWidth : 1))
            .frame(height: Metrics.minTouch)
            .contentShape(Rectangle())
    }
}
