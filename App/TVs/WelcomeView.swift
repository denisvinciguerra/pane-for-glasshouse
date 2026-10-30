import AppKit
import SwiftUI

/// The popover without a TV: what Pane needs, a link to the install guide, then the add screen.
struct WelcomeView: View {
    let model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Welcome")
            Text("Pane needs Glasshouse on a rooted LG TV.")
                .font(.manrope(19, .light))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            Text("Glasshouse is a server for rooted LG webOS TVs. Install it first, then find your TV here.")
                .font(.manrope(10.5))
                .foregroundStyle(palette.label)
                .fixedSize(horizontal: false, vertical: true)
            Button("Install guide ↗") {
                if let url = URL(string: "https://rorygallagher2024.github.io/glasshouse/install/") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(TextButtonStyle())
            .padding(.top, 8)
            Hairline().padding(.vertical, 16)
            AddTVView(model: model)
        }
    }
}
