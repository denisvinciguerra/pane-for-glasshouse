import PaneKit
import SwiftUI

/// The iPad's screen when it is wide (mockups/2026-11-02-ios/ipad-structure.html, option A, the
/// columns swapped): the remote always in view in a column of a phone's width, on the right unless
/// `MobileModel.remoteOnLeft`, and the chosen tab in the other column, under the popover's tab bar.
/// No Remote tab here: while `selectedTab` is Remote, the column shows the first other tab, and
/// `selectedTab` keeps Remote for the phone layout. HDMI and Stats are tabs of their own.
struct WideLayout: View {
    let model: MobileModel
    let session: TVSession
    let openSettings: () -> Void
    let find: (TVConfig) -> Void
    @Environment(\.palette) private var palette

    /// The width from which the window takes two columns, when its size class is regular too.
    /// Above every iPad held upright (a 13" one is about 1032 pt wide), which keeps the phone
    /// layout, as the spec wants; below every iPad on its side (1133 pt for the mini, 1194 for an
    /// 11"). A Split View or a Stage Manager window narrower than this takes the phone layout too.
    static let minWidth: CGFloat = 1100
    /// The remote's column: a phone's width, the B1 remote as the iPhone shows it.
    static let remoteWidth: CGFloat = 380
    /// The settings' widest, their gutters aside: a 13" iPad on its side would stretch the rows
    /// across some 1000 pt. The tab bar and the page keep it, centred in their column.
    static let readableWidth: CGFloat = 640

    var body: some View {
        HStack(spacing: 0) {
            if model.remoteOnLeft {
                remote
                separator
                tabs
            } else {
                tabs
                separator
                remote
            }
        }
    }

    private var remote: some View {
        ScrollView {
            RemoteScreen(model: model, session: session, openSettings: openSettings, find: find)
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.remoteWidth)
        .background(palette.bg)
        .underStatusBar()
    }

    private var separator: some View {
        Rectangle()
            .fill(palette.divider)
            .frame(width: 1)
            .ignoresSafeArea(.container, edges: .bottom)
    }

    private var tabs: some View {
        let app = model.app
        let available = session.availableTabs.filter { $0 != .remote }
        let shown = Self.shownTab(app.selectedTab, among: available)
        return VStack(spacing: 0) {
            TabBar(tabs: available, selection: selection(shown: shown), title: \.mobileTitle)
                .frame(maxWidth: Self.readableWidth + 2 * Metrics.gutter)
            // The scroll view across the whole column, so that its margins scroll the page too.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TabPageContent(tab: shown, model: app, session: session)
                }
                .frame(maxWidth: Self.readableWidth, alignment: .leading)
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 14)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity)
        .background(palette.bg)
        .overlay(alignment: .bottom) { PassingMessage(session: session) }
    }

    /// The tab the column shows: `selected`, or the first one when it is Remote or gone.
    static func shownTab(_ selected: PaneTab, among tabs: [PaneTab]) -> PaneTab {
        tabs.contains(selected) ? selected : tabs.first ?? .picture
    }

    /// The tab bar's choice: it shows `shown`, and a touch sets `selectedTab`. Remote stays in the
    /// model until another tab is touched, so the phone layout opens on it again.
    private func selection(shown: PaneTab) -> Binding<PaneTab> {
        let app = model.app
        return Binding { shown } set: { app.selectedTab = $0 }
    }
}

/// A tab of the wide layout's column, each in its own place so that none takes another's state.
/// No title: the tab bar names it, and Picture's mode, large, opens its page as on the phone.
private struct TabPageContent: View {
    let tab: PaneTab
    let model: AppModel
    let session: TVSession

    var body: some View {
        switch tab {
        case .remote, .picture: SettingsTab(kind: .picture, model: model, session: session)
        case .audio: SettingsTab(kind: .audio, model: model, session: session)
        case .game: SettingsTab(kind: .game, model: model, session: session)
        case .hdmi:
            OutdatedServerNote(model: model, session: session)
            HDMITab(model: model, session: session)
        case .stats:
            OutdatedServerNote(model: model, session: session)
            StatsTab(model: model, session: session)
        }
    }
}
