import PaneKit
import SwiftUI

/// A dashboard button: square, a 1 pt edge, 10 pt capitals. Selected: full-strength edge, a faint
/// fill and a 5 pt `on` dot before the title. Dimmed: greyed like a disabled one, still clickable.
/// Dashed: a dashed edge and a faint face (the "+" that adds). Filled: a solid colour under the
/// face, its edge drawn only when `outlined`, darker while pressed.
struct GHButton: View {
    private let title: LocalizedStringKey?
    private let systemImage: String?
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

    /// A button whose face is a drawn shape (the d-pad's triangles) instead of a title.
    init<Face: View>(selected: Bool = false, dimmed: Bool = false, dashed: Bool = false, height: CGFloat = Metrics.buttonHeight,
                     fill: Color? = nil, outlined: Bool = true, action: @escaping () -> Void, @ViewBuilder face: () -> Face) {
        self.title = nil
        self.systemImage = nil
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

    init(_ title: LocalizedStringKey?, systemImage: String? = nil, selected: Bool = false, dimmed: Bool = false,
         dashed: Bool = false, height: CGFloat = Metrics.buttonHeight, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
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
                if let systemImage { Image(systemName: systemImage).font(.system(size: 15 * Metrics.fontScale)) }
                if let title {
                    Text(title).textCase(.uppercase).tracking(Metrics.fontScale).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .font(.manrope(10))
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .contentShape(Rectangle())
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
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(dashed ? palette.fg.opacity(0.5) : palette.fg)
            .background(background(pressed: configuration.isPressed))
            .brightness(fill != nil && configuration.isPressed ? -0.15 : 0)
            .overlay(Rectangle().strokeBorder(outlined ? selected ? palette.fg : palette.line : .clear,
                                              style: StrokeStyle(lineWidth: selected ? palette.activeLineWidth : 1,
                                                                 dash: dashed ? [3, 2] : [])))
            // Greyed as one: an icon over its fill would otherwise show through brighter than the fill.
            .compositingGroup()
            .opacity(isEnabled && !dimmed ? 1 : 0.35)
            #if os(iOS)
            .onChange(of: configuration.isPressed) { _, pressed in pressChange?(pressed) }
            #endif
    }

    private func background(pressed: Bool) -> Color {
        if let fill { return fill }
        if pressed { return palette.fg.opacity(0.16) }
        if dashed { return .clear }
        return selected ? palette.keyActive : palette.key
    }
}

/// A section's title in spaced capitals, with an optional note on the right (shown as given).
struct SectionLabel: View {
    private let title: LocalizedStringKey
    private let trailing: String?
    private let tint: Color?
    @Environment(\.palette) private var palette

    /// `tint`: a colour in place of the label colour.
    init(_ title: LocalizedStringKey, trailing: String? = nil, tint: Color? = nil) {
        self.title = title
        self.trailing = trailing
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 8)
            if let trailing { Text(verbatim: trailing) }
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
            .overlay(Rectangle().strokeBorder(palette.line, lineWidth: 1))
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
        case .picture: "Picture"
        case .audio: "Audio"
        case .game: "Game"
        case .hdmi: "HDMI"
        case .stats: "Stats"
        }
    }
}
