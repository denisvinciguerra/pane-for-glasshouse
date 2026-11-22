import PaneKit
import SwiftUI

/// Stats: the System readouts of the web dashboard. A gauge per readout (label and detail, a 3 pt
/// rail with round ends, the value in large thin Outfit), then the facts as key/value pairs, their
/// values in Outfit. A missing field is not drawn. The session already reads the stats every 2 s
/// while the popover is open.
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
                        Text(verbatim: fact.value.forOutfit).font(Self.factValueFont).multilineTextAlignment(.trailing)
                    }
                    #if os(iOS)
                    .font(.manrope(points: 14))
                    .padding(.vertical, 12)
                    #else
                    .font(.manrope(11))
                    .padding(.vertical, 6)
                    #endif
                    Hairline().opacity(0.6)
                }
            }
        }
    }

    private func gaugeRow(_ gauge: Readout) -> some View {
        #if os(iOS)
        phoneGaugeRow(gauge)
        #else
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
            rail(gauge.fraction, width: 90)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: gauge.value.forOutfit).font(.outfit(24, .thin)).monospacedDigit()
                Text(verbatim: gauge.unit).font(.manrope(10)).foregroundStyle(palette.label)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 54, alignment: .trailing)
        }
        .padding(.vertical, 10)
        #endif
    }

    #if os(iOS)
    /// For a finger: the label and the value on one line, the bar across the row under them.
    private func phoneGaugeRow(_ gauge: Readout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: gauge.label).font(.manrope(points: 15.5))
                    if !gauge.detail.isEmpty {
                        Text(verbatim: gauge.detail)
                            .font(.manrope(points: 12))
                            .foregroundStyle(palette.label)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: gauge.value.forOutfit).font(.outfit(points: 32, .thin)).monospacedDigit()
                    Text(verbatim: gauge.unit).font(.manrope(points: 12)).foregroundStyle(palette.label)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            GeometryReader { proxy in rail(gauge.fraction, width: proxy.size.width) }
                .frame(height: Self.railHeight)
        }
        .padding(.vertical, 14)
    }
    #endif

    /// A gauge's rail: 3 pt with round ends (Glasshouse's `oc-track`), filled in `on` up to `fraction`.
    private func rail(_ fraction: Double?, width: CGFloat) -> some View {
        Capsule().fill(palette.fg.opacity(0.15))
            .frame(width: width, height: Self.railHeight)
            .overlay(alignment: .leading) {
                if let fraction {
                    Capsule().fill(palette.on).frame(width: width * fraction)
                }
            }
    }

    private static let railHeight: CGFloat = 3

    #if os(iOS)
    private static let factValueFont = Font.outfit(points: 17)
    #else
    private static let factValueFont = Font.outfit(13)
    #endif
}
