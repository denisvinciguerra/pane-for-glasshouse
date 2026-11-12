import PaneKit
import SwiftUI

/// The remote: sources, d-pad, playback, volume, pinned actions. Every button goes through the
/// keyboard controller and can carry a key; all but the pins' "+" are off when the TV can't be
/// controlled, unless the keys show: a click then chooses the button and sends nothing. On iOS, the
/// whole remote on one screen (mockups/2026-11-02-ios/iphone-compact.html, B1): the sources on one
/// row, the pins on one row, the cross, the navigation and playback rows, then the volume's.
struct RemoteTab: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.keyboard) private var keyboard
    @State private var pointerMode = false
    @State private var pointerController: PointerController?
    @Environment(\.palette) private var palette
    #if os(iOS)
    /// − and + held down repeat, each on its own.
    @State private var volumeDown = KeyRepeater()
    @State private var volumeUp = KeyRepeater()
    @Environment(\.scenePhase) private var scenePhase
    #endif

    private static let gap: CGFloat = 6

    var body: some View {
        let stats = session.stats
        let controlsOff = keyboard?.state.sendsCommands != false && !session.canControl
        #if os(iOS)
        phone(stats, controlsOff: controlsOff)
        #else
        VStack(alignment: .leading, spacing: 14) {
            Group {
                section("Source") { sourceGrid(stats.map(sources(from:)) ?? []) }
                section(pointerMode ? "Pointer" : "D-pad") {
                    if pointerMode {
                        VStack(spacing: Self.gap) {
                            pointerMacPad
                            navigation
                        }
                    } else { dpad }
                }
                section("Playback") { playback }
                section("Volume", trailing: stats?.sound?.output ?? stats?.audioOutput) { volume(stats) }
            }
            // The pins' edit sends nothing either.
            .disabled(controlsOff || keyboard?.pinsEditing == true)
            PinnedSection(model: model, session: session, controlsOff: controlsOff)
        }
        #endif
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
            navigation
        }
        .frame(maxWidth: .infinity)
    }

    private var navigation: some View {
        HStack(spacing: Self.gap) {
            GHButton("Back") { click(.rcu(.back)) }.keyed(.rcu(.back))
            GHButton("Home") { click(.rcu(.home)) }.keyed(.rcu(.home))
            GHButton("Settings") { click(.rcu(.settings)) }.keyed(.rcu(.settings))
            if session.caps?.pointer == true {
                Group {
                    if pointerMode {
                        GHButton("D-pad") { pointerMode = false }
                    } else {
                        GHButton("Pointer") { pointerMode = true }
                    }
                }
                .transaction { $0.animation = nil }
            }
        }
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

#if os(macOS)
extension RemoteTab {
    private var pointerMacPad: some View {
        ZStack {
            if let pointerController { PointerMacPad(controller: pointerController) }
            Text("Drag to move · Click to select\nUse the wheel or two fingers to scroll")
                .font(.manrope(13))
                .foregroundStyle(palette.label)
                .multilineTextAlignment(.center)
                .allowsHitTesting(false)
        }
        .frame(height: 3 * 50 + 2 * Self.gap)
        .background(palette.key)
        .overlay(Rectangle().strokeBorder(palette.line, lineWidth: 1))
        .onAppear { openPointer() }
        .onDisappear { pointerController?.close() }
    }

    private func openPointer() {
        if pointerController == nil, let client = model.client {
            pointerController = PointerController(client: client, updatesPerSecond: session.caps?.pointerRate ?? 120)
        }
        pointerController?.open()
    }
}
#endif

#if os(iOS)
extension RemoteTab {
    /// A key of the cross, at most: the cross narrows with the screen.
    private static let padKey = CGSize(width: 104, height: 70)
    /// The volume's row: −, the value and the output, +, Mute.
    private static let volumeHeight: CGFloat = 56

    private func phone(_ stats: Stats?, controlsOff: Bool) -> some View {
        // The pins' edit sends nothing either.
        let buttonsOff = controlsOff || keyboard?.pinsEditing == true
        return VStack(alignment: .leading, spacing: 0) {
            section("Source") { phoneSources(stats.map(sources(from:)) ?? []) }
                .disabled(buttonsOff)
            PinnedSection(model: model, session: session, controlsOff: controlsOff)
                .padding(.top, 16)
            Group {
                if pointerMode && session.caps?.pointer == true {
                    pointerPad.padding(.top, 16)
                } else {
                    phonePad.padding(.top, 16)
                }
                HStack(spacing: Self.gap) {
                    GHButton("Back") { click(.rcu(.back)) }.keyed(.rcu(.back))
                    GHButton("Home") { click(.rcu(.home)) }.keyed(.rcu(.home))
                    GHButton("Settings") { click(.rcu(.settings)) }.keyed(.rcu(.settings))
                    if session.caps?.pointer == true {
                        Group {
                            if pointerMode {
                                GHButton("D-pad") { pointerMode = false }
                            } else {
                                GHButton("Pointer") { pointerMode = true }
                            }
                        }
                        .transaction { $0.animation = nil }
                    }
                }
                .padding(.top, 8)
                playback.padding(.top, 8)
                phoneVolume(stats).padding(.top, 12)
            }
            .disabled(buttonsOff)
        }
        // A key held down stops repeating as soon as it can no longer be pressed.
        .onChange(of: buttonsOff) { _, off in if off { stopRepeating() } }
        .onChange(of: pointerMode) { _, active in if !active { pointerController?.close() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && pointerMode { openPointer() }
            else { pointerController?.close() }
        }
    }

    private var pointerPad: some View {
        ZStack {
            if let pointerController { PointerPad(controller: pointerController) }
            Text("Slide to move · Tap to click\nUse two fingers to scroll")
                .font(.manrope(points: 13))
                .foregroundStyle(palette.label)
                .multilineTextAlignment(.center)
                .allowsHitTesting(false)
        }
        .frame(height: 220)
        .background(palette.key)
        .overlay(Rectangle().strokeBorder(palette.line, lineWidth: 1))
        .onAppear { openPointer() }
        .onDisappear { pointerController?.close() }
    }

    private func openPointer() {
        if pointerController == nil, let client = model.client {
            pointerController = PointerController(client: client, updatesPerSecond: session.caps?.pointerRate ?? 120)
        }
        pointerController?.open()
    }

    private func stopRepeating() {
        volumeDown.stop()
        volumeUp.stop()
        pointerController?.close()
    }

    /// Up to five sources share the row, their names cut to a word; more scroll, at the width five
    /// would have. A long press shows the whole name, and chooses it.
    @ViewBuilder private func phoneSources(_ list: [Source]) -> some View {
        if list.count <= 5 {
            HStack(spacing: Self.gap) {
                ForEach(list) { sourceKey($0) }
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: Self.gap) {
                    ForEach(list) { source in
                        sourceKey(source).containerRelativeFrame(.horizontal, count: 5, spacing: Self.gap)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func sourceKey(_ source: Source) -> some View {
        GHButton(selected: source.isActive, action: { click(.source(source.id)) }) {
            Text(verbatim: Self.shortName(source.label))
                .font(.manrope(10))
                .textCase(.uppercase)
                .tracking(Metrics.fontScale)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .contextMenu {
            Button { click(.source(source.id)) } label: { Text(verbatim: source.label) }
        }
        .accessibilityLabel(Text(verbatim: source.label))
        .accessibilityIdentifier("remote.source.\(source.id)")
        .keyed(.source(source.id))
    }

    /// A source's name on its key: its first word ("Denon", "PS5"), "TV" and "HDMI n" whole, past
    /// 8 characters cut with "…".
    static func shortName(_ name: String) -> String {
        if name == "TV" || name.range(of: #"^HDMI \d+$"#, options: .regularExpression) != nil { return name }
        let first = name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
        return first.count > 8 ? String(first.prefix(7)) + "…" : first
    }

    /// The cross, centred, its keys as wide as the screen allows up to `padKey`.
    private var phonePad: some View {
        VStack(spacing: Self.gap) {
            HStack(spacing: Self.gap) { padGap; padArrow(.up, "Up"); padGap }
            HStack(spacing: Self.gap) {
                padArrow(.left, "Left")
                GHButton(height: Self.padKey.height, action: { click(.rcu(.ok)) }) {
                    Text(verbatim: "OK").font(.manrope(points: 14)).tracking(0.84)
                }
                .frame(maxWidth: Self.padKey.width)
                .accessibilityIdentifier("remote.ok")
                .keyed(.rcu(.ok))
                padArrow(.right, "Right")
            }
            HStack(spacing: Self.gap) { padGap; padArrow(.down, "Down"); padGap }
        }
        .frame(maxWidth: .infinity)
    }

    private var padGap: some View {
        Color.clear.frame(maxWidth: Self.padKey.width).frame(height: Self.padKey.height)
    }

    private func padArrow(_ key: RemoteKey, _ name: LocalizedStringKey) -> some View {
        GHButton(height: Self.padKey.height, action: { click(.rcu(key)) }) {
            Triangle(pointing: key).fill(.foreground).frame(width: 14, height: 14)
        }
        .frame(maxWidth: Self.padKey.width)
        .accessibilityLabel(Text(name))
        .accessibilityIdentifier("remote.\(key.rawValue)")
        .keyed(.rcu(key))
    }

    /// − and + 78 pt wide, held down they repeat; between them the volume and the output; Mute
    /// apart on the right.
    private func phoneVolume(_ stats: Stats?) -> some View {
        let muted = stats?.muted ?? false
        let output = stats?.sound?.output ?? stats?.audioOutput
        return HStack(spacing: Self.gap) {
            volumeKey(.volumeDown, "−", "Volume down", repeater: volumeDown)
                .accessibilityIdentifier("remote.volumeDown")
            VStack(spacing: 0) {
                Text(verbatim: stats?.volume.map(String.init) ?? "–")
                    .font(.manrope(points: 26, .light))
                    .monospacedDigit()
                if let output {
                    Text(verbatim: output)
                        .font(.manrope(points: 9.5))
                        .tracking(0.95)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            volumeKey(.volumeUp, "+", "Volume up", repeater: volumeUp)
                .accessibilityIdentifier("remote.volumeUp")
            GHButton("Mute", selected: muted, height: Self.volumeHeight) { click(.mute) }
                .frame(width: 84)
                .accessibilityIdentifier("remote.mute")
                .keyed(.mute)
        }
        .frame(height: Self.volumeHeight)
        // Gone from the screen (another tab, another layout), it stops sending.
        .onDisappear { stopRepeating() }
    }

    private func volumeKey(_ id: ButtonID, _ face: String, _ name: LocalizedStringKey,
                           repeater: KeyRepeater) -> some View {
        GHButton(height: Self.volumeHeight, action: { repeater.released { click(id) } }) {
            Text(verbatim: face).font(.manrope(points: 24, .light))
        }
        .onPressChange { pressed in repeater.pressChanged(pressed) { click(id) } }
        .frame(width: 78)
        .accessibilityLabel(Text(name))
        .keyed(id)
    }
}

/// A key held down: its command again after 0.45 s, then every 0.15 s until it is let go, at most
/// `maxRepeats` times (30 steps, about 5 s), and never once the repeater is gone. The release after
/// repeats sends nothing more; a plain tap sends once, on release, like any key.
@MainActor final class KeyRepeater {
    static let maxRepeats = 30

    private var task: Task<Void, Never>?
    private var repeated = false

    deinit {
        task?.cancel()
    }

    func pressChanged(_ pressed: Bool, send: @escaping @MainActor () -> Void) {
        stop()
        guard pressed else { return }
        repeated = false
        task = Task { [weak self] in
            for step in 0..<KeyRepeater.maxRepeats {
                try? await Task.sleep(for: .milliseconds(step == 0 ? 450 : 150))
                // Not held across the sleep: a repeater that went away sends nothing more.
                guard !Task.isCancelled, let self else { return }
                self.repeated = true
                send()
            }
        }
    }

    /// No more repeats, the finger down or not.
    func stop() {
        task?.cancel()
        task = nil
    }

    /// The key's action, on release.
    func released(_ send: () -> Void) {
        if repeated {
            repeated = false
        } else {
            send()
        }
    }
}
#endif

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
