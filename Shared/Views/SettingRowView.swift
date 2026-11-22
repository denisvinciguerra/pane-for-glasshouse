import PaneKit
import SwiftUI

/// One setting row of the TV: the title (and, when the row is off, why) on the left, the control
/// on the right. Texts come from the server and are shown as given. A row that is not active, or
/// inside a disabled view, is greyed to 35 %. An unsupported row draws nothing. With `onPin`, a
/// "PIN" shows after the title while the pointer is over the row. On iOS, rows for a finger
/// (mockups/2026-11-02-ios/iphone-compact.html, Image): a slider takes the row's width under its
/// title, in a 48 pt band; menus and switches stand in 64 pt rows.
struct SettingRowView: View {
    let row: SettingRow
    /// iOS: the TV can't be controlled. The controls go grey and inert, but the ⓘ stays live, which
    /// a `.disabled` on a parent would not allow. The Mac ignores it (its parents disable).
    var locked = false
    let onChange: (SettingValue) -> Void
    var onPin: (() -> Void)? = nil
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        if case .unsupported = row.kind {
            EmptyView()
        } else {
            #if os(iOS)
            phoneRow
            #else
            let dimmed = !row.active || !isEnabled
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    // As tall as the controls, so the title and the control share one centre line.
                    HStack(spacing: 6) {
                        Text(verbatim: row.title)
                            .font(.manrope(11.5))
                            .opacity(dimmed ? 0.35 : 1)
                        if let onPin { PinButton(visible: hovering, action: onPin) }
                    }
                    .frame(minHeight: SettingMetrics.controlHeight, alignment: .leading)
                    if let reason = RowLayout.inactiveReason(row) {
                        Text(verbatim: reason)
                            .font(.manrope(9.5))
                            .foregroundStyle(palette.label)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                control
                    .disabled(!row.active)
                    .opacity(dimmed ? 0.35 : 1)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .help(row.desc ?? "")
            #endif
        }
    }

    @ViewBuilder private var control: some View {
        switch row.kind {
        case .toggle(let on):
            ToggleButton(title: row.title, on: on) { onChange(.bool(!on)) }
        case .choice(let value, let choices):
            ChoiceMenu(value: value, choices: choices, title: nil) { onChange(.string($0)) }
        case .number(let value, let min, let max):
            NumberSlider(row: row, value: value, range: min...max) { onChange(.number($0)) }
        case .unsupported:
            EmptyView()
        }
    }
}

enum SettingMetrics {
    static let controlHeight: CGFloat = 22
}

/// The small "PIN" after a title: pins it to Remote. It keeps its room while hidden, so the title
/// does not move when it shows; it stays hidden while the controls are off.
struct PinButton: View {
    let visible: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.keyShape) private var shape

    var body: some View {
        let shown = visible && isEnabled
        Button(action: action) {
            Text("PIN")
                .font(.manrope(7.5))
                .tracking(0.9)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 3)
                .overlay(shape.strokeInside(palette.line, style: StrokeStyle(lineWidth: 1)))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.fg)
        .opacity(shown ? 0.5 : 0)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
        .accessibilityLabel(Text("Pin to Remote"))
    }
}

/// A row's on/off: a `PaneSwitchStyle` switch. The title is beside it, so the `Toggle`'s own label
/// is only for VoiceOver. A change sends the opposite of what the TV last said (the switch follows
/// the TV's state, not its own).
private struct ToggleButton: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { on }, set: { _ in action() })) { Text(verbatim: title) }
            .toggleStyle(PaneSwitchStyle())
    }
}

/// A menu of the server's choices, in a box of the key's shape with a chevron. With a `title`, the box shows it
/// instead of the current choice (the picture mode's menu, whose current choice is shown large).
struct ChoiceMenu: View {
    let value: String
    let choices: [Choice]
    let title: String?
    let onSelect: (String) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.keyShape) private var shape

    var body: some View {
        Menu {
            ForEach(choices, id: \.value) { choice in
                Button { onSelect(choice.value) } label: {
                    if choice.value == value {
                        Label { Text(verbatim: choice.label) } icon: { Image(systemName: "checkmark") }
                    } else {
                        Text(verbatim: choice.label)
                    }
                }
            }
        } label: {
            #if os(iOS)
            HStack(spacing: 8) {
                Text(verbatim: title ?? choices.first { $0.value == value }?.label ?? value)
                    .lineLimit(1)
                    .truncationMode(.tail)
                KeyIconView(.down, size: 12)
            }
            .font(.outfit(points: 16))
            .foregroundStyle(palette.fg)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(palette.key, in: shape)
            .contentShape(shape)
            #else
            HStack(spacing: 6) {
                Text(verbatim: title ?? choices.first { $0.value == value }?.label ?? value)
                    .lineLimit(1)
                    .truncationMode(.tail)
                KeyIconView(.down, size: 10)
            }
            .font(.outfit(12.5))
            .foregroundStyle(palette.fg)
            .padding(.horizontal, 8)
            .frame(height: SettingMetrics.controlHeight)
            .contentShape(shape)
            #endif
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        // The edge is drawn outside the menu: the menu styles replace a label's own chrome.
        .overlay(shape.strokeInside(palette.line, style: StrokeStyle(lineWidth: 1)).allowsHitTesting(false))
        #if os(iOS)
        .frame(maxWidth: 210, alignment: .trailing)
        #else
        .frame(maxWidth: 150, alignment: .trailing)
        #endif
    }
}

/// A 96 pt slider and its value: a 2 pt rail, the filled part in the foreground, a round thumb.
/// While dragging it shows the dragged value; the setting is sent once, on release, rounded to a
/// whole step. A click on the track jumps there.
private struct NumberSlider: View {
    let row: SettingRow
    let value: Double
    let range: ClosedRange<Double>
    let onRelease: (Double) -> Void
    @State private var dragged: Double?
    @Environment(\.palette) private var palette

    private static let width: CGFloat = 96
    private static let thumb = CGSize(width: 14, height: 14)

    var body: some View {
        let shown = (dragged ?? value).rounded()
        let span = range.upperBound - range.lowerBound
        let travel = Self.width - Self.thumb.width
        let x = span > 0 ? CGFloat((shown - range.lowerBound) / span) * travel : 0
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(palette.fg.opacity(0.30)).frame(height: 2)
                Capsule().fill(palette.fg).frame(width: x + Self.thumb.width / 2, height: 2)
                Circle().fill(palette.fg).frame(width: Self.thumb.width, height: Self.thumb.height).offset(x: x)
            }
            .frame(width: Self.width, height: SettingMetrics.controlHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragged = position($0.location.x, travel: travel, span: span) }
                    .onEnded { drag in
                        let final = position(drag.location.x, travel: travel, span: span)
                        dragged = nil
                        onRelease(final)
                    }
            )
            Text(verbatim: RowLayout.valueText(row, value: shown))
                .font(.outfit(11, .light))
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
        .frame(height: SettingMetrics.controlHeight)
    }

    /// The whole value under a touch at `x`, the thumb's centre following it, within the range.
    private func position(_ x: CGFloat, travel: CGFloat, span: Double) -> Double {
        guard travel > 0 else { return range.lowerBound }
        let fraction = min(max(Double((x - Self.thumb.width / 2) / travel), 0), 1)
        return (range.lowerBound + fraction * span).rounded()
    }
}

#if os(iOS)
extension SettingRowView {
    /// A slider row: the title and the value, then the slider across, 97 pt in all. Any other: the
    /// title on the left, the 44 pt control on the right, in 64 pt. A long press on the title (not on
    /// the control, which a held finger may be about to move) offers to pin the row, as PIN does on
    /// the Mac.
    @ViewBuilder fileprivate var phoneRow: some View {
        let dimmed = !row.active || !isEnabled || locked
        let pin = isEnabled && !locked ? onPin : nil
        switch row.kind {
        case .number(let value, let min, let max):
            WideSlider(row: row, value: value, range: min...max, dimmed: dimmed,
                       inert: !row.active || locked, onPin: pin) { onChange(.number($0)) }
                .padding(.top, 14)
                .padding(.bottom, 8)
        default:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.title)
                        .font(.manrope(points: 15.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(dimmed ? 0.35 : 1)
                    if let reason = RowLayout.inactiveReason(row) {
                        Text(verbatim: reason)
                            .font(.manrope(points: 12))
                            .foregroundStyle(palette.label)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pinMenu(pin)
                control
                    .disabled(!row.active || locked)
                    .opacity(dimmed ? 0.35 : 1)
                    .accessibilityIdentifier("setting.\(row.id)")
                if let desc = row.desc, !desc.isEmpty {
                    DescInfoButton(text: desc).accessibilityIdentifier("setting.\(row.id).info")
                }
            }
            .padding(.vertical, 10)
            .frame(minHeight: 64)
        }
    }
}

extension View {
    /// A long press offers « Pin to the remote », when `pin` is given.
    @ViewBuilder func pinMenu(_ pin: (() -> Void)?) -> some View {
        if let pin {
            contentShape(.contextMenuPreview, Rectangle())
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Pin to the remote", systemImage: "pin", action: pin)
                }
        } else {
            self
        }
    }
}

/// The touch stand-in for the pointer's tooltip: an ⓘ that opens a setting's description in a
/// popover (kept a popover on iPhone too, so it stays next to the row). The text comes from the
/// server and is shown as given.
struct DescInfoButton: View {
    let text: String
    @State private var shown = false
    @Environment(\.palette) private var palette

    var body: some View {
        Button { shown = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(palette.label)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("About this setting"))
        .popover(isPresented: $shown) {
            ScrollView {
                Text(verbatim: text)
                    .font(.manrope(points: 14))
                    .foregroundStyle(palette.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(minWidth: 240, idealWidth: 300, maxWidth: 320, maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            .background(palette.bg)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// A slider for a finger: the title and the value over a 2 pt rail as wide as the row, the filled
/// part in the foreground (from the middle when the range goes below zero), a 22 pt round thumb
/// (white with a shadow and a fine edge in the light theme), in a 48 pt band. It follows a sideways
/// drag only, so that a drag down the page scrolls it; a touch on the track jumps there. The
/// setting is sent once, on release, rounded to a whole step.
private struct WideSlider: View {
    let row: SettingRow
    let value: Double
    let range: ClosedRange<Double>
    /// Greyed (inactive row or no control): the title, value and track, not the ⓘ.
    let dimmed: Bool
    /// The track ignores touches (inactive row, or no control); the ⓘ does not.
    let inert: Bool
    /// Pins the row, from a long press on its title line.
    let onPin: (() -> Void)?
    let onRelease: (Double) -> Void
    @State private var dragged: Double?
    /// Whether the drag under way is sideways (it sets) or not (it scrolls); nil before it is known.
    @State private var sideways: Bool?
    /// Whether a finger is on the track: falls when the drag ends, or when the system cancels it
    /// (a call, a rotation, the Control Center), which never reaches `onEnded`.
    @GestureState private var touching = false
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    private static let thumb = CGSize(width: 22, height: 22)
    private static let band: CGFloat = 48

    var body: some View {
        let shown = (dragged ?? value).rounded()
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: row.title).font(.manrope(points: 15.5)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: RowLayout.valueText(row, value: shown))
                        .font(.outfit(points: 17, .light))
                        .monospacedDigit()
                }
                .opacity(dimmed ? 0.35 : 1)
                .pinMenu(onPin)
                // Outside the baseline line: the 44 pt button is centred on the 22 pt line and
                // overflows it without growing the row; the track below, drawn after, wins the
                // touches in the overlap.
                if let desc = row.desc, !desc.isEmpty {
                    DescInfoButton(text: desc).frame(height: 22).accessibilityIdentifier("setting.\(row.id).info")
                }
            }
            .frame(height: 22)
            GeometryReader { proxy in
                track(width: proxy.size.width, shown: shown)
            }
            .frame(height: Self.band)
            .disabled(inert)
            .opacity(dimmed ? 0.35 : 1)
        }
    }

    private func track(width: CGFloat, shown: Double) -> some View {
        let span = range.upperBound - range.lowerBound
        let travel = max(width - Self.thumb.width, 0)
        let fraction = span > 0 ? CGFloat((shown - range.lowerBound) / span) : 0
        let x = Self.thumb.width / 2 + fraction * travel
        let signed = range.lowerBound < 0
        let middle = Self.thumb.width / 2 + travel / 2
        let from = signed ? min(x, middle) : 0
        let to = signed ? max(x, middle) : x
        return ZStack(alignment: .topLeading) {
            Capsule().fill(palette.fg.opacity(0.30)).frame(width: width, height: 2).offset(y: Self.band / 2 - 1)
            if signed {
                Rectangle().fill(palette.frame).frame(width: 1, height: 13).offset(x: middle, y: Self.band / 2 - 6)
            }
            Capsule().fill(palette.fg).frame(width: max(to - from, 0), height: 2).offset(x: from, y: Self.band / 2 - 1)
            thumb
                .offset(x: x - Self.thumb.width / 2, y: (Self.band - Self.thumb.height) / 2)
        }
        .frame(width: width, height: Self.band, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { location in onRelease(position(location.x, travel: travel, span: span)) }
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { drag in
                    if sideways == nil { sideways = abs(drag.translation.width) > abs(drag.translation.height) }
                    guard sideways == true else { return }
                    dragged = position(drag.location.x, travel: travel, span: span)
                }
                .onEnded { drag in
                    defer { sideways = nil }
                    guard sideways == true else { return }
                    let final = position(drag.location.x, travel: travel, span: span)
                    dragged = nil
                    onRelease(final)
                }
        )
        // A drag the system cancelled: the value shown goes back to the TV's, nothing is sent.
        // After `onEnded`, which has already done so for a drag that ended.
        .onChange(of: touching) { _, now in
            guard !now else { return }
            Task { @MainActor in
                dragged = nil
                sideways = nil
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: row.title))
        .accessibilityValue(Text(verbatim: RowLayout.valueText(row, value: shown)))
        // VoiceOver: a swipe up or down moves the value one step, within the range.
        .accessibilityAdjustableAction { direction in
            guard !inert, isEnabled else { return }
            let step: Double
            switch direction {
            case .increment: step = 1
            case .decrement: step = -1
            @unknown default: return
            }
            let next = min(max(value.rounded() + step, range.lowerBound), range.upperBound)
            if next != value { onRelease(next) }
        }
    }

    /// The round thumb: the foreground; in the light theme white, with a soft shadow and a 0.5 pt edge.
    @ViewBuilder private var thumb: some View {
        if colorScheme == .light {
            Circle().fill(.white)
                .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.20), radius: 1.5)
                .frame(width: Self.thumb.width, height: Self.thumb.height)
        } else {
            Circle().fill(palette.fg).frame(width: Self.thumb.width, height: Self.thumb.height)
        }
    }

    /// The whole value under a touch at `x`, the thumb's centre following it, within the range.
    private func position(_ x: CGFloat, travel: CGFloat, span: Double) -> Double {
        guard travel > 0 else { return range.lowerBound }
        let fraction = min(max(Double((x - Self.thumb.width / 2) / travel), 0), 1)
        return (range.lowerBound + fraction * span).rounded()
    }
}
#endif
