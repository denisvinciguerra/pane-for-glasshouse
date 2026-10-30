import PaneKit
import SwiftUI

/// One setting row of the TV: the title (and, when the row is off, why) on the left, the control
/// on the right. Texts come from the server and are shown as given. A row that is not active, or
/// inside a disabled view, is greyed to 35 %. An unsupported row draws nothing. With `onPin`, a
/// "PIN" shows after the title while the pointer is over the row.
struct SettingRowView: View {
    let row: SettingRow
    let onChange: (SettingValue) -> Void
    var onPin: (() -> Void)? = nil
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        if case .unsupported = row.kind {
            EmptyView()
        } else {
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
        }
    }

    @ViewBuilder private var control: some View {
        switch row.kind {
        case .toggle(let on):
            ToggleButton(on: on) { onChange(.bool(!on)) }
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

    var body: some View {
        let shown = visible && isEnabled
        Button(action: action) {
            Text("PIN")
                .font(.manrope(7.5))
                .tracking(0.9)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 3)
                .overlay(Rectangle().strokeBorder(palette.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.fg)
        .opacity(shown ? 0.5 : 0)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
        .accessibilityLabel(Text("Pin to Remote"))
    }
}

/// ON or OFF in a ruled box; the edge and the text are in the active colour when on.
private struct ToggleButton: View {
    let on: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Text(verbatim: on ? "ON" : "OFF")
                .lineLimit(1)
                .tracking(1)
                .font(.manrope(9.5))
                .foregroundStyle(on ? palette.on : palette.fg)
                .frame(width: 44, height: SettingMetrics.controlHeight)
                .overlay(Rectangle().strokeBorder(on ? palette.on : palette.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A menu of the server's choices, in a ruled box with a ▾. With a `title`, the box shows it
/// instead of the current choice (the picture mode's menu, whose current choice is shown large).
struct ChoiceMenu: View {
    let value: String
    let choices: [Choice]
    let title: String?
    let onSelect: (String) -> Void
    @Environment(\.palette) private var palette

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
            HStack(spacing: 6) {
                Text(verbatim: title ?? choices.first { $0.value == value }?.label ?? value)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: "▾").font(.manrope(8))
            }
            .font(.manrope(10.5))
            .foregroundStyle(palette.fg)
            .padding(.horizontal, 8)
            .frame(height: SettingMetrics.controlHeight)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        // The edge is drawn outside the menu: the menu styles replace a label's own chrome.
        .overlay(Rectangle().strokeBorder(palette.line, lineWidth: 1).allowsHitTesting(false))
        .frame(maxWidth: 150, alignment: .trailing)
    }
}

/// A 96 pt slider and its value: a hairline track, the filled part in the foreground, a square
/// thumb. While dragging it shows the dragged value; the setting is sent once, on release,
/// rounded to a whole step. A click on the track jumps there.
private struct NumberSlider: View {
    let row: SettingRow
    let value: Double
    let range: ClosedRange<Double>
    let onRelease: (Double) -> Void
    @State private var dragged: Double?
    @Environment(\.palette) private var palette

    private static let width: CGFloat = 96
    private static let thumb = CGSize(width: 8, height: 12)

    var body: some View {
        let shown = (dragged ?? value).rounded()
        let span = range.upperBound - range.lowerBound
        let travel = Self.width - Self.thumb.width
        let x = span > 0 ? CGFloat((shown - range.lowerBound) / span) * travel : 0
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Rectangle().fill(palette.line).frame(height: 1)
                Rectangle().fill(palette.fg).frame(width: x + Self.thumb.width / 2, height: 1)
                Rectangle().fill(palette.fg).frame(width: Self.thumb.width, height: Self.thumb.height).offset(x: x)
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
                .font(.manrope(11, .light))
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
