import PaneKit
import SwiftUI

/// The Remote tab, the whole remote on one screen (mockups/2026-11-02-ios/iphone-compact.html, B1):
/// the TVs as chips with the dashboard and the settings on the right, the header with Power, then
/// the remote. During the demo, the row says so and offers the way out. A TV that is not found gets
/// its way to be found; the local network refused, the explanation takes the remote's place. The
/// phone's tab and the iPad's column both show it.
struct RemoteScreen: View {
    let model: MobileModel
    let session: TVSession
    let openSettings: () -> Void
    /// Looks for the TV's new address, in a sheet that outlives the layout.
    let find: (TVConfig) -> Void

    var body: some View {
        let app = model.app
        let lost = app.lostTV.flatMap { id in app.store.tvs.first { $0.id == id } }
            .flatMap { tv in session.power == .unreachable && !session.localNetworkDenied && !session.stale ? tv : nil }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                if TVChips.shown(for: model) {
                    TVChips(model: model)
                } else if app.isDemo && !DebugLaunch.hideDemoLabel {
                    DemoLabel()
                }
                Spacer(minLength: 8)
                if app.isDemo && !DebugLaunch.hideDemoLabel { DemoExitButton(model: app) }
                DashboardMenu(model: app, session: session)
                IconButton("gearshape", label: "Settings", action: openSettings)
            }
            .padding(.trailing, -10)
            .frame(height: Metrics.minTouch)
            HeaderView(model: app, session: session)
                .padding(.top, 10)
            if let lost {
                NotFoundPanel { find(lost) }
                    .padding(.top, 12)
            }
            if session.localNetworkDenied {
                LocalNetworkBlockedView()
                    .padding(.top, 16)
            } else {
                RemoteTab(model: app, session: session)
                    .padding(.top, 16)
            }
        }
    }
}

/// The web dashboard: a touch shows its tabs, the first entry opens it on its own default.
private struct DashboardMenu: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.palette) private var palette

    var body: some View {
        // No link when the address cannot form one (the demo has none).
        if model.client?.dashboardURL(tab: nil) != nil {
            Menu {
                Button("Dashboard ↗") { model.openDashboard(tab: nil) }
                Section("Dashboard tabs") {
                    ForEach(session.webTabs, id: \.id) { tab in
                        Button(tab.label) { model.openDashboard(tab: tab.id) }
                    }
                }
            } label: {
                Image(systemName: "globe")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(palette.fg)
                    .frame(width: Metrics.minTouch, height: Metrics.minTouch)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Dashboard ↗"))
        }
    }
}

/// The active TV no longer answers and is not found: what may have happened (a TV in deep standby
/// can't be told from a moved one), and the search by hand, where a touch gives the TV the address
/// found. One line and its key, so the remote moves down as little as it can.
private struct NotFoundPanel: View {
    let find: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Text("TV not found: it may be off, or have a new address.")
                .font(.manrope(points: 13))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            GHButton("Find it", action: find)
                .frame(width: 128)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(palette.key)
        .overlay(Rectangle().strokeBorder(palette.line, lineWidth: 1))
    }
}
