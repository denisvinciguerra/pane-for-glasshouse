import PaneKit
import SwiftUI

/// HDMI: the ports (name, device seen, signal of the active one), the receiver on the eARC port,
/// and the HDMI and device settings. Texts come from the server and are shown as given.
struct HDMITab: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CappedScroll { content }
            if model.client?.dashboardURL(tab: "audio") != nil {
                Button("Audio formats ↗") { model.openDashboard(tab: "audio") }
                    .buttonStyle(AllSettingsStyle())
                    .padding(.top, 10)
            }
        }
        .refreshing(.hdmi, model: model, session: session)
    }

    @ViewBuilder private var content: some View {
        if let hdmi = session.hdmi {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Ports")
                    ForEach(hdmi.ports) { port in
                        portRow(port)
                        Hairline().opacity(0.6)
                    }
                }
                if let receiver = hdmi.receiver {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("Audio receiver")
                        Text(verbatim: receiver)
                            .font(.manrope(11.5))
                            .padding(.vertical, 3)
                    }
                }
                if !hdmi.settings.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("Settings")
                        ForEach(hdmi.settings) { row in
                            SettingRowView(row: row) { value in
                                Task { await session.send(.lgSetting(id: row.id, value)) }
                            } onPin: {
                                model.pin(row: row)
                            }
                            Hairline().opacity(0.6)
                        }
                    }
                    .disabled(!session.canControl)
                }
            }
        }
    }

    private func portRow(_ port: HDMIPort) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                // The dot's slot keeps the names aligned when no port is active.
                ZStack { if port.isActive { OnDot(size: 6) } }.frame(width: 6)
                Text(verbatim: port.name).font(.manrope(11.5))
                if port.isARC { ValueBadge(text: "ARC") }
                Spacer(minLength: 8)
                if !port.deviceSeen {
                    Text("no device").font(.manrope(10)).foregroundStyle(palette.label)
                }
            }
            if port.isActive {
                let line = ([port.signal].compactMap { $0 } + port.flags).joined(separator: " · ")
                if !line.isEmpty {
                    Text(verbatim: line)
                        .font(.manrope(9.5))
                        .foregroundStyle(palette.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 13)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
