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

    /// A button whose face is a drawn shape (the d-pad's triangles) instead of a title.
    init<Face: View>(selected: Bool = false, dimmed: Bool = false, dashed: Bool = false, height: CGFloat = 34,
                     fill: Color? = nil, outlined: Bool = true, action: @escaping () -> Void, @ViewBuilder face: () -> Face) {
        self.title = nil
        self.systemImage = nil
        self.selected = selected
        self.dimmed = dimmed
        self.dashed = dashed
        self.height = height
        self.fill = fill
        self.outlined = outlined
        self.shape = AnyView(face())
        self.action = action
    }

    init(_ title: LocalizedStringKey?, systemImage: String? = nil, selected: Bool = false, dimmed: Bool = false,
         dashed: Bool = false, height: CGFloat = 34, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.selected = selected
        self.dimmed = dimmed
        self.dashed = dashed
        self.height = height
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
                if let systemImage { Image(systemName: systemImage).font(.system(size: 15)) }
                if let title {
                    Text(title).textCase(.uppercase).tracking(1).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .font(.manrope(10))
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(GHButtonStyle(selected: selected, dimmed: dimmed, dashed: dashed, fill: fill, outlined: outlined))
    }
}

private struct GHButtonStyle: ButtonStyle {
    let selected: Bool
    let dimmed: Bool
    let dashed: Bool
    let fill: Color?
    let outlined: Bool
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(dashed ? palette.fg.opacity(0.5) : palette.fg)
            .background(background(pressed: configuration.isPressed))
            .brightness(fill != nil && configuration.isPressed ? -0.15 : 0)
            .overlay(Rectangle().strokeBorder(outlined ? selected ? palette.fg : palette.line : .clear,
                                              style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : [])))
            .opacity(isEnabled && !dimmed ? 1 : 0.35)
    }

    private func background(pressed: Bool) -> Color {
        if let fill { return fill }
        if pressed { return palette.fg.opacity(0.16) }
        return selected ? palette.fg.opacity(0.10) : .clear
    }
}

/// A section's title in spaced capitals, with an optional note on the right (shown as given).
struct SectionLabel: View {
    private let title: LocalizedStringKey
    private let trailing: String?
    @Environment(\.palette) private var palette

    init(_ title: LocalizedStringKey, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 8)
            if let trailing { Text(verbatim: trailing) }
        }
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
