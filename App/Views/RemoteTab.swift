import PaneKit
import SwiftUI

/// The remote: sources, d-pad, playback, volume, pinned actions. Every button goes through the
/// keyboard controller and can carry a key; all but the pins' "+" are off when the TV can't be
/// controlled, unless keys are being set.
struct RemoteTab: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.keyboard) private var keyboard

    private static let gap: CGFloat = 6

    var body: some View {
        let stats = session.stats
        let controlsOff = keyboard?.state.sendsCommands != false && !session.canControl
        VStack(alignment: .leading, spacing: 14) {
            Group {
                section("Source") { sourceGrid(stats.map(sources(from:)) ?? []) }
                section("D-pad") { dpad }
                section("Playback") { playback }
                section("Volume", trailing: stats?.sound?.output ?? stats?.audioOutput) { volume(stats) }
            }
            .disabled(controlsOff)
            PinnedSection(model: model, session: session, controlsOff: controlsOff)
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, trailing: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title, trailing: trailing)
            content()
        }
    }

    private func click(_ id: ButtonID) {
        keyboard?.buttonClicked(id)
    }

    // MARK: Source

    private func sourceGrid(_ list: [Source]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: max(1, min(5, list.count)))
        return LazyVGrid(columns: columns, spacing: Self.gap) {
            ForEach(list) { source in
                GHButton(selected: source.isActive, action: { click(.source(source.id)) }) {
                    Text(verbatim: source.label)
                        .font(.manrope(10))
                        .textCase(.uppercase)
                        .tracking(1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .help(Text(verbatim: source.label))
                .keyed(.source(source.id))
            }
        }
    }

    // MARK: D-pad

    private var dpad: some View {
        VStack(spacing: Self.gap) {
            HStack(spacing: Self.gap) { gap; arrow(.up, "Up"); gap }
            HStack(spacing: Self.gap) {
                arrow(.left, "Left")
                GHButton("OK", height: 50) { click(.rcu(.ok)) }.frame(width: 58).keyed(.rcu(.ok))
                arrow(.right, "Right")
            }
            HStack(spacing: Self.gap) { gap; arrow(.down, "Down"); gap }
            HStack(spacing: Self.gap) {
                GHButton("Back") { click(.rcu(.back)) }.keyed(.rcu(.back))
                GHButton("Home") { click(.rcu(.home)) }.keyed(.rcu(.home))
                GHButton("Settings") { click(.rcu(.settings)) }.keyed(.rcu(.settings))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var gap: some View { Color.clear.frame(width: 58, height: 50) }

    private func arrow(_ key: RemoteKey, _ name: LocalizedStringKey) -> some View {
        GHButton(height: 50, action: { click(.rcu(key)) }) {
            // The button's colour: amber while it awaits its key.
            Triangle(pointing: key).fill(.foreground).frame(width: 12, height: 12)
        }
        .frame(width: 58)
        .accessibilityLabel(Text(name))
        .keyed(.rcu(key))
    }

    // MARK: Playback

    private var playback: some View {
        HStack(spacing: Self.gap) {
            media(.rewind, "backward.fill", "Rewind")
            media(.playPause, "playpause.fill", "Play/Pause")
            media(.stop, "stop.fill", "Stop")
            media(.fastForward, "forward.fill", "Fast forward")
        }
    }

    private func media(_ key: MediaKey, _ systemImage: String, _ name: LocalizedStringKey) -> some View {
        GHButton(nil, systemImage: systemImage) { click(.media(key)) }
            .accessibilityLabel(Text(name))
            .keyed(.media(key))
    }

    // MARK: Volume

    private func volume(_ stats: Stats?) -> some View {
        let muted = stats?.muted ?? false
        return WeightedRow(weights: [1, 1.2, 1, 1.6], spacing: Self.gap) {
            GHButton(action: { click(.volumeDown) }) { Text(verbatim: "−").font(.manrope(16, .light)) }
                .accessibilityLabel(Text("Volume down"))
                .keyed(.volumeDown)
            Text(verbatim: stats?.volume.map(String.init) ?? "–")
                .font(.manrope(15, .light))
                .frame(maxWidth: .infinity)
            GHButton(action: { click(.volumeUp) }) { Text(verbatim: "+").font(.manrope(16, .light)) }
                .accessibilityLabel(Text("Volume up"))
                .keyed(.volumeUp)
            GHButton("Mute", selected: muted) { click(.mute) }.keyed(.mute)
        }
        .frame(height: 34)
    }
}

/// Lays its children in one row, their widths in the ratio of `weights`, the gaps excluded.
private struct WeightedRow: Layout {
    let weights: [CGFloat]
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = proposal.replacingUnspecifiedDimensions()
        return CGSize(width: size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let unit = (bounds.width - spacing * CGFloat(subviews.count - 1)) / weights.reduce(0, +)
        var x = bounds.minX
        for (view, weight) in zip(subviews, weights) {
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: unit * weight, height: bounds.height))
            x += unit * weight + spacing
        }
    }
}

private struct Triangle: Shape {
    let pointing: RemoteKey

    func path(in rect: CGRect) -> Path {
        let (w, h) = (rect.width, rect.height)
        var p = Path()
        switch pointing {
        case .up: p.addLines([CGPoint(x: w / 2, y: 0), CGPoint(x: w, y: h), CGPoint(x: 0, y: h)])
        case .down: p.addLines([CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0), CGPoint(x: w / 2, y: h)])
        case .left: p.addLines([CGPoint(x: 0, y: h / 2), CGPoint(x: w, y: 0), CGPoint(x: w, y: h)])
        case .right: p.addLines([CGPoint(x: w, y: h / 2), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: h)])
        default: break   // only the four arrows draw a triangle
        }
        p.closeSubpath()
        return p
    }
}
