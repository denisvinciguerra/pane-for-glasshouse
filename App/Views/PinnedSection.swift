import PaneKit
import SwiftUI

/// Remote's pinned actions, three to a row, and a "+" right of the section's label that opens the
/// editor on a new one; with no pin yet, a dashed "+" tile stands in the row. A pin whose action cannot run here is greyed; a click on it says why and sends nothing. A pin
/// shown as an icon fills its tile with the colour of the icon's edge, the icon at full height in
/// the middle, and draws the tile's edge when that colour blends into the popover; it keeps its
/// title as text until the icon comes, and as its tooltip.
struct PinnedSection: View {
    let model: AppModel
    let session: TVSession
    /// The TV takes no commands now: the pins are off like Remote's other buttons; "+" is not.
    let controlsOff: Bool
    @Environment(\.keyboard) private var keyboard
    @Environment(\.palette) private var palette

    private static let gap: CGFloat = 6

    var body: some View {
        let pinned = model.store.activeID.map(model.actions.pinned(for:)) ?? []
        let iconApps = pinned.filter { $0.shownTile == .icon }.compactMap(\.iconAppID)
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: 3)
        VStack(alignment: .leading, spacing: 0) {
            header(empty: pinned.isEmpty)
            LazyVGrid(columns: columns, spacing: Self.gap) {
                ForEach(pinned) { action in
                    let icon = icon(action)
                    let edge = icon?.edge
                    GHButton(dimmed: session.unavailableReason(action) != nil, fill: edge?.color,
                             outlined: edge.map { $0.blends(into: background) } ?? true,
                             action: { keyboard?.buttonClicked(.action(action.id)) }) {
                        if let icon {
                            Image(nsImage: icon.image)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: Self.iconSize, height: Self.iconSize)
                                .accessibilityLabel(Text(verbatim: action.title))
                        } else {
                            Text(verbatim: action.title)
                                .textCase(.uppercase)
                                .tracking(1)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .help(icon == nil ? "" : action.title)
                    .keyed(.action(action.id), pinned: action)
                    .disabled(controlsOff)
                }
                if pinned.isEmpty {
                    GHButton(dashed: true, action: model.newAction) {
                        Text(verbatim: "+").font(.manrope(16, .light))
                    }
                    .disabled(addDisabled)
                    .accessibilityLabel(Text("New action"))
                }
            }
        }
        // Again for another TV, other pins, or a TV that answers again.
        .task(id: IconRequest(apps: iconApps, session: ObjectIdentifier(session), reachable: session.power != .unreachable)) {
            guard session.power != .unreachable else { return }
            await model.icons.refresh(iconApps) { await session.appIcon($0) }
        }
    }

    /// The tile's height.
    private static let iconSize: CGFloat = 34

    /// A click while keys are being set is for a key, and "+" carries none.
    private var addDisabled: Bool { keyboard?.state.setsKeys == true }

    /// "Pinned", and the "+" on its right once a pin is there (before, the row's tile adds).
    private func header(empty: Bool) -> some View {
        HStack(alignment: .center) {
            Text("Pinned").sectionLabelStyle()
            Spacer(minLength: 8)
            if !empty {
                AddPinButton(action: model.newAction)
                    .disabled(addDisabled)
            }
        }
        .frame(height: 12)
        .padding(.bottom, 7)
    }

    /// The icon of the app the pin launches and its edge, when it is shown as one and the icon came.
    private func icon(_ action: CustomAction) -> (image: NSImage, edge: IconColor?)? {
        guard action.shownTile == .icon, let app = action.iconAppID, let data = model.icons.icon(for: app),
              let image = NSImage(data: data) else { return nil }
        return (image, model.icons.edge(for: app))
    }

    /// The popover's background, which a tile's colour must stand out from.
    private var background: IconColor {
        guard let c = NSColor(palette.bg).usingColorSpace(.sRGB) else { return IconColor(red: 0, green: 0, blue: 0) }
        return IconColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
    }
}

private extension IconColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

/// A light "+" in the label's colour, the foreground's under the pointer or pressed.
private struct AddPinButton: View {
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(verbatim: "+")
                .font(.manrope(16, .light))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(AddPinStyle(hovered: hovered && isEnabled))
        .onHover { hovered = $0 }
        .help(Text("New action"))
        .accessibilityLabel(Text("New action"))
    }
}

private struct AddPinStyle: ButtonStyle {
    let hovered: Bool
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovered || configuration.isPressed ? palette.fg : palette.label)
            .opacity(isEnabled ? 1 : 0.35)
    }
}

private struct IconRequest: Equatable {
    let apps: [String]
    let session: ObjectIdentifier
    let reachable: Bool
}
