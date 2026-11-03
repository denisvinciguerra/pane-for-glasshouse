import PaneKit
import SwiftUI

/// More: HDMI and Stats, chosen at the top with the popover's tab bar, and whether the server is
/// out of date. The page shown is `AppModel.selectedTab`.
struct MoreTab: View {
    let model: AppModel
    let session: TVSession
    /// The pages the TV offers, among `pages`.
    let pages: [PaneTab]

    /// What More holds, in this order.
    static let pages: [PaneTab] = [.hdmi, .stats]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTitle("More")
            OutdatedServerNote(model: model, session: session)
            TabBar(tabs: pages, selection: Bindable(model).selectedTab, title: \.mobileTitle,
                   identifier: { "more.page.\($0.rawValue)" })
                // Across the screen's full width, as across the popover's.
                .padding(.horizontal, -Metrics.gutter)
            Group {
                switch model.selectedTab {
                case .stats: StatsTab(model: model, session: session)
                default: HDMITab(model: model, session: session)
                }
            }
            .padding(.top, 16)
        }
    }
}

/// Whether the server is out of date, and the way to update it: the Mac's status line says it;
/// Remote has no room for it on iOS, so HDMI and Stats do.
struct OutdatedServerNote: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.palette) private var palette

    var body: some View {
        if let version = session.outdatedVersion {
            HStack(spacing: 0) {
                Text(verbatim: String(localized: "Glasshouse \(version) is out of date") + " · ")
                Button("Update ↗") { model.openDashboard(tab: "server") }
                    .buttonStyle(TextButtonStyle())
            }
            .font(.manrope(10.5))
            .foregroundStyle(palette.label)
            .padding(.bottom, 8)
        }
    }
}
