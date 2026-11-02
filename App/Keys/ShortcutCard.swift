import AppKit
import PaneKit
import SwiftUI

/// The card under the menu-bar icon while a global shortcut runs with the popover closed: the
/// button's tile, its name and what is happening, then the result for 2 s. It takes neither the
/// keyboard nor the mouse, and never makes Pane active.
@MainActor final class ShortcutCard {
    static let width: CGFloat = 260
    /// Between the menu-bar button and the card.
    private static let gap: CGFloat = 6
    private static let fade: TimeInterval = 0.15

    private let panel: NSPanel
    private var hosting: NSHostingController<ShortcutCardView>?
    private weak var button: NSStatusBarButton?
    private weak var model: AppModel?
    /// The press shown, kept while the card is hidden, so that a press of the same button can join it.
    private var current: (id: ButtonID, phase: ShortcutPhase)?
    private var height: CGFloat = 0
    private var visible = false
    private var hideTask: Task<Void, Never>?
    /// Watches a wait that a press joined without owning it (see `release`).
    private var releaseTask: Task<Void, Never>?
    /// Each press shown gets the next number, which `finish` must bring back: an earlier press of
    /// another button that ends later (an action the Power shortcut cancelled while it waited)
    /// leaves the card alone.
    private var generation = 0
    /// How long a joined wait is watched at most: the power-on's timeout, its settle pause, a margin.
    private static let longestWait: Duration = TVSession.powerOnTimeout + TVSession.settlePause + .seconds(10)

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// Shows the press as running, in place of the card shown; returns the number to finish it with.
    /// A press of the button whose press still runs joins that one (an action pressed again during
    /// its wait returns `.replaced`, and the first press ends the card).
    @discardableResult func show(for id: ButtonID, model: AppModel, below button: NSStatusBarButton) -> Int {
        if current?.id != id || current?.phase != .running {
            generation += 1
            releaseTask?.cancel()
        }
        current = (id, .running)
        self.model = model
        self.button = button
        hideTask?.cancel()
        panel.appearance = model.theme.appearance
        render()
        if !visible {
            visible = true
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            panel.animator().alphaValue = 1
        }
        return generation
    }

    /// The press numbered `token`, of `id`, ended: its result, then the card goes 2 s later.
    /// Ignored once a later press took the card, unless the card still runs for the same button: a
    /// shortcut pressed again during its action's wait got a newer number (another card came
    /// between, say), and the first press, which owns the wait, brings the real result.
    /// Recorded only while the card is hidden (the popover opened).
    func finish(_ phase: ShortcutPhase, for token: Int, id: ButtonID) {
        guard token == generation || (current?.id == id && current?.phase == .running) else { return }
        current = (id, phase)
        releaseTask?.cancel()
        guard visible else { return }
        render()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// The press of `id` ended without a phase: it joined the wait of its action, pending already.
    /// The press that owns the wait may have no card (it came from the popover), so the card is not
    /// left running: it says "Turning on the TV…" while the action waits, then, if no result came
    /// within the time its steps take, it goes. The watch is bounded by the longest power-on.
    func release(for token: Int, id: ButtonID) {
        guard token == generation, current?.id == id, current?.phase == .running, let model else { return }
        let steps = id.actionID.flatMap { actionID in
            model.store.activeID.flatMap { tv in model.actions.actions(for: tv).first { $0.id == actionID } }
        }?.steps.count ?? 1
        let grace = TVSession.stepPause * max(steps - 1, 0) + .seconds(5)
        releaseTask?.cancel()
        releaseTask = Task { [weak self, weak model] in
            let clock = ContinuousClock()
            let deadline = clock.now + Self.longestWait
            while model?.session?.pendingAction.map({ ButtonID.action($0.id) }) == id, clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: grace)
            guard let self, !Task.isCancelled, token == self.generation,
                  self.current?.id == id, self.current?.phase == .running else { return }
            self.hide()
        }
    }

    /// Fades the card out (the popover opens, or its 2 s are up).
    func hide() {
        hideTask?.cancel()
        guard visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                // A show during the fade keeps it up.
                guard let self, !self.visible else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func render() {
        guard let model, let current else { return }
        let view = ShortcutCardView(id: current.id, phase: current.phase, model: model) { [weak self] height in
            self?.resize(to: height)
        }
        if let hosting {
            hosting.rootView = view
        } else {
            let hosting = NSHostingController(rootView: view)
            // The card sets the panel's frame itself: measured here, then from the height the view reports.
            hosting.sizingOptions = []
            panel.contentView = hosting.view
            self.hosting = hosting
        }
        resize(to: hosting?.sizeThatFits(in: NSSize(width: Self.width, height: 1000)).height ?? 0)
    }

    private func resize(to height: CGFloat) {
        self.height = height
        place()
    }

    /// Centred under the button, 6 pt below it, kept on the button's screen.
    private func place() {
        guard let button, let window = button.window, height > 0 else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        var x = anchor.midX - Self.width / 2
        if let screen = window.screen?.visibleFrame {
            x = min(max(x, screen.minX + Self.gap), screen.maxX - Self.width - Self.gap)
        }
        panel.setFrame(NSRect(x: x, y: anchor.minY - Self.gap - height, width: Self.width, height: height), display: true)
        panel.invalidateShadow()
    }
}

/// The card's face, in the popover's style: the tile, the name in capitals, the state under it.
private struct ShortcutCardView: View {
    let id: ButtonID
    let phase: ShortcutPhase
    let model: AppModel
    let onHeight: (CGFloat) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Palette.of(colorScheme)
        let action = action
        let failed = if case .failed = phase { true } else { false }
        HStack(spacing: 10) {
            ShortcutTile(id: id, action: action, model: model)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title(action))
                    .font(.manrope(11))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .truncationMode(.tail)
                state(action, palette: palette)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: ShortcutCard.width)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(palette.fg)
        .background(palette.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(failed ? Color.red.opacity(0.6) : palette.line))
        .environment(\.palette, palette)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
    }

    /// The active TV's action the shortcut runs; nil for a button or a source.
    private var action: CustomAction? {
        guard let actionID = id.actionID, let tv = model.store.activeID else { return nil }
        return model.actions.actions(for: tv).first { $0.id == actionID }
    }

    private func title(_ action: CustomAction?) -> String {
        let inputs = model.session?.stats.map(sources(from:)) ?? []
        return id.title(sources: inputs, actions: action.map { [$0] } ?? [])
    }

    /// Running: "Turning on the TV…" over a moving bar while the action waits for the TV, "…"
    /// otherwise. Then the result, in red for a failure.
    @ViewBuilder private func state(_ action: CustomAction?, palette: Palette) -> some View {
        switch phase {
        case .running:
            if let action, model.session?.pendingAction?.id == action.id {
                stateText(String(localized: "Turning on the TV…"), color: palette.label)
                IndeterminateBar().padding(.top, 6)
            } else {
                stateText("…", color: palette.label)
            }
        case .done(let text): stateText(text, color: palette.label)
        case .failed(let text): stateText(text, color: .red)
        }
    }

    private func stateText(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.manrope(10.5))
            .foregroundStyle(color)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }
}

/// The tile on the card's left: the app's icon for an action shown as one (on the colour of the
/// icon's edge, as the pins show it), else the button's symbol, else the title as text.
private struct ShortcutTile: View {
    let id: ButtonID
    let action: CustomAction?
    let model: AppModel
    @Environment(\.palette) private var palette

    private static let size = CGSize(width: 40, height: 28)

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Self.size.height, height: Self.size.height)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .background(icon.edge.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) } ?? .clear)
                    .overlay(Rectangle().strokeBorder(icon.edge.map { $0.blends(into: background) } ?? true ? palette.line : .clear))
            } else {
                Group {
                    if let symbol = Self.symbol(for: id) {
                        Image(systemName: symbol).font(.system(size: 13))
                    } else {
                        Text(verbatim: action?.title ?? id.rawValue)
                            .font(.manrope(7.5, .semibold))
                            .textCase(.uppercase)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 2)
                    }
                }
                .frame(width: Self.size.width, height: Self.size.height)
                .overlay(Rectangle().strokeBorder(palette.line))
            }
        }
        .accessibilityHidden(true)
    }

    /// The icon of the app the action launches and its edge, when it is shown as one and the icon came.
    private var icon: (image: NSImage, edge: IconColor?)? {
        guard let action, action.shownTile == .icon, let app = action.iconAppID, let data = model.icons.icon(for: app),
              let image = NSImage(data: data) else { return nil }
        return (image, model.icons.edge(for: app))
    }

    /// The card's background, which the tile's colour must stand out from.
    private var background: IconColor {
        guard let c = NSColor(palette.bg).usingColorSpace(.sRGB) else { return IconColor(red: 0, green: 0, blue: 0) }
        return IconColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
    }

    /// The SF Symbol of a fixed button or a source; nil for an action.
    static func symbol(for id: ButtonID) -> String? {
        id.sourceID != nil ? "rectangle.connected.to.line.below" : symbols[id.rawValue]
    }

    private static let symbols: [String: String] = [
        "power": "power",
        "rcu.up": "chevron.up", "rcu.down": "chevron.down", "rcu.left": "chevron.left", "rcu.right": "chevron.right",
        "rcu.ok": "smallcircle.filled.circle", "rcu.back": "arrow.uturn.backward", "rcu.home": "house",
        "rcu.settings": "gearshape",
        "media.rewind": "backward.fill", "media.playPause": "playpause.fill", "media.stop": "stop.fill",
        "media.fastForward": "forward.fill",
        "volume.down": "speaker.wave.1.fill", "volume.up": "speaker.wave.3.fill", "mute": "speaker.slash.fill",
    ]
}

/// A 2 pt track with a segment sliding across it, left to right, again and again.
private struct IndeterminateBar: View {
    @Environment(\.palette) private var palette

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { proxy in
                let width = proxy.size.width
                let segment = width * 0.45
                let progress = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                Rectangle()
                    .fill(palette.global)
                    .frame(width: segment)
                    .offset(x: -segment + (width + segment) * progress)
            }
        }
        .frame(height: 2)
        .background(palette.divider)
        .clipped()
    }
}
