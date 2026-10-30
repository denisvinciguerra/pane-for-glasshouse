import AppKit
import SwiftUI

/// Shown where macOS refuses Pane the local network: an amber panel with what happens, where to
/// allow it, and one button to that setting. Pane reads again by itself once access is back.
struct LocalNetworkBlockedView: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Local network blocked")
                .sectionLabelStyle()
                .foregroundStyle(palette.accent)
                .padding(.bottom, 6)
            Text("Pane can’t reach your TV")
                .font(.manrope(14))
                .foregroundStyle(palette.fg)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
            Text("macOS denies Pane local network access. Allow it in System Settings › Privacy & Security › Local Network; it picks up again on its own.")
                .font(.manrope(10.5))
                .foregroundStyle(palette.label)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Open Local Network Settings")
                    .font(.manrope(10, .semibold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AmberButtonStyle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.accent.opacity(0.08))
        .overlay(Rectangle().strokeBorder(palette.accent.opacity(0.3), lineWidth: 1))
    }
}

private struct AmberButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.accent)
            .background(palette.accent.opacity(configuration.isPressed ? 0.12 : 0))
            .overlay(Rectangle().strokeBorder(palette.accent, lineWidth: 1))
    }
}
