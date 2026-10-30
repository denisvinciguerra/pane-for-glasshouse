import PaneKit
import SwiftUI

/// Stats: the System readouts of the web dashboard. A gauge per readout (label and detail, a 2 pt
/// bar, the value in large light type), then the facts as key/value pairs. A missing field is
/// not drawn. The session already reads the stats every 2 s while the popover is open.
struct StatsTab: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CappedScroll { content }
            if model.client?.dashboardURL(tab: "metrics") != nil {
                Button("Charts ↗") { model.openDashboard(tab: "metrics") }
                    .buttonStyle(AllSettingsStyle())
                    .padding(.top, 10)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let stats = session.stats {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(StatsReadouts.gauges(stats)) { gauge in
                    gaugeRow(gauge)
                    Hairline().opacity(0.6)
                }
                ForEach(StatsReadouts.facts(stats)) { fact in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: fact.label).foregroundStyle(palette.label)
                        Spacer(minLength: 8)
                        Text(verbatim: fact.value).multilineTextAlignment(.trailing)
                    }
                    .font(.manrope(11))
                    .padding(.vertical, 6)
                    Hairline().opacity(0.6)
                }
            }
        }
    }

    private func gaugeRow(_ gauge: Readout) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: gauge.label).font(.manrope(11.5))
                if !gauge.detail.isEmpty {
                    Text(verbatim: gauge.detail)
                        .font(.manrope(10))
                        .foregroundStyle(palette.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(palette.fg.opacity(0.15))
                .frame(width: 90, height: 2)
                .overlay(alignment: .leading) {
                    if let fraction = gauge.fraction {
                        Rectangle().fill(palette.on).frame(width: 90 * fraction)
                    }
                }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: gauge.value).font(.manrope(20, .light))
                Text(verbatim: gauge.unit).font(.manrope(10)).foregroundStyle(palette.label)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 54, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }
}
