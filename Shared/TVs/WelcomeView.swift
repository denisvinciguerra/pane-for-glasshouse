import SwiftUI

/// The popover without a TV: what Pane needs, a link to the install guide (on iOS, then the demo),
/// then the add screen.
struct WelcomeView: View {
    let model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Welcome")
            Text(headline)
                .font(.manrope(19, .light))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            Text(explanation)
                .font(.manrope(10.5))
                .foregroundStyle(palette.label)
                .fixedSize(horizontal: false, vertical: true)
            Button("Install guide ↗") {
                if let url = URL(string: "https://rorygallagher2024.github.io/glasshouse/install/") {
                    openExternal(url)
                }
            }
            .buttonStyle(TextButtonStyle())
            .padding(.top, 8)
            #if os(iOS)
            // For App Review and for a look before installing Glasshouse: a fake TV, offline.
            GHButton("Try without a TV") { model.startDemo() }
                .accessibilityIdentifier("welcome.tryDemo")
                .padding(.top, 14)
            #endif
            Hairline().padding(.vertical, 16)
            AddTVView(model: model)
        }
    }

    #if os(macOS)
    private var headline: LocalizedStringKey { "Pane needs Glasshouse on a rooted LG TV." }
    private var explanation: LocalizedStringKey {
        "Glasshouse is a server for rooted LG webOS TVs. Install it first, then find your TV here."
    }
    #else
    private var headline: LocalizedStringKey { "Pane needs a TV with Glasshouse." }
    private var explanation: LocalizedStringKey {
        "Glasshouse is a server for LG webOS TVs. Install it on your TV first, then find your TV here."
    }
    #endif
}
