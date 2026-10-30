import AppKit
import SwiftUI

/// Preferences › About: the app, its version, its links and the projects it owes.
struct AboutPane: View {
    @Environment(\.palette) private var palette

    private static let website = URL(string: "https://synlink.fr/pane")!
    private static let source = URL(string: "https://github.com/denisvinciguerra/pane-for-glasshouse")!
    private static let license = URL(string: "https://github.com/denisvinciguerra/pane-for-glasshouse/blob/main/LICENSE")!
    private static let glasshouse = URL(string: "https://github.com/rorygallagher2024/glasshouse")!
    private static let manrope = URL(string: "https://github.com/googlefonts/manrope")!
    private static let sparkle = URL(string: "https://sparkle-project.org")!

    var body: some View {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        PreferencesScroll {
            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text(verbatim: "Pane for Glasshouse")
                    .font(.manrope(16, .bold))
                    .padding(.top, 10)
                Text("Version \(short) (\(build))")
                    .font(.manrope(10.5))
                    .foregroundStyle(palette.label)
                    .padding(.top, 3)
                Text("A remote for your Glasshouse TV, in the menu bar.")
                    .font(.manrope(11))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                GHButton("Website ↗", height: 30) { NSWorkspace.shared.open(Self.website) }
                GHButton("Source ↗", height: 30) { NSWorkspace.shared.open(Self.source) }
                GHButton("License ↗", height: 30) { NSWorkspace.shared.open(Self.license) }
            }
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Thanks")
                Text("Pane talks to Glasshouse and borrows the look of its dashboard.")
                    .font(.manrope(10.5))
                    .foregroundStyle(palette.label)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    credit("Glasshouse", by: "by Rory Gallagher", license: "MIT", url: Self.glasshouse)
                    credit("Manrope", by: "by Mikhail Sharanda", license: "OFL", url: Self.manrope)
                    credit("Sparkle", by: "by the Sparkle Project", license: "MIT", url: Self.sparkle)
                }
                .padding(.top, 10)
            }
            Text(verbatim: "© 2026 Denis Vinciguerra")
                .font(.manrope(10))
                .foregroundStyle(palette.label)
                .frame(maxWidth: .infinity)
        }
    }

    /// A credited project: its name, its author, and its license; the line opens its page.
    private func credit(_ name: String, by author: LocalizedStringKey, license: String, url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: name).foregroundStyle(palette.fg)
                Text(author)
                Spacer(minLength: 0)
                Text(verbatim: "\(license) ↗")
            }
        }
        .buttonStyle(TextButtonStyle())
    }
}
