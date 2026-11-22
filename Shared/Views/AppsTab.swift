import PaneKit
import SwiftUI

/// Apps: every app of the TV, in the editor's order (mockups/2026-11-21-apps/apps.html, variant 2).
/// A grid of icons and names, four to a row (more in the iPad's wide page): a click launches the app,
/// as a pin that does just that would, a right-click (a long press on iOS) pins or unpins it. The
/// app on screen has a green dot under its icon, a pinned one a pin in its top right corner. Pin…
/// turns the grid into a list where a click anywhere on a row pins or unpins its app and launches
/// nothing; Done, another tab, the popover closing or another TV bring the grid back. On the Mac,
/// both scroll in a fixed height; on iOS, the page scrolls.
struct AppsTab: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.palette) private var palette
    @Environment(\.keyShape) private var keyShape
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    /// The list that pins is shown in place of the grid.
    @State private var pinning = false

    /// The height the grid and the list scroll in, close to Remote's with a row of pins and the pad.
    static let macHeight: CGFloat = 430

    #if os(macOS)
    private static let tileSize: CGFloat = 52
    private static let rowIconSize: CGFloat = 30
    private static let rowHeight: CGFloat = 38
    private static let markSize: CGFloat = 11
    #else
    private static let tileSize: CGFloat = 58
    private static let rowIconSize: CGFloat = 38
    private static let rowHeight: CGFloat = 50
    private static let markSize: CGFloat = 13
    #endif
    private static let gap: CGFloat = 6
    /// A row's icon: the tile's corners, in proportion.
    private static let rowIconShape = AnyShape(RoundedRectangle(cornerRadius: Metrics.keyRadius * rowIconSize / tileSize))

    var body: some View {
        // The editor's list, in its order.
        let apps = session.actionContext.apps
        VStack(alignment: .leading, spacing: 0) {
            if apps.isEmpty {
                // No stats yet in this session: nothing to list.
                Text("Apps appear once the TV answers")
                    .font(.manrope(10))
                    .foregroundStyle(palette.label)
            } else {
                header(apps)
                #if os(macOS)
                ScrollView {
                    content(apps)
                        // No scroller, like Settings and the pins.
                        .background(HiddenScrollers())
                }
                .frame(height: Self.macHeight)
                #else
                content(apps)
                #endif
            }
        }
        .onDisappear { pinning = false }
        // The popover's hosting controller stays alive when it closes, and may not send onDisappear.
        .onChange(of: model.isOpen) { if !model.isOpen { pinning = false } }
        .onChange(of: ObjectIdentifier(session)) { pinning = false }
        // Again for other apps, another TV, or a TV that answers again.
        .task(id: IconRequest(apps: apps.map(\.id), session: ObjectIdentifier(session), reachable: session.power != .unreachable)) {
            guard session.power != .unreachable else { return }
            await model.icons.refresh(apps.map(\.id)) { await session.appIcon($0) }
        }
    }

    @ViewBuilder private func content(_ apps: [Stats.App]) -> some View {
        if pinning {
            VStack(spacing: 0) {
                ForEach(apps, id: \.id) { row($0) }
            }
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(apps, id: \.id) { cell($0) }
            }
        }
    }

    /// Four columns; in a wider page (the iPad's), as many as fit at about the same width.
    private var columns: [GridItem] {
        #if os(iOS)
        if sizeClass == .regular { return [GridItem(.adaptive(minimum: 84), spacing: Self.gap, alignment: .top)] }
        #endif
        // At the top, so that the icons line up whatever the names' lines.
        return Array(repeating: GridItem(.flexible(), spacing: Self.gap, alignment: .top), count: 4)
    }

    /// The number of apps and Pin…; while pinning, the number of pinned apps and Done.
    private func header(_ apps: [Stats.App]) -> some View {
        HStack(alignment: .center) {
            if pinning {
                Text("\(apps.filter { model.isPinned(app: $0.id) }.count) pinned").sectionLabelStyle()
                Spacer(minLength: 8)
                PinsLink("Done") { pinning = false }
            } else {
                Text("\(apps.count) apps").sectionLabelStyle()
                Spacer(minLength: 8)
                PinsLink("Pin…") { pinning = true }
            }
        }
        .frame(height: 12 * Metrics.fontScale)
        .padding(.bottom, 7)
    }

    /// An app of the grid, its icon and name one button that launches it. Greyed and off as a pin
    /// that launches it would be.
    private func cell(_ app: Stats.App) -> some View {
        let pinned = model.isPinned(app: app.id)
        // Without its icon, the tile shows the name: the caption keeps its room, unseen, so that the
        // row's icons stay in line.
        let iconShown = model.icons.icon(for: app.id).flatMap(Image.init(data:)) != nil
        return Button { model.launch(app) } label: {
            VStack(spacing: 5) {
                AppIcon(app: app, icons: model.icons, size: Self.tileSize, shape: keyShape, titled: true,
                        onScreen: onScreen(app), pinMark: pinned ? Self.markSize : nil)
                Text(verbatim: app.title)
                    .font(.outfit(10.5))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.fg.opacity(0.8))
                    .opacity(iconShown ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppCellStyle(dimmed: session.unavailableReason(app.launchAction) != nil))
        .disabled(!session.canTrigger(app.launchAction))
        .help(app.title)
        .accessibilityLabel(Text(verbatim: app.title))
        .accessibilityValue(pinned ? Text("app.pinned") : Text(verbatim: ""))
        .accessibilityHint(Text(verbatim: ""))
        .accessibilityIdentifier("apps.app.\(app.id)")
        // Outside the button's disabled state: pinning sends nothing to the TV.
        .contextMenu {
            if pinned {
                Button("Unpin", systemImage: "pin.slash") { model.unpin(app: app) }
            } else {
                Button("Pin", systemImage: "pin") { model.pin(app: app) }
            }
        }
    }

    /// An app of the list, the whole row one button that pins or unpins it.
    private func row(_ app: Stats.App) -> some View {
        let pinned = model.isPinned(app: app.id)
        return Button { pinned ? model.unpin(app: app) : model.pin(app: app) } label: {
            HStack(spacing: 10) {
                AppIcon(app: app, icons: model.icons, size: Self.rowIconSize, shape: Self.rowIconShape, titled: false,
                        onScreen: onScreen(app), pinMark: nil)
                Text(verbatim: app.title)
                    #if os(iOS)
                    .font(.outfit(points: 18.5))
                    #else
                    .font(.outfit(14))
                    #endif
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: Self.markSize, weight: .medium))
                    .foregroundStyle(pinned ? palette.fg : palette.fg.opacity(0.35))
                    .frame(width: 28)
            }
            .foregroundStyle(palette.fg)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PinsListRowStyle())
        .overlay(alignment: .bottom) { Hairline().opacity(0.6) }
        .accessibilityLabel(Text(verbatim: app.title))
        .accessibilityValue(pinned ? Text("app.pinned") : Text(verbatim: ""))
        // What the row does, unlike a cell of the grid.
        .accessibilityHint(pinned ? Text("Unpin") : Text("Pin"))
    }

    private func onScreen(_ app: Stats.App) -> Bool { session.stats?.isForeground(appID: app.id) == true }
}

/// An app's icon in a tile of the given shape (a key's rounded corners), filled with the colour of
/// its edge, the tile's edge drawn when that colour blends into the background, as a pin's. Without
/// the icon (not come yet, or none on the TV), the app's title in the tile, as a pin without one
/// shows, or nothing. The green dot of the app on screen bottom left; with `pinMark`, a pin in a
/// black disc of that size top right.
private struct AppIcon: View {
    let app: Stats.App
    let icons: AppIconStore
    let size: CGFloat
    let shape: AnyShape
    /// The title in the tile while there is no icon.
    let titled: Bool
    let onScreen: Bool
    let pinMark: CGFloat?
    @Environment(\.palette) private var palette

    var body: some View {
        let image = icons.icon(for: app.id).flatMap(Image.init(data:))
        let edge = image == nil ? nil : icons.edge(for: app.id)
        let outlined = edge.map { $0.blends(into: palette.bgComponents) } ?? true
        ZStack {
            if let image {
                image.resizable().interpolation(.high)
            } else if titled {
                Text(verbatim: app.title)
                    .nameOnKey(lines: 2)
                    .foregroundStyle(palette.fg)
                    .padding(3)
            }
        }
        .frame(width: size, height: size)
        .background(edge?.color ?? palette.key)
        .clipShape(shape)
        .overlay(shape.strokeInside(outlined ? palette.line : .clear, style: StrokeStyle(lineWidth: 1)))
        .overlay(alignment: .bottomLeading) {
            if onScreen {
                // Ringed in black, to stand out from any icon.
                OnDot(size: 6)
                    .background(Circle().fill(.black).padding(-1.5))
                    .padding(4)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let pinMark {
                Image(systemName: "pin.fill")
                    .font(.system(size: pinMark * 0.55, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: pinMark, height: pinMark)
                    .background(Circle().fill(.black))
                    .background(Circle().fill(.white.opacity(0.55)).padding(-1))
                    .padding(2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A tile of the grid: darker while pressed, greyed as one (an icon over its fill would otherwise
/// show through brighter than the fill) when off or when its launch cannot run here.
private struct AppCellStyle: ButtonStyle {
    let dimmed: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.15 : 0)
            .compositingGroup()
            .opacity(isEnabled && !dimmed ? 1 : 0.35)
    }
}
