import PaneKit
import SwiftUI
import UIKit

/// The iPhone's screen, and the iPad's when it is narrow: five tabs at the bottom (Remote, Picture,
/// Audio, Game when the TV offers it, More with HDMI and Stats), the welcome screen without a TV.
/// Wide enough, the two columns of `WideLayout` instead, chosen by the room the window has (never
/// by the device), again at each rotation, Split View or fold. What must outlive the switch lives
/// in the models (`selectedTab`, `editingAction`, `morePage`) or here, above both layouts.
struct RootView: View {
    let model: MobileModel
    @State private var keyboard: KeyboardController
    @State private var hardware = HardwareKeyboard()
    @State private var showsSettings = false
    /// Raised as a sheet closes: the iPad's keyboard goes back to the remote.
    @State private var keyClaims = 0
    /// The TV whose new address is being looked for.
    @State private var finding: TVConfig?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    private static let isPad = UIDevice.current.userInterfaceIdiom == .pad

    init(model: MobileModel) {
        self.model = model
        _keyboard = State(initialValue: KeyboardController(model: model.app, layout: LearnedKeyboardLayout()))
    }

    /// The iPad's keyboard works the remote while Pane is in front and no sheet is over it.
    private var keysActive: Bool {
        scenePhase == .active && !showsSettings && finding == nil && model.app.editingAction == nil
    }

    var body: some View {
        let app = model.app
        let palette = Palette.of(colorScheme)
        VStack(spacing: 0) {
            if let session = app.session {
                // The room inside the safe area, so that a large iPhone on its side stays below
                // the threshold.
                GeometryReader { proxy in
                    if sizeClass == .regular && proxy.size.width > WideLayout.minWidth {
                        WideLayout(model: model, session: session,
                                   openSettings: { showsSettings = true }, find: { finding = $0 })
                    } else {
                        tabs(session)
                    }
                }
            } else {
                welcome
            }
        }
        // A tab the TV can't offer (Game Optimizer missing) goes from the bar; leave it.
        .onChange(of: app.session?.availableTabs) { _, tabs in
            if let tabs, !tabs.contains(app.selectedTab) { app.selectedTab = .remote }
        }
        .onChange(of: app.selectedTab) { _, tab in
            if tab == .hdmi || tab == .stats { model.morePage = tab }
        }
        .sensoryFeedback(Haptics.tap, trigger: app.commandsSent)
        .modifier(PinsFeedback(app: app))
        .font(.manrope(11))
        .foregroundStyle(palette.fg)
        .background(palette.bg)
        .tint(palette.fg)
        .environment(\.palette, palette)
        .environment(\.keyboard, keyboard)
        // Above the switch of layouts: the keys go on working through a rotation.
        .background {
            if Self.isPad { HardwareKeys(keyboard: keyboard, hardware: hardware, active: keysActive, claims: keyClaims) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { hardware.refresh() }
        }
        .sheet(isPresented: $showsSettings, onDismiss: { keyClaims += 1 }) {
            AppSettingsView(model: model, keyboard: keyboard, hardware: hardware)
        }
        .sheet(item: $finding, onDismiss: { keyClaims += 1 }) { tv in TVFinderSheet(model: app, tv: tv) }
        .actionEditor(app) { keyClaims += 1 }
        .preferredColorScheme(app.theme.colorScheme)
    }

    private func tabs(_ session: TVSession) -> some View {
        let available = session.availableTabs
        let more = MoreTab.pages.filter(available.contains)
        return TabView(selection: selection) {
            // Under the tab bar, only as much room as the remote needs to fit the screen.
            TabPage(session: session, bottom: 4) {
                RemoteScreen(model: model, session: session,
                             openSettings: { showsSettings = true }, find: { finding = $0 })
            }
            .tabItem { Label("tab.remote", systemImage: "av.remote") }
            .tag(MobileTab.remote)
            ForEach([SettingsTab.Kind.picture, .audio, .game], id: \.self) { kind in
                if available.contains(kind.tab) {
                    TabPage(session: session) {
                        // Picture's mode, large, is its title.
                        if kind != .picture { PageTitle(kind.tab.mobileTitle) }
                        SettingsTab(kind: kind, model: model.app, session: session)
                            .padding(.top, kind == .picture ? 14 : 0)
                    }
                    .tabItem { Label(kind.tab.mobileTitle, systemImage: kind.systemImage) }
                    .tag(MobileTab(kind.tab))
                }
            }
            if !more.isEmpty {
                TabPage(session: session) {
                    MoreTab(model: model.app, session: session, pages: more)
                }
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(MobileTab.more)
            }
        }
    }

    /// The tab bar's choice, as `selectedTab`: More stands for HDMI and Stats.
    private var selection: Binding<MobileTab> {
        let app = model.app
        return Binding {
            MobileTab(app.selectedTab)
        } set: { tab in
            switch tab {
            case .remote: app.selectedTab = .remote
            case .picture: app.selectedTab = .picture
            case .audio: app.selectedTab = .audio
            case .game: app.selectedTab = .game
            case .more:
                if app.selectedTab != .hdmi && app.selectedTab != .stats {
                    let pages = MoreTab.pages.filter { app.session?.availableTabs.contains($0) ?? true }
                    app.selectedTab = pages.contains(model.morePage) ? model.morePage : pages.first ?? .hdmi
                }
            }
        }
    }

    /// No TV yet: the gear, then the welcome screen with its add screen.
    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    IconButton("gearshape", label: "Settings") { showsSettings = true }
                }
                .padding(.trailing, -10)
                WelcomeView(model: model.app)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .underStatusBar()
    }
}

/// A tap when a pin is added or removed on the same TV; not for another TV's pins, nor for a move,
/// which the pins' grid marks itself as the finger goes.
private struct PinsFeedback: ViewModifier {
    let app: AppModel

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: PinsShown(app)) { old, new in
            old.tv == new.tv && Set(old.ids) != Set(new.ids) ? Haptics.tap : nil
        }
    }
}

/// The active TV's pins, in their order.
private struct PinsShown: Equatable {
    let tv: UUID?
    let ids: [UUID]

    @MainActor init(_ app: AppModel) {
        tv = app.activeID
        ids = app.activeID.map { app.actions.pinned(for: $0).map(\.id) } ?? []
    }
}

/// The tab bar's tabs.
private enum MobileTab: Hashable {
    case remote, picture, audio, game, more

    init(_ tab: PaneTab) {
        switch tab {
        case .remote: self = .remote
        case .picture: self = .picture
        case .audio: self = .audio
        case .game: self = .game
        case .hdmi, .stats: self = .more
        }
    }
}

/// A tab's page: its content scrolling under the screen's top (only when it does not fit), and the
/// session's passing message above the tab bar.
private struct TabPage<Content: View>: View {
    let session: TVSession
    /// The room under the content.
    var bottom: CGFloat = 28
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, bottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(palette.bg)
        .underStatusBar()
        .overlay(alignment: .bottom) { PassingMessage(session: session) }
    }
}

extension View {
    /// The screen's background behind the status bar, which the content scrolls under.
    func underStatusBar() -> some View { modifier(UnderStatusBar()) }
}

private struct UnderStatusBar: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            // No height of its own: the background reaches into the status bar's area only.
            Color.clear.frame(height: 0).background(palette.bg)
        }
    }
}

/// A tab's title, large and light, like Picture's mode.
struct PageTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.manrope(points: 32, .light))
            .frame(height: 56, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The session's passing message, a few seconds above the tab bar, in a thin frame.
struct PassingMessage: View {
    let session: TVSession
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if let message = session.transientMessage {
                Text(verbatim: message)
                    .font(.manrope(points: 13))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(palette.key == .clear ? palette.bg : palette.key)
                    .overlay(Rectangle().strokeBorder(palette.line, lineWidth: 1))
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.transientMessage)
    }
}

/// A 44 pt icon in the foreground's colour, dimmed while pressed: the gear.
struct IconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    init(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .light))
                .frame(width: Metrics.minTouch, height: Metrics.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

struct IconButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.fg.opacity(configuration.isPressed ? 0.6 : 1))
            .opacity(isEnabled ? 1 : 0.35)
    }
}

extension PaneTab {
    /// The tab bar's name: the mockup's, longer than the Mac's in French.
    var mobileTitle: LocalizedStringKey {
        switch self {
        case .remote: "tab.remote"
        case .audio: "tab.audio"
        default: title
        }
    }
}

extension SettingsTab.Kind {
    var systemImage: String {
        switch self {
        case .picture: "circle.lefthalf.filled"
        case .audio: "speaker.wave.2"
        case .game: "gamecontroller"
        }
    }
}

/// The bars UIKit draws (the tab bar, the sheets' navigation bars) in the palette and in Manrope,
/// for both themes: their colours resolve with the theme in force. From iOS 26 the tab bar is the
/// system's floating glass, as the mockup draws it, and the navigation bars keep their own glass
/// with Pane's title.
enum BarAppearance {
    @MainActor static func apply() {
        let bg = dynamic(Palette.dark.bg, Palette.light.bg)
        let fg = dynamic(Palette.dark.fg, Palette.light.fg)
        let label = dynamic(Palette.dark.label, Palette.light.label)
        let divider = dynamic(Palette.dark.divider, Palette.light.divider)

        if #available(iOS 26, *) {
            let bar = UINavigationBarAppearance()
            bar.configureWithTransparentBackground()
            bar.titleTextAttributes = [.foregroundColor: fg, .font: font(16, .semibold)]
            UINavigationBar.appearance().standardAppearance = bar
            UINavigationBar.appearance().scrollEdgeAppearance = bar
            UINavigationBar.appearance().compactAppearance = bar
            return
        }

        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = bg
        tabs.shadowColor = divider
        let titleFont = font(10, .medium)
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = label
            item.normal.titleTextAttributes = [.foregroundColor: label, .font: titleFont]
            item.selected.iconColor = fg
            item.selected.titleTextAttributes = [.foregroundColor: fg, .font: titleFont]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs

        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = bg
        bar.shadowColor = divider
        bar.titleTextAttributes = [.foregroundColor: fg, .font: font(16, .semibold)]
        let buttons = UIBarButtonItemAppearance()
        buttons.normal.titleTextAttributes = [.foregroundColor: fg, .font: font(16, .medium)]
        bar.buttonAppearance = buttons
        bar.doneButtonAppearance = buttons
        bar.backButtonAppearance = buttons
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
    }

    private static func dynamic(_ dark: Color, _ light: Color) -> UIColor {
        let dark = UIColor(dark)
        let light = UIColor(light)
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    /// Manrope at a weight of its variable axis, as `Font.manrope` takes it.
    private static func font(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "Manrope",
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}
