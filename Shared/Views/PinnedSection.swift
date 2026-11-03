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
/// tooltip. On iOS, one row of six that scrolls sideways beyond; a long press on a pin offers Edit,
/// Unpin and Delete, and while they are edited the pins stand in rows of six, every place in
/// sight: a pin follows the finger as soon as it moves, the others slide out of its way, and it
/// takes its new place on release; a short tap edits it. "+" offers the unpinned actions in a menu.
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
    #if os(iOS)
    /// The pin a finger is moving in the edit's grid.
    @State private var drag: PinDrag?
    /// When a finger came down on each pin it is still on: a tap is short.
    @State private var pressStarts: [UUID: Date] = [:]
    /// The grid's width, which its cells share.
    @State private var gridWidth: CGFloat = 0
    /// A finger is on a pin of the grid; back to false when the gesture ends or is cancelled.
    @GestureState private var touching = false
    #endif

    private static let gap: CGFloat = 6

    private var editing: Bool { keyboard?.pinsEditing == true }

    var body: some View {
        let pinned = model.activeID.map(model.actions.pinned(for:)) ?? []
        // The unpinned actions' icons too, for the "+" list.
        let iconApps = (pinned + model.unpinnedActions).filter { $0.shownTile == .icon }.compactMap(\.iconAppID)
        #if os(macOS)
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: 3)
        #endif
        VStack(alignment: .leading, spacing: 0) {
            header(empty: pinned.isEmpty)
            #if os(macOS)
            LazyVGrid(columns: columns, spacing: Self.gap) { tiles(pinned) }
            #else
            if editing {
                // Rows of six while the pins move: no sideways scroll for a drag to fight, and
                // every place in sight.
                reorderGrid(pinned)
            } else {
                // One row of six; more scroll sideways.
                ScrollView(.horizontal) {
                    HStack(spacing: Self.gap) { tiles(pinned) }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            #endif
            if editing {
                #if os(iOS)
                Text("Drag a pin to move it, tap it to edit it.")
                    .foregroundStyle(palette.label)
                    .padding(.top, 9)
                #else
                Text("Drag a pin to move it, click it to edit it.")
                    .foregroundStyle(palette.label)
                    .padding(.top, 9)
                #endif
            }
        }
        // Again for another TV, other pins, or a TV that answers again.
        .task(id: IconRequest(apps: iconApps, session: ObjectIdentifier(session), reachable: session.power != .unreachable)) {
            guard session.power != .unreachable else { return }
            await model.icons.refresh(iconApps) { await session.appIcon($0) }
        }
    }

    /// The pins, then the "+" while they are edited or when there is none.
    @ViewBuilder private func tiles(_ pinned: [CustomAction]) -> some View {
        ForEach(pinned) { action in
            tile(action)
                .accessibilityIdentifier("remote.pin.\(pinned.firstIndex { $0.id == action.id } ?? 0)")
        }
        if pinned.isEmpty || editing {
            #if os(iOS)
            addTile
                .disabled(addDisabled)
                .accessibilityLabel(Text("New action"))
                .modifier(RowCell(inRow: !editing, count: Self.perRow, spacing: Self.gap))
            #else
            GHButton(dashed: true, height: Self.iconSize, action: add) {
                Text(verbatim: "+").font(.manrope(16, .light))
            }
            .disabled(addDisabled)
            .anchorPreference(key: PinsListAnchor.self, value: .bounds) { $0 }
            .accessibilityLabel(Text("New action"))
            #endif
        }
    }

    /// A pin's tile: its action, or while the pins are edited, its editor.
    @ViewBuilder private func tile(_ action: CustomAction) -> some View {
        let icon = icon(action)
        let edge = icon?.edge
        GHButton(dimmed: !editing && session.unavailableReason(action) != nil, height: Self.iconSize, fill: edge?.color,
                 outlined: edge.map { $0.blends(into: background) } ?? true,
                 action: { editing ? model.edit(action) : keyboard?.buttonClicked(.action(action.id)) }) {
            if let icon {
                icon.image
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .accessibilityLabel(Text(verbatim: action.title))
            } else {
                Text(verbatim: action.title)
                    #if os(iOS)
                    .font(.manrope(8))
                    #endif
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
        #if os(iOS)
        // In the edit's grid, the finger's moves and taps go to the grid, not to the button
        // (still there for VoiceOver); the × stays above.
        .overlay {
            if editing {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(reorderGesture(action))
                    .accessibilityHidden(true)
            }
        }
        #endif
        .modifier(PinEdit(editing: editing, id: action.id, dragging: $dragging,
                          delete: { model.deleteAction(action.id) },
                          move: { model.movePin($0, to: action.id) }))
        #if os(iOS)
        .modifier(PinMenu(shown: !editing, edit: { model.edit(action) }, unpin: { model.unpin(action.id) },
                          delete: { model.deleteAction(action.id) }))
        .modifier(RowCell(inRow: !editing, count: Self.perRow, spacing: Self.gap))
        #endif
    }

    #if os(iOS)
    // MARK: Reordering

    /// The movement that turns a touch into a drag; less is a tap.
    private static let dragThreshold: CGFloat = 8
    /// The longest touch that still counts as a tap: a finger held longer edits nothing.
    private static let tapTime: TimeInterval = 0.5
    /// Room between the grid's rows, for the ×s.
    private static let rowGap: CGFloat = 12
    private static let gridSpace = "pins.grid"
    /// The tiles making room, and the dragged one settling.
    private static let slide = Animation.spring(duration: 0.3, bounce: 0.15)

    private var pinnedIDs: [UUID] { model.activeID.map { model.actions.pinned(for: $0).map(\.id) } ?? [] }

    private var grid: ReorderGrid {
        ReorderGrid(columns: Self.perRow, width: gridWidth, cellHeight: Self.iconSize,
                    columnSpacing: Self.gap, rowSpacing: Self.rowGap)
    }

    /// The pins, then "+", each in its cell. While a pin is dragged, it follows the finger above the
    /// others, which stand in the order a release would give.
    private func reorderGrid(_ pinned: [CustomAction]) -> some View {
        let ids = pinned.map(\.id)
        let grid = grid
        let shown = drag.map { ids.moving(from: $0.from, to: $0.slot) } ?? ids
        return ZStack(alignment: .topLeading) {
            ForEach(pinned) { action in
                let dragged = drag?.id == action.id
                let place = grid.origin(of: dragged ? drag?.from ?? 0 : shown.firstIndex(of: action.id) ?? 0)
                let moved = dragged ? drag?.translation ?? .zero : .zero
                tile(action)
                    .frame(width: grid.cellWidth)
                    .scaleEffect(dragged ? 1.08 : 1)
                    .shadow(color: .black.opacity(dragged ? 0.3 : 0), radius: 10, y: 6)
                    .animation(.spring(duration: 0.2), value: dragged)
                    .offset(x: place.x + moved.width, y: place.y + moved.height)
                    .zIndex(dragged ? 1 : 0)
            }
            let plus = grid.origin(of: ids.count)
            addTile
                .disabled(addDisabled || drag != nil)
                .accessibilityLabel(Text("New action"))
                .frame(width: grid.cellWidth)
                .offset(x: plus.x, y: plus.y)
        }
        .frame(maxWidth: .infinity, minHeight: grid.height(for: ids.count + 1), alignment: .topLeading)
        .coordinateSpace(.named(Self.gridSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        // Picked up, each new place, dropped.
        .sensoryFeedback(Haptics.tap, trigger: drag?.slot)
        // A gesture the system cancelled (a rotation, a call) never ends: its drag ends here,
        // nothing moved.
        .onChange(of: touching) { _, now in
            guard !now else { return }
            Task { @MainActor in cancelDrag() }
        }
        .onDisappear { cancelDrag() }
    }

    /// A finger on a pin of the grid: moved past the threshold, it drags the pin; lifted soon
    /// without moving, it opens the pin's editor; held still, nothing.
    private func reorderGesture(_ action: CustomAction) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.gridSpace))
            .updating($touching) { _, state, _ in state = true }
            .onChanged { value in
                let id = action.id
                if pressStarts[id] == nil { pressStarts[id] = value.time }
                let ids = pinnedIDs
                if drag == nil, Self.distance(value.translation) >= Self.dragThreshold, let from = ids.firstIndex(of: id) {
                    drag = PinDrag(id: id, from: from, slot: from, translation: value.translation)
                }
                guard let current = drag, current.id == id else { return }
                drag?.translation = value.translation
                let origin = grid.origin(of: current.from)
                let centre = CGPoint(x: origin.x + grid.cellWidth / 2 + value.translation.width,
                                     y: origin.y + grid.cellHeight / 2 + value.translation.height)
                let slot = grid.slot(nearest: centre, count: ids.count)
                if slot != current.slot { withAnimation(Self.slide) { drag?.slot = slot } }
            }
            .onEnded { value in
                let start = pressStarts.removeValue(forKey: action.id)
                if let current = drag, current.id == action.id {
                    drop(current)
                } else if drag == nil, let start, value.time.timeIntervalSince(start) < Self.tapTime,
                          Self.distance(value.translation) < Self.dragThreshold {
                    model.edit(action)
                }
            }
    }

    /// The pin takes the place it was dropped on, in one move; if the pins changed under the finger
    /// (another TV, a pin deleted), nothing moves.
    private func drop(_ current: PinDrag) {
        let ids = pinnedIDs
        let still = ids.indices.contains(current.from) && ids[current.from] == current.id && ids.indices.contains(current.slot)
        withAnimation(Self.slide) {
            if still && current.slot != current.from { model.movePin(current.id, to: ids[current.slot]) }
            drag = nil
        }
    }

    private func cancelDrag() {
        pressStarts = [:]
        if drag != nil { withAnimation(Self.slide) { drag = nil } }
    }

    private static func distance(_ size: CGSize) -> CGFloat { (size.width * size.width + size.height * size.height).squareRoot() }

    /// "+": the editor on a new action, or first a menu of the unpinned actions, which a touch pins
    /// again, and New Action….
    @ViewBuilder private var addTile: some View {
        let unpinned = model.unpinnedActions
        if unpinned.isEmpty {
            GHButton(dashed: true, height: Self.iconSize, action: model.newAction) { plus }
        } else {
            Menu {
                Section("Pin again") {
                    ForEach(unpinned) { action in
                        Button(action.title) { model.pin(action.id) }
                    }
                }
                Button("New Action…", systemImage: "plus", action: model.newAction)
            } label: {
                // The dashed tile of GHButton, drawn here: a menu's label takes no button style.
                plus
                    .foregroundStyle(palette.fg.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: Self.iconSize, maxHeight: Self.iconSize)
                    .overlay(Rectangle().strokeBorder(palette.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    private var plus: some View {
        Text(verbatim: "+").font(.manrope(16, .light))
    }
    #endif

    /// The tile's height, which the icon fills: a button's on the Mac, taller on iOS.
    #if os(macOS)
    private static let iconSize: CGFloat = Metrics.buttonHeight
    #else
    private static let iconSize: CGFloat = 54
    /// The tiles one row shows.
    private static let perRow = 6
    #endif

    /// A click while keys are being set is for a key, and "+" carries none.
    private var addDisabled: Bool { keyboard?.state.setsKeys == true }

    #if os(macOS)
    /// The editor on a new action, or the list of the unpinned ones first.
    private func add() {
        if model.unpinnedActions.isEmpty {
            model.newAction()
        } else {
            keyboard?.pinsListOpen = true
        }
    }
    #endif

    /// "Pinned", and the pencil on its right once a pin is there (before, the row's tile adds), Done while
    /// the pins are edited.
    private func header(empty: Bool) -> some View {
        HStack(alignment: .center) {
            Text("Pinned").sectionLabelStyle()
            Spacer(minLength: 8)
            if editing {
                PinsLink("Done") { keyboard?.finishEditingPins() }
                    .accessibilityIdentifier("remote.pins.done")
            } else if !empty {
                EditPinsButton { keyboard?.editPins() }
                    .disabled(addDisabled)
                    .accessibilityIdentifier("remote.pins.edit")
            }
        }
        .frame(height: 12 * Metrics.fontScale)
        .padding(.bottom, 7)
    }

    /// The icon of the app the pin launches and its edge, when it is shown as one and the icon came.
    private func icon(_ action: CustomAction) -> (image: Image, edge: IconColor?)? {
        guard action.shownTile == .icon, let app = action.iconAppID, let data = model.icons.icon(for: app),
              let image = Image(data: data) else { return nil }
        return (image, model.icons.edge(for: app))
    }

    /// The popover's background, which a tile's colour must stand out from.
    private var background: IconColor { palette.bgComponents }
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
        #if os(iOS)
        // A finger's target, without moving the label.
        .contentShape(Rectangle().inset(by: -13))
        #endif
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
            #if os(iOS)
            // The grid moves the pins itself, under the finger.
            content.overlay(alignment: .topLeading) { deleteButton }
            #else
            content
                .overlay(alignment: .topLeading) { deleteButton }
                .onDrag {
                    dragging = id
                    return NSItemProvider(object: id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: PinDrop(target: id, dragging: $dragging, move: move))
            #endif
        } else {
            content
        }
    }

    private var deleteButton: some View {
        Button(action: delete) {
            #if os(iOS)
            // A finger's target around a slightly larger ×.
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.bg)
                .frame(width: 20, height: 20)
                .background(Circle().fill(palette.fg))
                .contentShape(Circle().inset(by: -8))
            #else
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(palette.bg)
                .frame(width: 15, height: 15)
                .background(Circle().fill(palette.fg))
                .contentShape(Circle())
            #endif
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .offset(x: -8, y: -8)
        #else
        .offset(x: -7, y: -7)
        #endif
        .help(Text("Delete"))
        .accessibilityLabel(Text("Delete"))
    }
}

#if os(iOS)
/// A pin out of the edit: a long press offers Edit, Unpin and Delete. During the edit, the long
/// press starts a drag instead.
private struct PinMenu: ViewModifier {
    let shown: Bool
    let edit: () -> Void
    let unpin: () -> Void
    let delete: () -> Void

    func body(content: Content) -> some View {
        if shown {
            content.contextMenu {
                Button("Edit", systemImage: "pencil", action: edit)
                Button("Unpin", systemImage: "pin.slash", action: unpin)
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            }
        } else {
            content
        }
    }
}

/// A pin a finger is moving: from its place, over the slot it would take, as far as the finger went.
private struct PinDrag: Equatable {
    let id: UUID
    let from: Int
    var slot: Int
    var translation: CGSize
}

/// A tile of the row that scrolls: its share of the row's width. In the edit's grid, its column's.
private struct RowCell: ViewModifier {
    let inRow: Bool
    let count: Int
    let spacing: CGFloat

    func body(content: Content) -> some View {
        if inRow {
            content.containerRelativeFrame(.horizontal, count: count, spacing: spacing)
        } else {
            content
        }
    }
}
#endif

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
        if let app = action.iconAppID, let data = model.icons.icon(for: app), let image = Image(data: data) {
            image.resizable().interpolation(.high).frame(width: 16, height: 16)
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
