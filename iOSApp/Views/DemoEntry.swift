import SwiftUI

/// What says the demo runs, at the left of Remote's top row when no chip is there: the word and
/// what it is. The ways in are « Try without a TV » on the welcome screen and « Try the demo » in
/// the settings.
struct DemoLabel: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Text("Demo")
                .font(.manrope(Metrics.labelSize, .semibold))
                .tracking(Metrics.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(palette.accent)
            Text("A fake TV, offline")
                .font(.manrope(points: 13))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The way out of the demo, in Remote's top row: back to the active TV, or to the welcome screen.
struct DemoExitButton: View {
    let model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        Button { model.endDemo() } label: {
            Text("Exit")
                .font(.manrope(Metrics.labelSize, .semibold))
                .tracking(Metrics.labelTracking)
                .textCase(.uppercase)
                .padding(.horizontal, 8)
                .frame(minWidth: Metrics.minTouch, minHeight: Metrics.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(ExitStyle())
        .accessibilityLabel(Text("Exit the demo"))
        .accessibilityIdentifier("demo.exit")
    }
}

/// The foreground's text, dimmed while pressed.
private struct ExitStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(palette.fg.opacity(configuration.isPressed ? 0.6 : 1))
    }
}
