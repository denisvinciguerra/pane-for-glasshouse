import SwiftUI

/// The bar under the footer when a version is out: the way into Sparkle's window, and a way to put the bar away.
struct UpdateBar: View {
    let updates: Updates
    let version: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Text("Pane \(version) is available")
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Install") { updates.checkNow() }
                .fontWeight(.semibold)
                .foregroundStyle(palette.fg)
            Button("Later") { updates.dismissBar() }
        }
        .buttonStyle(TextButtonStyle())
        .font(.manrope(10))
        .foregroundStyle(palette.label)
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { Hairline() }
    }
}
