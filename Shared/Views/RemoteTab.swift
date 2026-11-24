import PaneKit
import SwiftUI

/// The remote: sources, d-pad, playback, volume, pinned actions. Every button goes through the
/// keyboard controller and can carry a key; all but the pins' "+" are off when the TV can't be
/// controlled, unless the keys show: a click then chooses the button and sends nothing. On iOS, the
/// whole remote on one screen (mockups/2026-11-02-ios/iphone-compact.html, B1): the sources on one
/// row, the pins on one row, the ring d-pad, the navigation and playback rows, then the volume's.
struct RemoteTab: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.keyboard) private var keyboard
    @State private var pointerMode = Self.startsInPointer
    @State private var pointerController: PointerController?
    /// What is typed in the pointer's pad, for this TV.
    @State private var typing: TextTyping?
    @Environment(\.palette) private var palette
    @Environment(\.keyShape) private var keyShape
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    /// How the Mac pad moves the TV's pointer: the stored `PointerMoveGesture`.
    @AppStorage(PointerMoveGesture.defaultsKey) private var storedGesture = ""
    /// A gesture is under way: the Mac cursor is frozen and the mouse drives the TV's pointer.
    @State private var pointerDriving = false
    #endif
    #if os(iOS)
    /// − and + held down repeat, each on its own.
    @State private var volumeDown = KeyRepeater()
    @State private var volumeUp = KeyRepeater()
    @Environment(\.scenePhase) private var scenePhase
    #endif

    private static let gap: CGFloat = 6

    /// Screenshots (-PanePointer YES): the pad in place of the ring, where the TV offers it.
    private static var startsInPointer: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "PanePointer")
        #else
        false
        #endif
    }

    var body: some View {
        let stats = session.stats
        let controlsOff = keyboard?.state.sendsCommands != false && !session.canControl
        #if os(iOS)
        phone(stats, controlsOff: controlsOff)
        #else
        VStack(alignment: .leading, spacing: 14) {
            Group {
                section("Source") { sourceGrid(stats.map(sources(from:)) ?? []) }
                pointerOrDpad(controlsOff: controlsOff)
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

    #if os(macOS)
    /// The ring, or the pad with the gesture picker on its title.
    @ViewBuilder
    private func pointerOrDpad(controlsOff: Bool) -> some View {
        if showsPointer {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Pointer") { PointerGesturePicker(selection: gestureBinding) }
                VStack(spacing: Self.gap) {
                    pointerMacPad(controlsOff: controlsOff)
                    navigation
                }
            }
        } else {
            section("D-pad") { dpad }
        }
    }

    private var gesture: PointerMoveGesture { PointerMoveGesture(stored: storedGesture.isEmpty ? nil : storedGesture) }

    private var gestureBinding: Binding<PointerMoveGesture> {
        Binding(get: { gesture }, set: { storedGesture = $0.rawValue })
    }
    #endif

    private func click(_ id: ButtonID) {
        keyboard?.buttonClicked(id)
    }

    // MARK: Pointer

    /// The pad in place of the ring: chosen, and offered by this TV's Glasshouse.
    private var showsPointer: Bool { pointerMode && session.caps?.pointer == true }

    /// Opens the pointer to the TV shown, in place of one opened to another TV or token.
    private func openPointer() {
        let rate = session.caps?.pointerRate ?? 120
        if let client = model.client {
            if pointerController?.needsReplacement(for: client.endpoint) ?? true {
                pointerController?.close()
                pointerController = PointerController(client: client, updatesPerSecond: rate)
            }
        } else if model.isDemo {
            // The demo has no TV: an offline pad, so that its gestures and keys still show.
            if pointerController?.needsReplacement(for: nil) ?? true {
                pointerController?.close()
                pointerController = PointerController.offline(updatesPerSecond: rate)
            }
        } else {
            return
        }
        pointerController?.open()
    }

    /// The pad takes the keys, for the TV shown: a new typing for another TV, the old text forgotten.
    /// Not the keys while the pad can't send (iOS: the pins' edit, a TV out of reach). On iOS the keys
    /// are the pad's only while its field holds them: `PointerSurface` follows the field itself, so that
    /// a hardware keyboard presses the buttons again once the field is lowered.
    private func openTyping(takesKeys: Bool = true) {
        #if os(macOS)
        keyboard?.typing = takesKeys
        #endif
        guard typing?.session !== session else { return }
        typing?.forget()
        typing = TextTyping(session: session, reducedMotion: reduceMotion)
    }

    /// The pad goes: the keys are the buttons' again, and the text is forgotten on Pane's side.
    private func closeTyping() {
        keyboard?.typing = false
        typing?.forget()
    }

    // MARK: Source

    private func sourceGrid(_ list: [Source]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: max(1, min(5, list.count)))
        return LazyVGrid(columns: columns, spacing: Self.gap) {
            ForEach(list) { source in
                GHButton(name: source.label, selected: source.isActive, action: { click(.source(source.id)) })
                .help(Text(verbatim: source.label))
                .keyed(.source(source.id))
            }
        }
    }

    // MARK: D-pad

    #if os(macOS)
    private var dpad: some View {
        VStack(spacing: Self.gap) {
            ring(diameter: Metrics.ringDiameter)
            navigation
        }
        .frame(maxWidth: .infinity)
    }
    #endif

    /// The ring d-pad, each of its parts a key in its own shape.
    private func ring(diameter: CGFloat) -> some View {
        DpadRingView(diameter: diameter) { part, shape, anchor in
            ringKey(part, diameter: diameter)
                // Outside every modifier of the key, `.keyed` among them, which all go by its shape.
                .environment(\.keyShape, shape)
                .environment(\.keyTileAnchor, anchor)
        }
    }

    /// A part of the ring: its chevron at the middle of its quarter, or OK in Outfit; its name as
    /// VoiceOver's label (OK says itself) and, on the Mac, as the help of a square around its
    /// chevron, the identifier the app previews find it by (`remote.up`, `remote.ok`...), and its key.
    private func ringKey(_ part: RingPart, diameter: CGFloat) -> some View {
        let key = part.remoteKey
        let ring = DpadRing(diameter: diameter)
        let icon = ring.iconCenter(part)
        return GHButton(height: diameter, outlined: false, action: { click(.rcu(key)) }) {
            ZStack {
                Group {
                    if part == .ok {
                        Text(verbatim: "OK").font(Self.okFont).tracking(Metrics.okSize * 0.04)
                    } else {
                        KeyIconView(KeyIcon(arrow: key), size: Metrics.ringArrowIcon)
                    }
                }
                .position(icon)
                #if os(macOS)
                if let name = part.name { helpArea(ring).help(Text(name)).position(icon) }
                #endif
            }
            .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(part.name.map { Text($0) } ?? Text(verbatim: "OK"))
        .accessibilityHint(Text(verbatim: ""))
        .accessibilityIdentifier("remote.\(key.rawValue)")
        .keyed(.rcu(key))
    }

    #if os(macOS)
    /// Where a direction's help shows: a square around its chevron, inside its quarter. Each key's
    /// frame is the whole ring's square, and AppKit shows help by rectangle: on the frames, the
    /// topmost would show its name over all four. Nor can one help on the ring follow the part
    /// under the pointer, as a tooltip already shown keeps its text while the pointer stays in its
    /// rectangle. A square of 85 % of the ring's width, around the chevron, keeps clear of the
    /// circles and of its neighbours; the diagonals show none.
    private func helpArea(_ ring: DpadRing) -> some View {
        let side = (ring.outerRadius - ring.okRadius) * 0.85
        return Color.clear.frame(width: side, height: side).contentShape(Rectangle())
    }
    #endif

    #if os(iOS)
    private static let okFont = Font.outfit(points: Metrics.okSize)
    #else
    private static let okFont = Font.outfit(Metrics.okSize)
    #endif

    private var navigation: some View {
        HStack(spacing: Self.gap) {
            GHButton(action: { click(.rcu(.back)) }) { KeyIconView(.back) }
                .keyName("Back").keyed(.rcu(.back))
            GHButton(action: { click(.rcu(.home)) }) { KeyIconView(.home) }
                .keyName("Home").keyed(.rcu(.home))
            GHButton(action: { click(.rcu(.settings)) }) { KeyIconView(.settings) }
                .keyName("Settings").keyed(.rcu(.settings))
            if session.caps?.pointer == true {
                // The key shows the mode it leads to.
                Group {
                    if pointerMode {
                        GHButton(action: { pointerMode = false }) { KeyIconView(.dpad) }.keyName("D-pad")
                            .accessibilityIdentifier("remote.pointerSwap")
                    } else {
                        GHButton(action: { pointerMode = true }) { KeyIconView(.pointer) }.keyName("Pointer")
                            .accessibilityIdentifier("remote.pointerSwap")
                    }
                }
                .transaction { $0.animation = nil }
                .environment(\.palette, palette.swapKey)
            }
        }
    }

    // MARK: Playback

    private var playback: some View {
        HStack(spacing: Self.gap) {
            media(.rewind, .rewind, "Rewind")
            media(.playPause, .playPause, "Play/Pause")
            media(.stop, .stop, "Stop")
            media(.fastForward, .fastForward, "Fast forward")
        }
    }

    private func media(_ key: MediaKey, _ icon: KeyIcon, _ name: LocalizedStringKey) -> some View {
        GHButton(action: { click(.media(key)) }) { KeyIconView(icon) }
            .keyName(name)
            .keyed(.media(key))
    }

    // MARK: Volume

    private func volume(_ stats: Stats?) -> some View {
        let muted = stats?.muted ?? false
        return WeightedRow(weights: [1, 1.2, 1, 1.6], spacing: Self.gap) {
            GHButton(action: { click(.volumeDown) }) { KeyIconView(.volumeDown) }
                .keyName("Volume down")
                .keyed(.volumeDown)
            Text(verbatim: stats?.volume.map(String.init) ?? "–")
                .font(.outfit(20, .thin))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
            GHButton(action: { click(.volumeUp) }) { KeyIconView(.volumeUp) }
                .keyName("Volume up")
                .keyed(.volumeUp)
            GHButton(selected: muted, action: { click(.mute) }) { KeyIconView(.mute) }
                .keyName("Mute").keyed(.mute)
        }
        .frame(height: 34)
    }
}

#if os(macOS)
extension RemoteTab {
    /// What to do to move the pointer, for the gesture picked.
    @ViewBuilder
    private var padHelp: some View {
        switch gesture {
        case .drag:
            Text("Click and drag to move\nClick to select\nRight-click to go back\nScroll with the wheel or two fingers")
                .foregroundStyle(palette.label)
        case .option:
            VStack(spacing: 0) {
                optionHoldLine
                Text("Click to select\nRight-click to go back\nScroll with the wheel or two fingers")
            }
            .foregroundStyle(palette.label)
        }
    }

    /// "Hold ⌥ and move to point", the ⌥ in a small frame; the sentence's order is the language's.
    /// VoiceOver reads it in one go, with the key's name.
    private var optionHoldLine: some View {
        let sentence = String(localized: "Hold %@ and move to point")
        let parts = sentence.components(separatedBy: "%@")
        return HStack(spacing: 0) {
            Text(verbatim: parts.first ?? "")
            Text(verbatim: "⌥")
                .font(.manrope(11, .semibold))
                .padding(.horizontal, 4)
                .overlay(RoundedRectangle(cornerRadius: Metrics.smallRadius).strokeBorder(palette.frame, lineWidth: 1))
                .padding(.horizontal, 1)
            Text(verbatim: parts.dropFirst().joined())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: sentence.replacingOccurrences(of: "%@", with: String(localized: "Option"))))
    }

    private func pointerMacPad(controlsOff: Bool) -> some View {
        let active = !(controlsOff || keyboard?.pinsEditing == true)
        return ZStack {
            // A new controller or typing (another TV) needs a new view: the old one keeps its own.
            if let pointerController, let typing {
                PointerMacPad(controller: pointerController, typing: typing, gesture: gesture, active: active,
                              drivingChanged: { pointerDriving = $0 })
                    .id([ObjectIdentifier(pointerController), ObjectIdentifier(typing)])
            }
            VStack(spacing: 6) {
                padHelp
                Text("Type to write on the TV")
                    .foregroundStyle(palette.fg.opacity(0.85))
            }
            .font(.manrope(13))
            .multilineTextAlignment(.center)
            .opacity(pointerDriving ? 0.35 : 1)
            .allowsHitTesting(false)
            // Over the help, which shows again once the letters are gone.
            if let typing { TypingEchoView(typing: typing) }
        }
        // The ring's height: the popover keeps its size from one mode to the other.
        .frame(height: Metrics.ringDiameter)
        .background(palette.key, in: keyShape)
        .overlay(keyShape.strokeInside(pointerDriving ? palette.fg : palette.line, style: StrokeStyle(lineWidth: 1)))
        .overlay(alignment: .bottom) {
            if pointerDriving {
                Text("Moving the pointer")
                    .sectionLabelStyle()
                    .padding(.bottom, 7)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: pointerDriving)
        .onAppear {
            openPointer()
            openTyping()
        }
        .onDisappear {
            pointerDriving = false
            pointerController?.close()
            closeTyping()
        }
        .onChange(of: model.client?.endpoint) { openPointer() }
        .onChange(of: ObjectIdentifier(session)) { openTyping() }
        // The TV's focus may have moved (Back, Home, a source, a pin, a global shortcut...).
        .onChange(of: session.focusEpoch) { typing?.forget() }
        .onChange(of: model.isOpen) { _, open in
            if !open { typing?.forget() }
        }
    }
}
#endif

#if os(iOS)
extension RemoteTab {
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
                // A tall screen's spare room, half above the ring (or the pad), half under it
                // (mockups/2026-11-22-espace-remote, A). Without any, the spacers take nothing.
                Spacer(minLength: 0)
                if showsPointer {
                    pointerPad(buttonsOff: buttonsOff).padding(.top, 16)
                } else {
                    phonePad.padding(.top, 16)
                }
                Spacer(minLength: 0)
                navigation
                    .padding(.top, 8)
                playback.padding(.top, 8)
                phoneVolume(stats).padding(.top, 12)
                // Some of it, 12 pt at most, keeps the volume off the tab bar.
                Spacer(minLength: 0).frame(maxHeight: 12)
            }
            .disabled(buttonsOff)
        }
        // A key held down stops repeating as soon as it can no longer be pressed.
        .onChange(of: buttonsOff) { _, off in
            if off {
                stopRepeating()
                pointerController?.close()
                closeTyping()
            } else if showsPointer {
                openPointer()
                openTyping()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && showsPointer && !buttonsOff { openPointer() }
            else { pointerController?.close() }
            // The pad lowers its keyboard itself; a moment away (Control Center) keeps the text.
            if phase == .background { closeTyping() }
            else if phase == .active && showsPointer && !buttonsOff { openTyping() }
        }
    }

    private func pointerPad(buttonsOff: Bool) -> some View {
        ZStack {
            // A new controller or typing (another TV) needs a new view: the old one keeps its own.
            if let pointerController, let typing {
                PointerPad(controller: pointerController, typing: typing)
                    .id([ObjectIdentifier(pointerController), ObjectIdentifier(typing)])
            }
        }
        // The ring's height: the screen keeps its height from one mode to the other.
        .frame(height: Metrics.ringDiameter)
        .background(palette.key, in: keyShape)
        .overlay(keyShape.strokeInside(palette.line, style: StrokeStyle(lineWidth: 1)))
        .onAppear {
            openPointer()
            openTyping(takesKeys: !buttonsOff)
        }
        .onDisappear {
            pointerController?.close()
            closeTyping()
        }
        .onChange(of: model.client?.endpoint) { openPointer() }
        .onChange(of: ObjectIdentifier(session)) { openTyping(takesKeys: !buttonsOff) }
        // The TV's focus may have moved (Back, Home, a source, a pin...).
        .onChange(of: session.focusEpoch) { typing?.forget() }
    }

    private func stopRepeating() {
        volumeDown.stop()
        volumeUp.stop()
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
        GHButton(name: Self.shortName(source.label), selected: source.isActive, action: { click(.source(source.id)) })
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

    /// The ring, centred, as wide as the screen allows up to `Metrics.ringDiameter` (the iPad's
    /// column too: its cross had the phone's size).
    private var phonePad: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: Metrics.ringDiameter)
            .overlay {
                GeometryReader { proxy in ring(diameter: min(proxy.size.width, proxy.size.height)) }
            }
            .frame(maxWidth: .infinity)
    }

    /// − and + 78 pt wide, held down they repeat; between them the volume and the output; Mute
    /// apart on the right.
    private func phoneVolume(_ stats: Stats?) -> some View {
        let muted = stats?.muted ?? false
        let output = stats?.sound?.output ?? stats?.audioOutput
        return HStack(spacing: Self.gap) {
            volumeKey(.volumeDown, .volumeDown, "Volume down", repeater: volumeDown)
                .accessibilityIdentifier("remote.volumeDown")
            VStack(spacing: 0) {
                Text(verbatim: stats?.volume.map(String.init) ?? "–")
                    .font(.outfit(points: 32, .thin))
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
            volumeKey(.volumeUp, .volumeUp, "Volume up", repeater: volumeUp)
                .accessibilityIdentifier("remote.volumeUp")
            GHButton(selected: muted, height: Self.volumeHeight, action: { click(.mute) }) { KeyIconView(.mute) }
                .keyName("Mute")
                .frame(width: 84)
                .accessibilityIdentifier("remote.mute")
                .keyed(.mute)
        }
        .frame(height: Self.volumeHeight)
        // Gone from the screen (another tab, another layout), it stops sending.
        .onDisappear { stopRepeating() }
    }

    private func volumeKey(_ id: ButtonID, _ icon: KeyIcon, _ name: LocalizedStringKey,
                           repeater: KeyRepeater) -> some View {
        GHButton(height: Self.volumeHeight, action: { repeater.released { click(id) } }) {
            KeyIconView(icon)
        }
        .onPressChange { pressed in repeater.pressChanged(pressed) { click(id) } }
        .frame(width: 78)
        .keyName(name)
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

private extension RingPart {
    /// The key the part sends.
    var remoteKey: RemoteKey {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .ok: .ok
        }
    }

    /// Its name, for its help and VoiceOver; none for OK, whose face says it.
    var name: LocalizedStringKey? {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .ok: nil
        }
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
