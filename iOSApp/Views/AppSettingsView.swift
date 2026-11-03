import PaneKit
import SwiftUI
import UIKit

/// The app's settings, in a sheet: the TVs, the theme, the iPad's column order and keyboard
/// (its profile and keys), panel maintenance, and about. The Mac's preferences, minus what iOS does itself
/// (language, opening at login, updates) and the global shortcuts it has not.
struct AppSettingsView: View {
    let model: MobileModel
    let keyboard: KeyboardController
    let hardware: HardwareKeyboard
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        let palette = Palette.of(colorScheme)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    TVListView(model: model.app)
                    DemoSection(model: model.app) { dismiss() }
                    ThemeSection(model: model.app)
                    if isPad {
                        RemoteSideSection(model: model)
                        // Its keys only with a keyboard to press them.
                        if hardware.connected { KeyboardSection(model: model.app, keyboard: keyboard) }
                    }
                    MaintenanceSection(model: model.app)
                    AboutSection()
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(palette.bg)
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.manrope(13, .semibold))
                }
            }
        }
        .font(.manrope(11))
        .foregroundStyle(palette.fg)
        .tint(palette.fg)
        .environment(\.palette, palette)
        .environment(\.appModel, model.app)
        .presentationBackground(palette.bg)
        // A sheet is its own presentation: it takes the theme again.
        .preferredColorScheme(model.app.theme.colorScheme)
    }
}

// MARK: Sections

/// The demo, saved TVs or not: its fake TV takes the active one's place until Exit.
private struct DemoSection: View {
    let model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Demo")
            if model.isDemo {
                GHButton("Exit the demo") { model.endDemo() }
            } else {
                SettingsNote("A fake TV, offline, to try Pane without touching yours.").padding(.bottom, 10)
                GHButton("Try the demo") {
                    model.startDemo()
                    close()
                }
            }
        }
    }
}

private struct ThemeSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Theme")
            HStack(spacing: 6) {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    GHButton(mode.title, selected: model.theme == mode) { model.theme = mode }
                }
            }
        }
    }
}

/// iPad only: which column the remote takes when the window is wide.
private struct RemoteSideSection: View {
    let model: MobileModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Remote column")
            HStack(spacing: 6) {
                GHButton("remoteSide.left", selected: model.remoteOnLeft) { model.remoteOnLeft = true }
                GHButton("remoteSide.right", selected: !model.remoteOnLeft) { model.remoteOnLeft = false }
            }
            SettingsNote("When the iPad is wide enough for two columns.").padding(.top, 8)
        }
    }
}

/// iPad only, a keyboard attached: its profile, and its keys, which work the remote while Pane is
/// in front.
private struct KeyboardSection: View {
    let model: AppModel
    let keyboard: KeyboardController
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Keyboard")
            HStack(spacing: 6) {
                ForEach(KeyProfile.allCases, id: \.self) { profile in
                    GHButton(profile.title, selected: model.keymap.choice == .profile(profile)) {
                        model.keymap.choose(.profile(profile))
                    }
                }
                GHButton("Custom", selected: model.keymap.choice == .custom) {
                    model.keymap.choose(.custom)
                }
                .disabled(model.keymap.custom == nil)
            }
            if model.keymap.choice == .custom, let base = model.keymap.custom?.base {
                Text("Based on \(base.name)")
                    .font(.manrope(10.5))
                    .foregroundStyle(palette.label)
                    .padding(.top, 8)
            }
            SettingsNote("With a keyboard attached, its keys work the remote while Pane is in front.")
                .padding(.top, 8)
            KeysList(model: model, keyboard: keyboard)
                .padding(.top, 18)
        }
    }
}

private struct MaintenanceSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Panel maintenance")
            SettingsNote("Turn on the TV even during panel maintenance").padding(.bottom, 8)
            HStack(spacing: 6) {
                GHButton("maintenance.on", selected: model.powersOnDuringMaintenance) { model.powersOnDuringMaintenance = true }
                GHButton("maintenance.off", selected: !model.powersOnDuringMaintenance) { model.powersOnDuringMaintenance = false }
            }
            SettingsNote("Triggering an action then interrupts the maintenance.").padding(.top, 8)
        }
    }
}

/// The app, its version, its links and the projects it owes.
private struct AboutSection: View {
    @Environment(\.palette) private var palette

    private static let website = URL(string: "https://synlink.fr/pane")!
    private static let source = URL(string: "https://github.com/denisvinciguerra/pane-for-glasshouse")!
    private static let license = URL(string: "https://github.com/denisvinciguerra/pane-for-glasshouse/blob/main/LICENSE")!
    private static let glasshouse = URL(string: "https://github.com/rorygallagher2024/glasshouse")!
    private static let manrope = URL(string: "https://github.com/googlefonts/manrope")!

    var body: some View {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("About")
            Text(verbatim: "Pane for Glasshouse").font(.manrope(16, .bold))
            Text("Version \(short) (\(build))")
                .font(.manrope(10.5))
                .foregroundStyle(palette.label)
                .padding(.top, 3)
            Text("A remote for your Glasshouse TV.")
                .font(.manrope(11))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            HStack(spacing: 6) {
                GHButton("Website ↗") { openExternal(Self.website) }
                GHButton("Source ↗") { openExternal(Self.source) }
                GHButton("License ↗") { openExternal(Self.license) }
            }
            .padding(.top, 14)
            SectionLabel("Thanks").padding(.top, 22)
            SettingsNote("Pane talks to Glasshouse and borrows the look of its dashboard.")
            VStack(alignment: .leading, spacing: 0) {
                credit("Glasshouse", by: "by Rory Gallagher", license: "MIT", url: Self.glasshouse)
                credit("Manrope", by: "by Mikhail Sharanda", license: "OFL", url: Self.manrope)
            }
            .padding(.top, 6)
            Text(verbatim: "© 2026 Denis Vinciguerra")
                .font(.manrope(10))
                .foregroundStyle(palette.label)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
        }
    }

    /// A credited project: its name, its author, and its license; the line opens its page.
    private func credit(_ name: String, by author: LocalizedStringKey, license: String, url: URL) -> some View {
        Button { openExternal(url) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: name).foregroundStyle(palette.fg)
                Text(author)
                Spacer(minLength: 0)
                Text(verbatim: "\(license) ↗")
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(TextButtonStyle())
    }
}

// MARK: Pieces

/// A line of secondary text under a section's title or its buttons.
struct SettingsNote: View {
    let text: LocalizedStringKey
    @Environment(\.palette) private var palette

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.manrope(10.5))
            .foregroundStyle(palette.label)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension KeyProfile {
    var title: LocalizedStringKey {
        switch self {
        case .arrows: "Arrows"
        case .gaming: "Gaming"
        }
    }

    var name: String {
        switch self {
        case .arrows: String(localized: "Arrows")
        case .gaming: String(localized: "Gaming")
        }
    }
}
