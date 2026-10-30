import PaneKit
import SwiftUI

/// Power on the left, the keyboard icon between, the web dashboard on the right (a click opens
/// it, the chevron's menu opens one of its tabs), then the preferences' ⚙ at the edge, away from
/// the keyboard. Power sends nothing while keys are being set. In French the row is tight (≈95 pt
/// « ALIMENTATION », ≈134 pt « TABLEAU DE BORD ↗ » with its chevron, in 292 pt): hence the 6 pt
/// gaps and an icon without its name.
struct FooterView: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.keyboard) private var keyboard

    var body: some View {
        HStack(spacing: 0) {
            Button {
                Task { await session.togglePower() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "power").font(.system(size: 9, weight: .medium))
                    Text("Power")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(FooterButtonStyle())
            .disabled(!session.canPower || keyboard?.state.setsKeys == true)
            .fixedSize()
            .layoutPriority(1)
            Spacer(minLength: 6)
            KeyboardIcon()
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                Button("Dashboard ↗") { model.openDashboard(tab: nil) }
                Menu {
                    ForEach(session.webTabs, id: \.id) { tab in
                        Button(tab.label) { model.openDashboard(tab: tab.id) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text("Dashboard tabs"))
            }
            .buttonStyle(FooterButtonStyle())
            // No link when the address cannot form one.
            .disabled(model.client?.dashboardURL(tab: nil) == nil)
            .fixedSize()
            .layoutPriority(1)
            Button { model.openPreferences(nil) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .frame(height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FooterButtonStyle())
            .fixedSize()
            .layoutPriority(1)
            .help(Text("Settings…"))
            .accessibilityLabel(Text("Settings…"))
            .padding(.leading, 8)
        }
        .sectionLabelStyle()
        .padding(.top, 11)
        .overlay(alignment: .top) { Hairline() }
        .padding(.top, 16)
    }
}

/// Shows the keys (click), edits them all (⌥-click). Boxed while they show, amber while they are set.
private struct KeyboardIcon: View {
    @Environment(\.keyboard) private var keyboard
    @Environment(\.palette) private var palette

    var body: some View {
        let state = keyboard?.state
        let color = state?.setsKeys == true ? palette.accent : state?.mode == .showing ? palette.fg : palette.label
        let edge = state?.setsKeys == true ? palette.accent : state?.mode == .showing ? palette.fg.opacity(0.5) : .clear
        Button { keyboard?.iconClicked() } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 11))
                .foregroundStyle(color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(Rectangle().strokeBorder(edge, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Keys"))
        .accessibilityLabel(Text("Keys"))
    }
}

/// Footer links: label text, full strength while pressed.
private struct FooterButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? palette.fg : palette.label)
            .opacity(isEnabled ? 1 : 0.5)
    }
}
