import PaneKit
import SwiftUI

/// What is typed for the TV, over the pointer pad's help, in the "Lumière" look
/// (mockups/2026-11-19-saisie-texte/mac-placement.html, option A): letters that light up with a short
/// halo, a blinking caret, a faint glow behind; deleted letters going out where they stood; a line at
/// the bottom when the TV's answers say something of the text, and "Sent" after Return. With a control
/// in the bottom right corner (the iPhone's keyboard icon, mockups/2026-11-19-saisie-texte/
/// iphone-clavier.html), "Sent" goes to the top right corner.
///
/// `TypingEcho` says how each letter looks at each moment; this view only draws it. It redraws every
/// frame while something moves, and otherwise wakes up when the echo next changes by itself or the
/// caret blinks. Its face hides the help while letters show and fades out once they are gone; the
/// deleted letters and the bottom line are drawn apart from it, so they outlive it.
struct TypingEchoView: View {
    /// Half a blink, on then off (the mockup's 1.05 s cycle).
    private static let blinkHalf: TimeInterval = 0.525
    /// How long "Sent" stays.
    private static let sentFor: TimeInterval = 1.4
    /// The letters' room in the pad; the bottom line sits under it.
    private static let room = EdgeInsets(top: 22, leading: 16, bottom: 22, trailing: 16)

    let typing: TextTyping
    /// The width kept free at the bottom right for a control: the line stops before it.
    var cornerRoom: CGFloat = 0
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped when the echo changes by itself, so that the body reads the time again.
    @State private var wakes = 0

    var body: some View {
        let _ = wakes
        let echo = typing.echo
        let now = Date.timeIntervalSinceReferenceDate
        let phase = echo.phase(at: now)
        let sent = typing.sentAt.map { now - $0 < Self.sentFor } ?? false
        ZStack {
            TimelineView(.animation(paused: !echo.isAnimating(at: now))) { context in
                // Paused, the timeline keeps the date it stopped at: the body's own is newer.
                let time = max(context.date.timeIntervalSinceReferenceDate, now)
                ZStack {
                    face(echo, at: time, glowing: phase == .showing)
                        .opacity(phase == .hidden ? 0 : 1)
                        .animation(phase == .hidden ? .easeInOut(duration: 0.8).delay(0.25) : .easeOut(duration: 0.12),
                                   value: phase == .hidden)
                    departures(echo, at: time)
                }
            }
            bottomLine(sent: sent)
            if cornerRoom > 0 {
                sentLabel(sent)
                    .padding(.top, 8)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .animation(.easeOut(duration: 0.3), value: sent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .task(id: nextWake(echo, after: now)) {
            guard let wake = nextWake(echo, after: now) else { return }
            // A hair late, so that the time read then is past the wake-up.
            try? await Task.sleep(for: .seconds(max(0, wake - Date.timeIntervalSinceReferenceDate) + 0.01))
            if !Task.isCancelled { wakes &+= 1 }
        }
    }

    /// When the body must read the time again: the echo changes by itself, "Sent" goes, the caret blinks.
    private func nextWake(_ echo: TypingEcho, after now: TimeInterval) -> TimeInterval? {
        var times = [echo.nextWake(after: now)].compactMap { $0 }
        if let sentAt = typing.sentAt, sentAt + Self.sentFor > now { times.append(sentAt + Self.sentFor) }
        if !reduceMotion, echo.phase(at: now) == .showing {
            times.append((floor(now / Self.blinkHalf) + 1) * Self.blinkHalf)
        }
        return times.min()
    }

    // MARK: Face

    /// The pad's face over the help, the glow behind the letters, the letters and their halo.
    private func face(_ echo: TypingEcho, at time: TimeInterval, glowing: Bool) -> some View {
        let looks = echo.letters.indices.map { echo.look(ofLetter: $0, at: time) }
        // Letters deleted from the end keep their room until gone, as in the mockup: the text does not
        // move under them, and the caret stays after them.
        let room = Dictionary(echo.departures.filter {
            $0.index >= echo.letters.count && echo.removalProgress(of: $0, at: time) < 1
        }.map { ($0.index, $0.letter) }) { _, later in later }.sorted { $0.key < $1.key }.map(\.value)
        let size = TypingEcho.textSize(forCount: echo.letters.count + room.count)
        let caretOn = echo.phase(at: time) == .showing
            && (reduceMotion || Int(time / Self.blinkHalf).isMultiple(of: 2))
        let unseen = room.map { Glyph(letter: $0, opacity: 0) }
        return ZStack {
            palette.bg
            palette.key
            aura(on: glowing)
            if looks.contains(where: { $0.glow > 0 }) {
                letters(zip(echo.letters, looks).map { Glyph(letter: $0, opacity: $1.glow) } + unseen,
                        size: size, caret: .clear)
                    .blur(radius: 4)
            }
            letters(zip(echo.letters, looks).map { Glyph(letter: $0, opacity: $1.opacity) } + unseen, size: size,
                    caret: caretOn ? palette.fg : .clear)
        }
        // The field is invisible: the typed text is read here.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(echo.letters)))
        .accessibilityHidden(echo.letters.isEmpty)
    }

    /// White at 7% in the middle, gone at 62% of the way out, over a little more than the pad; on while
    /// typing, 0.2 s to light, 1.5 s to go out.
    private func aura(on: Bool) -> some View {
        EllipticalGradient(colors: [palette.fg.opacity(0.07), .clear], center: .center,
                           startRadiusFraction: 0, endRadiusFraction: 0.44)
            .padding(.horizontal, -10)
            .padding(.vertical, -30)
            .opacity(on ? 0.7 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: on ? 0.2 : 1.5), value: on)
    }

    // MARK: Deleted letters

    /// Each deletion's letters going out in 0.22 s where they stood: up 4 pt, down to 85%, blurred
    /// 2 pt. The letters before them are laid out unseen, as they were then, so that they land in place.
    private func departures(_ echo: TypingEcho, at time: TimeInterval) -> some View {
        let groups = Dictionary(grouping: echo.departures, by: \.start)
        return ZStack {
            ForEach(groups.keys.sorted(), id: \.self) { start in
                let going = (groups[start] ?? []).sorted { $0.index < $1.index }
                let p = going.first.map { echo.removalProgress(of: $0, at: time) } ?? 1
                if p < 1, let first = going.first {
                    let before = (0..<first.index).compactMap { letter(at: $0, in: echo) }
                    letters(before.map { Glyph(letter: $0, opacity: 0) }
                                + going.map { Glyph(letter: $0.letter, opacity: 1 - p, scale: 1 - 0.15 * p) },
                            size: TypingEcho.textSize(forCount: first.index + going.count), caret: .clear)
                        .offset(y: -4 * p)
                        .blur(radius: 2 * p)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The letter at `index` when a deletion began: still on screen, or itself going out.
    private func letter(at index: Int, in echo: TypingEcho) -> Character? {
        echo.letters.indices.contains(index) ? echo.letters[index] : echo.departures.first { $0.index == index }?.letter
    }

    // MARK: Letters

    private struct Glyph {
        let letter: Character
        let opacity: Double
        var scale: Double = 1
    }

    /// One layer of letters, each in the palette's colour at its own opacity, then the caret: Manrope
    /// 300, centred, wrapped between words. Every layer is laid out alike, so they sit on one another.
    private func letters(_ glyphs: [Glyph], size: Double, caret: Color) -> some View {
        let points = size * Metrics.fontScale
        var string = AttributedString()
        for glyph in glyphs {
            var piece = AttributedString(String(glyph.letter))
            piece.swiftUI.foregroundColor = palette.fg.opacity(glyph.opacity)
            if glyph.scale != 1 {
                piece.swiftUI.font = .manrope(size * glyph.scale, .light)
                // About the letter's middle, not its baseline.
                piece.swiftUI.baselineOffset = points * (1 - glyph.scale) * 0.3
            }
            string += piece
        }
        let text = Text(string) + Text(Self.caret(color: caret, height: points * 0.92)).baselineOffset(-0.1 * points)
        return EndVisible(room: Self.room) {
            text
                .font(.manrope(size, .light))
                .multilineTextAlignment(.center)
        }
    }

    /// The caret: 1.5 pt wide after a 2 pt gap, `.92em` high.
    private static func caret(color: Color, height: CGFloat) -> Image {
        Image(size: CGSize(width: 3.5, height: height)) { context in
            context.fill(Path(CGRect(x: 2, y: 0, width: 1.5, height: height)), with: .color(color))
        }
    }

    // MARK: Bottom line

    /// What the TV's answers say of the text, on the left; "Sent" on the right for 1.4 s after Return.
    /// Neither goes out with the letters.
    private func bottomLine(sent: Bool) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            if let notice = typing.notice {
                Text(verbatim: Self.message(notice))
                    .font(.manrope(10))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            if cornerRoom == 0 { sentLabel(sent) }
        }
        .padding(.leading, 10)
        .padding(.trailing, max(10, cornerRoom))
        .padding(.bottom, 7)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.3), value: typing.notice)
        .animation(.easeOut(duration: 0.3), value: sent)
    }

    private func sentLabel(_ sent: Bool) -> some View {
        Text(verbatim: "↵ " + String(localized: "Sent"))
            .font(.manrope(9))
            .textCase(.uppercase)
            .tracking(Metrics.fontScale)
            .foregroundStyle(palette.fg.opacity(0.6))
            .opacity(sent ? 1 : 0)
            .accessibilityHidden(!sent)
    }

    private static func message(_ notice: TypingNotice) -> String {
        switch notice {
        case .noField: String(localized: "No text field selected on the TV")
        case .lowercase: String(localized: "Lowercase only in this app")
        case .notSent: String(localized: "Text not sent")
        }
    }
}

/// One text over the whole pad, inside `room`: centred, or, taller than the room, its end on the room's
/// bottom, so that the last letters typed always show.
private struct EndVisible: Layout {
    let room: EdgeInsets

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = max(0, bounds.width - room.leading - room.trailing)
        let top = bounds.minY + room.top
        let bottom = bounds.maxY - room.bottom
        let middle = bounds.minX + room.leading + width / 2
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let y = size.height <= bottom - top ? (top + bottom - size.height) / 2 : bottom - size.height
            subview.place(at: CGPoint(x: middle, y: y), anchor: .top, proposal: ProposedViewSize(width: width, height: size.height))
        }
    }
}
