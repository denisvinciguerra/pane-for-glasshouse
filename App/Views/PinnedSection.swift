import PaneKit
import SwiftUI

/// Remote's pinned actions, three to a row, and a pencil right of the section's label. While they are
/// edited, each pin has a × that deletes its action and keys, moves by dragging, and opens its
/// editor on a click; a dashed "+" tile ends the row, which opens the editor on a new action, or
/// first the list of the actions without a pin when there are some. With no pin yet, the dashed
/// "+" tile stands in the row. A pin whose action
/// cannot run here is greyed; a click on it says why and sends nothing. While the TV is off, a pin
/// stays clickable when its action can turn it on. A pin shown as an icon fills its tile with the
/// colour of the icon's edge, the icon at full height in the middle, and draws the tile's edge when
/// that colour blends into the popover; it keeps its title as text until the icon comes, and as its
/// tooltip.
struct PinnedSection: View {
    let model: AppModel
    let session: TVSession
    /// The TV takes no commands now and a click would send one: the pins are off like Remote's
    /// other buttons, except those whose action can turn it on; "+" is not.
    let controlsOff: Bool
    @Environment(\.keyboard) private var keyboard
    @Environment(\.palette) private var palette
    /// The pin being dragged, while the pins are edited.
    @State private var dragging: UUID?

    private static let gap: CGFloat = 6

    private var editing: Bool { keyboard?.pinsEditing == true }

    var body: some View {
        let pinned = model.store.activeID.map(model.actions.pinned(for:)) ?? []
        // The unpinned actions' icons too, for the "+" list.
        let iconApps = (pinned + model.unpinnedActions).filter { $0.shownTile == .icon }.compactMap(\.iconAppID)
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: 3)
        VStack(alignment: .leading, spacing: 0) {
            header(empty: pinned.isEmpty)
            LazyVGrid(columns: columns, spacing: Self.gap) {
                ForEach(pinned) { action in
                    let icon = icon(action)
                    let edge = icon?.edge
                    GHButton(dimmed: !editing && session.unavailableReason(action) != nil, fill: edge?.color,
                             outlined: edge.map { $0.blends(into: background) } ?? true,
                             action: { editing ? model.edit(action) : keyboard?.buttonClicked(.action(action.id)) }) {
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
                    .keyed(.action(action.id))
                    .disabled(!editing && controlsOff && !session.canTrigger(action))
                    .modifier(PinEdit(editing: editing, id: action.id, dragging: $dragging,
                                      delete: { model.deleteAction(action.id) },
                                      move: { model.movePin($0, to: action.id) }))
                }
                if pinned.isEmpty || editing {
                    GHButton(dashed: true, action: add) {
                        Text(verbatim: "+").font(.manrope(16, .light))
                    }
                    .disabled(addDisabled)
                    .anchorPreference(key: PinsListAnchor.self, value: .bounds) { $0 }
                    .accessibilityLabel(Text("New action"))
                }
            }
            if editing {
                Text("Drag a pin to move it, click it to edit it.")
                    .foregroundStyle(palette.label)
                    .padding(.top, 9)
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

    /// The editor on a new action, or the list of the unpinned ones first.
    private func add() {
        if model.unpinnedActions.isEmpty {
            model.newAction()
        } else {
            keyboard?.pinsListOpen = true
        }
    }

    /// "Pinned", and the pencil on its right once a pin is there (before, the row's tile adds), Done while
    /// the pins are edited.
    private func header(empty: Bool) -> some View {
        HStack(alignment: .center) {
            Text("Pinned").sectionLabelStyle()
            Spacer(minLength: 8)
            if editing {
                PinsLink("Done") { keyboard?.finishEditingPins() }
            } else if !empty {
                EditPinsButton { keyboard?.editPins() }
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

/// A small pencil right of Pinned, a little brighter than the label, the foreground's under the
/// pointer: it edits the pins.
private struct EditPinsButton: View {
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: 11.5, weight: .medium))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovered && isEnabled ? palette.fg : palette.fg.opacity(0.7))
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovered = $0 }
        .help(Text("Edit"))
        .accessibilityLabel(Text("Edit"))
    }
}

/// Done, right of Pinned while the pins are edited: the label's size and tracking, in the foreground's colour, dimmed
/// under the pointer or pressed.
private struct PinsLink: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.manrope(Metrics.labelSize, .semibold))
                .tracking(Metrics.labelTracking)
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
                .frame(height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.fg.opacity(!isEnabled ? 0.35 : hovered ? 0.7 : 1))
        .onHover { hovered = $0 }
    }
}

/// A pin while the pins are edited: its × in the top left corner, and dragged onto another pin, it
/// takes its place.
private struct PinEdit: ViewModifier {
    let editing: Bool
    let id: UUID
    @Binding var dragging: UUID?
    let delete: () -> Void
    let move: (UUID) -> Void
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        if editing {
            content
                .overlay(alignment: .topLeading) {
                    Button(action: delete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(palette.bg)
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(palette.fg))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: -7, y: -7)
                    .help(Text("Delete"))
                    .accessibilityLabel(Text("Delete"))
                }
                .onDrag {
                    dragging = id
                    return NSItemProvider(object: id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: PinDrop(target: id, dragging: $dragging, move: move))
        } else {
            content
        }
    }
}

/// The dragged pin moves as soon as it enters another's place.
private struct PinDrop: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let move: (UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeOut(duration: 0.15)) { move(dragging) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Where the pins' "+" is, for the list it opens.
struct PinsListAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// The pins' "+" list, in a white frame like the keys' bar: the unpinned actions, each with its
/// icon and its keys, which a click pins again, then "New Action…". Drawn over the popover, above
/// the "+" (under it, only the footer is left); a click anywhere else or Esc closes it.
struct PinsList: View {
    let model: AppModel
    let keyboard: KeyboardController
    @Environment(\.palette) private var palette

    static let width: CGFloat = 236

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pin again")
                .sectionLabelStyle()
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(model.unpinnedActions) { action in
                Button {
                    keyboard.pinsListOpen = false
                    model.pin(action.id)
                } label: {
                    HStack(spacing: 7) {
                        icon(action)
                        Text(verbatim: action.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let key = keyboard.label(for: .action(action.id)) {
                            Chip(text: key, fill: palette.fg, none: "key.none")
                        }
                        if let global = keyboard.globalLabel(for: .action(action.id)) {
                            Chip(text: global, fill: palette.global, none: "shortcut.none")
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PinsListRowStyle())
            }
            Hairline()
            Button {
                keyboard.pinsListOpen = false
                model.newAction()
            } label: {
                Text("New Action…")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PinsListRowStyle())
        }
        .font(.manrope(12))
        .frame(width: Self.width)
        .background(palette.bg)
        .overlay(Rectangle().strokeBorder(palette.fg, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
    }

    /// The app's icon when it came, else an empty square, so that the titles line up.
    @ViewBuilder private func icon(_ action: CustomAction) -> some View {
        if let app = action.iconAppID, let data = model.icons.icon(for: app), let image = NSImage(data: data) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: 16, height: 16)
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }
}

/// A row of the pins' list: lit under the pointer or pressed.
private struct PinsListRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Lit(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct Lit<Label: View>: View {
        let label: Label
        let pressed: Bool
        @State private var hovered = false
        @Environment(\.palette) private var palette

        var body: some View {
            label
                .background(palette.fg.opacity(pressed ? 0.16 : hovered ? 0.09 : 0))
                .onHover { hovered = $0 }
        }
    }
}

private struct IconRequest: Equatable {
    let apps: [String]
    let session: ObjectIdentifier
    let reachable: Bool
}
