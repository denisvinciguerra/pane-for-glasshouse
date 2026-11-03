import PaneKit
import SwiftUI

/// The popover: the masthead, a status line, the tab bar, the tab, the footer, and under it the
/// bar of the keys while they show, then the bar announcing an update. The action editor, while
/// open, takes the place of the tab bar and the tab. Without a TV, the welcome screen. Its palette
/// follows the popover's appearance, which follows the theme.
struct PopoverRoot: View {
    let model: AppModel
    let keyboard: KeyboardController
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Palette.of(colorScheme)
        let keysBar = model.session != nil && model.editingAction == nil && keyboard.state.keysShown
        let updateBar = model.updates.available != nil && !model.updates.barDismissed
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(.top, 18)
                .padding(.bottom, keysBar || updateBar ? 10 : 14)
            if keysBar { KeysBar(model: model, keyboard: keyboard) }
            if updateBar, let version = model.updates.available { UpdateBar(updates: model.updates, version: version) }
        }
        // A tab the TV can't offer (Game Optimizer missing) goes from the bar; leave it.
        .onChange(of: model.session?.availableTabs) { _, tabs in
            if let tabs, !tabs.contains(model.selectedTab) { model.selectedTab = .remote }
        }
        .frame(width: Metrics.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .overlayPreferenceValue(PinsListAnchor.self) { anchor in
            if keyboard.pinsListOpen, let anchor { pinsList(above: anchor) }
        }
        .font(.manrope(11))
        .foregroundStyle(palette.fg)
        .background(palette.bg)
        .environment(\.palette, palette)
        .environment(\.keyboard, keyboard)
    }

    /// The pins' "+" list over everything, its bottom just above the "+" and its right edge on the
    /// "+"'s; a click beside it closes it.
    private func pinsList(above anchor: Anchor<CGRect>) -> some View {
        GeometryReader { proxy in
            let plus = proxy[anchor]
            let left = min(max(Metrics.gutter, plus.maxX - PinsList.width), proxy.size.width - PinsList.width)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { keyboard.pinsListOpen = false }
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PinsList(model: model, keyboard: keyboard)
                }
                .frame(height: max(0, plus.minY - 4))
                .offset(x: left)
            }
        }
    }

    @ViewBuilder private var content: some View {
        Group {
            if let session = model.session, model.store.active != nil {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        HeaderView(model: model, session: session)
                        StatusLine(model: model, session: session)
                    }
                    .padding(.horizontal, Metrics.gutter)
                    if let draft = model.editingAction {
                        ActionEditorView(model: model, draft: draft) { model.editingAction = nil }
                            .id(draft.id)
                            .padding(.top, 14)
                            .padding(.horizontal, Metrics.gutter)
                    } else if session.localNetworkDenied {
                        LocalNetworkBlockedView()
                            .padding(.vertical, 16)
                            .padding(.horizontal, Metrics.gutter)
                    } else {
                        TabBar(tabs: session.availableTabs, selection: Bindable(model).selectedTab, title: \.title)
                        TabContent(tab: model.selectedTab, model: model, session: session)
                            .padding(.top, 14)
                            .padding(.horizontal, Metrics.gutter)
                    }
                    FooterView(model: model, session: session)
                        .padding(.horizontal, Metrics.gutter)
                }
            } else {
                WelcomeView(model: model)
                    .padding(.horizontal, Metrics.gutter)
            }
        }
    }
}

/// One line under the masthead: the passing message, else why the commands are off (not while the
/// local network block explains it below), else that the server is out of date. It keeps its
/// height when empty, so the window does not jump.
private struct StatusLine: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if let message = session.transientMessage {
                plain(message)
            } else if !session.localNetworkDenied, let reason = session.blockedReason {
                plain(reason)
            } else if let version = session.outdatedVersion {
                HStack(spacing: 0) {
                    Text(verbatim: String(localized: "Glasshouse \(version) is out of date") + " · ")
                    Button("Update ↗") { model.openDashboard(tab: "server") }
                        .buttonStyle(TextButtonStyle())
                }
                .font(.manrope(10))
                .foregroundStyle(palette.label)
                .lineLimit(1)
            } else {
                plain("")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .leading)
    }

    private func plain(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.manrope(10))
            .foregroundStyle(palette.label)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// The selected tab.
private struct TabContent: View {
    let tab: PaneTab
    let model: AppModel
    let session: TVSession

    var body: some View {
        switch tab {
        case .remote: RemoteTab(model: model, session: session)
        case .picture: SettingsTab(kind: .picture, model: model, session: session)
        case .audio: SettingsTab(kind: .audio, model: model, session: session)
        case .game: SettingsTab(kind: .game, model: model, session: session)
        case .hdmi: HDMITab(model: model, session: session)
        case .stats: StatsTab(model: model, session: session)
        }
    }
}
