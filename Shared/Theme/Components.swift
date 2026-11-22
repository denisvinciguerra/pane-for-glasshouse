import PaneKit
import SwiftUI

/// A dashboard button: the key's shape (`\.keyShape`, rounded by default), a soft 1 pt edge that
/// strengthens under the pointer on the Mac, its face at `ink` until hovered, selected or pressed.
/// Its face is a command in 10 pt capitals, a name as given in Outfit, or a drawn shape. Selected:
/// full-strength edge, a faint fill and a 5 pt `on` dot before the face. Dimmed: greyed like a
/// disabled one, still clickable. Dashed: a dashed edge and a faint face (the "+" that adds). Filled:
/// a solid colour under the face, its edge drawn only when `outlined`, darker while pressed.
struct GHButton: View {
    private let title: LocalizedStringKey?
    private let name: String?
    private let selected: Bool
    private let dimmed: Bool
    private let dashed: Bool
    private let height: CGFloat
    private let fill: Color?
    private let outlined: Bool
    private let shape: AnyView?
    private let action: () -> Void
    #if os(iOS)
    /// Told when the finger comes down on the button and when it leaves it.
    private var pressChange: ((Bool) -> Void)?
    #endif
    @Environment(\.keyShape) private var keyShape

    /// A button whose face is a drawn shape (a key's icon, the d-pad's chevrons) instead of a title.
    init<Face: View>(selected: Bool = false, dimmed: Bool = false, dashed: Bool = false, height: CGFloat = Metrics.buttonHeight,
                     fill: Color? = nil, outlined: Bool = true, action: @escaping () -> Void, @ViewBuilder face: () -> Face) {
        self.title = nil
        self.name = nil
        self.selected = selected
        self.dimmed = dimmed
        self.dashed = dashed
        // A finger's least target on iOS; none on the Mac.
        self.height = max(height, Metrics.minTouch)
        self.fill = fill
        self.outlined = outlined
        self.shape = AnyView(face())
        self.action = action
    }

    /// A command: its title in capitals.
    init(_ title: LocalizedStringKey?, selected: Bool = false, dimmed: Bool = false,
         dashed: Bool = false, height: CGFloat = Metrics.buttonHeight, action: @escaping () -> Void) {
        self.title = title
        self.name = nil
        self.selected = selected
        self.dimmed = dimmed
        self.dashed = dashed
        self.height = max(height, Metrics.minTouch)
        self.fill = nil
        self.outlined = true
        self.shape = nil
        self.action = action
    }

    /// A name (a source, a pin), shown as given: Outfit, no forced capitals (`KeyName`).
    init(name: String, selected: Bool = false, dimmed: Bool = false, dashed: Bool = false,
         height: CGFloat = Metrics.buttonHeight, action: @escaping () -> Void) {
        self.title = nil
        self.name = name
        self.selected = selected
        self.dimmed = dimmed
        self.dashed = dashed
        self.height = max(height, Metrics.minTouch)
        self.fill = nil
        self.outlined = true
        self.shape = nil
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected { OnDot(size: 5) }
                if let shape { shape }
                if let title {
                    Text(title).textCase(.uppercase).tracking(Metrics.fontScale).lineLimit(1).minimumScaleFactor(0.8)
                }
                if let name { KeyName(name: name) }
            }
            .font(.manrope(10))
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .contentShape(keyShape)
        }
        #if os(iOS)
        .buttonStyle(GHButtonStyle(selected: selected, dimmed: dimmed, dashed: dashed, fill: fill, outlined: outlined,
                                   pressChange: pressChange))
        #else
        .buttonStyle(GHButtonStyle(selected: selected, dimmed: dimmed, dashed: dashed, fill: fill, outlined: outlined))
        #endif
    }

    #if os(iOS)
    /// The button, telling `change` when it is pressed and released (a key that repeats).
    func onPressChange(_ change: @escaping (Bool) -> Void) -> GHButton {
        var button = self
        button.pressChange = change
        return button
    }
    #endif
}

private struct GHButtonStyle: ButtonStyle {
    let selected: Bool
    let dimmed: Bool
    let dashed: Bool
    let fill: Color?
    let outlined: Bool
    #if os(iOS)
    let pressChange: ((Bool) -> Void)?
    #endif

    func makeBody(configuration: Configuration) -> some View {
        #if os(iOS)
        GHButtonFace(label: configuration.label, pressed: configuration.isPressed, selected: selected, dimmed: dimmed,
                     dashed: dashed, fill: fill, outlined: outlined, pressChange: pressChange)
        #else
        GHButtonFace(label: configuration.label, pressed: configuration.isPressed, selected: selected, dimmed: dimmed,
                     dashed: dashed, fill: fill, outlined: outlined)
        #endif
    }
}

/// A `GHButton` as drawn: a view of its own, as a button style keeps no state and the face holds
/// whether the pointer is over it.
private struct GHButtonFace: View {
    let label: ButtonStyleConfiguration.Label
    let pressed: Bool
    let selected: Bool
    let dimmed: Bool
    let dashed: Bool
    let fill: Color?
    let outlined: Bool
    #if os(iOS)
    let pressChange: ((Bool) -> Void)?
    #endif
    @Environment(\.palette) private var palette
    @Environment(\.keyShape) private var shape
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.keyHover) private var hoverGiven
    /// The pointer over the face, as its own `onHover` sees it.
    @State private var pointerOver = false

    var body: some View {
        label
            .foregroundStyle(ink)
            .background(background, in: shape)
            // A tile's icon kept within its rounded corners.
            .clipShape(shape)
            .brightness(fill != nil && pressed ? -0.15 : 0)
            .overlay(shape.strokeInside(edge, style: StrokeStyle(lineWidth: selected ? palette.activeLineWidth : 1,
                                                                 dash: dashed ? [3, 2] : [])))
            // Greyed as one: an icon over its fill would otherwise show through brighter than the fill.
            .compositingGroup()
            .opacity(isEnabled && !dimmed ? 1 : 0.35)
            #if os(macOS)
            .onHover { pointerOver = $0 }
            #else
            .onChange(of: pressed) { _, pressed in pressChange?(pressed) }
            #endif
    }

    /// Under the pointer, as its container tells it or as seen; never while greyed.
    private var hovered: Bool { isEnabled && (hoverGiven ?? pointerOver) }

    private var ink: Color {
        if dashed { return palette.fg.opacity(0.5) }
        return hovered || selected || pressed ? palette.fg : palette.ink
    }

    private var edge: Color {
        guard outlined else { return .clear }
        if selected { return palette.fg }
        return hovered ? palette.lineHover : palette.line
    }

    private var background: Color {
        if let fill { return fill }
        if pressed { return palette.pressed }
        if dashed { return .clear }
        return selected ? palette.keyActive : palette.key
    }
}

extension View {
    /// A name on a key (a source, a pin), as given: Outfit light, centred. On one line at
    /// `Metrics.nameSize`, shrinking to .8 before it is cut; on two at `nameSizeTwoLines`, shrinking
    /// to .6 rather than breaking a word that is longer than the key is wide.
    func nameOnKey(lines: Int = 1) -> some View {
        font(lines >= 2 ? Font.nameOnKeyTwoLines : .outfit(Metrics.nameSize))
            .textCase(nil)
            .tracking(0)
            .lineLimit(lines)
            .minimumScaleFactor(lines >= 2 ? 0.6 : 0.8)
            .multilineTextAlignment(.center)
    }
}

/// A name on a key, as given: on one line when it fits there whole, else on two at the smaller size
/// (`nameOnKey`). A source on the Mac ("Nintendo Switch"), a pin there, a source's word on iOS.
struct KeyName: View {
    let name: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(verbatim: name).nameOnKey()
            Text(verbatim: name).nameOnKey(lines: 2)
        }
    }
}

private extension Font {
    #if os(iOS)
    static let nameOnKeyTwoLines = Font.outfit(points: Metrics.nameSizeTwoLines)
    #else
    static let nameOnKeyTwoLines = Font.outfit(Metrics.nameSizeTwoLines)
    #endif
}

/// A section's title in spaced capitals, with an optional note on the right (shown as given).
struct SectionLabel: View {
    private let title: LocalizedStringKey
    private let trailing: String?
    private let accessory: AnyView?
    private let tint: Color?
    @Environment(\.palette) private var palette

    /// `tint`: a colour in place of the label colour.
    init(_ title: LocalizedStringKey, trailing: String? = nil, tint: Color? = nil) {
        self.title = title
        self.trailing = trailing
        self.accessory = nil
        self.tint = tint
    }

    /// A view on the right in place of the note.
    init(_ title: LocalizedStringKey, tint: Color? = nil, @ViewBuilder accessory: () -> some View) {
        self.title = title
        self.trailing = nil
        self.accessory = AnyView(accessory())
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 8)
            if let trailing { Text(verbatim: trailing) }
            if let accessory { accessory }
        }
        .foregroundStyle(tint ?? palette.label)
        .sectionLabelStyle()
        .padding(.bottom, 7)
    }
}

extension View {
    /// 9.5 pt capitals, tracking 1.3, label colour.
    func sectionLabelStyle() -> some View { modifier(SectionLabelStyle()) }
}

private struct SectionLabelStyle: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .font(.manrope(Metrics.labelSize))
            .tracking(Metrics.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(palette.label)
            .lineLimit(1)
    }
}

/// A switch: a capsule (40 × 22 pt on the Mac, 52 × 30 on iOS) with a round thumb. Off: a soft edge
/// and the thumb on the left at .55. On: the edge and the thumb in the `on` colour, the thumb on the
/// right. With `drawsLabel`, the label is drawn on the left of the row and the switch on its right
/// (a sentence the switch answers); without, the label is not drawn (the title is beside it). Either
/// way VoiceOver reads it once, with the state, and a double tap toggles: the accessibility element
/// is the system's own `Toggle`.
struct PaneSwitchStyle: ToggleStyle {
    var drawsLabel = false
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(iOS)
    private static let size = CGSize(width: 52, height: 30)
    private static let thumb: CGFloat = 20
    private static let margin: CGFloat = 4
    #else
    private static let size = CGSize(width: 40, height: 22)
    private static let thumb: CGFloat = 14
    private static let margin: CGFloat = 3
    #endif

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            if drawsLabel {
                configuration.label
                Spacer(minLength: 0)
            }
            switchButton(configuration)
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }

    private func switchButton(_ configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().strokeBorder(on ? palette.on : palette.line, lineWidth: 1)
                Circle()
                    .fill(on ? palette.on : palette.fg.opacity(0.55))
                    .frame(width: Self.thumb, height: Self.thumb)
                    .padding(.horizontal, Self.margin)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            // A finger's least target on iOS.
            .frame(minHeight: Metrics.minTouch)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: on)
        }
        .buttonStyle(.plain)
    }
}

/// A 1 pt separator across the available width.
struct Hairline: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle().fill(palette.divider).frame(height: 1)
    }
}

/// A small boxed value, like the HDR/SDR badge of the header.
struct ValueBadge: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(verbatim: text)
            .font(.manrope(8.5))
            .padding(.horizontal, 3)
            .overlay(RoundedRectangle(cornerRadius: Metrics.smallRadius).strokeBorder(palette.frame, lineWidth: 1))
    }
}

/// The round status dot of the dashboard, in the active colour.
struct OnDot: View {
    let size: CGFloat
    @Environment(\.palette) private var palette

    var body: some View {
        Circle().fill(palette.on).frame(width: size, height: size)
    }
}

/// A small text button in the label colour, full strength while pressed; a finger's height on iOS.
struct TextButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.manrope(10.5))
            .foregroundStyle(configuration.isPressed ? palette.fg : palette.label)
            .opacity(isEnabled ? 1 : 0.35)
            #if os(iOS)
            .frame(minHeight: Metrics.minTouch)
            #endif
            .contentShape(Rectangle())
    }
}

/// One row of a preferences list: its line, what may come under it, a hairline at the bottom.
struct PreferencesRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Hairline().opacity(0.6) }
    }
}

/// Equal columns (one per visible tab) across the window's full width (10 pt in from its edges), a 1 pt underline
/// under the selected tab, a separator under the bar. The popover's tabs, and the preferences' panes;
/// on iOS, More's pages.
struct TabBar<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> LocalizedStringKey
    /// Each tab's accessibility identifier, for the scripted video takes.
    var identifier: (Tab) -> String = { _ in "" }
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button { selection = tab } label: {
                    Text(title(tab))
                        .font(.manrope(9))
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selection == tab ? palette.fg : palette.fg.opacity(0.55))
                        .padding(.top, 9)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                        #if os(iOS)
                        .frame(minHeight: Metrics.minTouch)
                        #endif
                        .overlay(alignment: .bottom) {
                            if selection == tab { Rectangle().fill(palette.fg).frame(height: 1) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier(tab))
            }
        }
        .padding(.horizontal, 10)
        .background(alignment: .bottom) { Hairline() }
    }
}

extension PaneTab {
    var title: LocalizedStringKey {
        switch self {
        case .remote: "Remote"
        case .apps: "Apps"
        case .picture: "Picture"
        case .audio: "Audio"
        case .game: "Game"
        case .hdmi: "HDMI"
        case .stats: "Stats"
        }
    }
}
