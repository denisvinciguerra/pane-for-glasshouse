import PaneKit
import SwiftUI

/// Apps: every app of the TV, in the editor's order (mockups/2026-11-21-apps/apps.html, variant 2).
/// A grid of icons and names, four to a row (more in the iPad's wide page): a click launches the app,
/// as a pin that does just that would, a right-click (a long press on iOS) pins or unpins it. The
/// app on screen has a green dot under its icon, a pinned one a pin in its top right corner. Pin…
/// turns the grid into a list where a click anywhere on a row pins or unpins its app and launches
/// nothing; Done, another tab, the popover closing or another TV bring the grid back. On the Mac,
/// both scroll in a fixed height; on iOS, the page scrolls.
///
/// Above the grid, a strip of the TV's recent apps (mockups/2026-11-27-recentes-mac/bande.html, B):
/// the app on screen first, then the TV's recent cards in its order, then after a rule the apps in
/// memory without a card. A click opens one; on the Mac a cross shows on hover, and a right-click
/// (a long press on iOS) says the app's state and memory, opens it or closes it.
struct AppsTab: View {
    let model: AppModel
    let session: TVSession
    @Environment(\.palette) private var palette
    @Environment(\.keyShape) private var keyShape
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    #endif
    /// The list that pins is shown in place of the grid.
    @State private var pinning = false
    @State private var confirmsCloseAll = false
    @State private var appToClose: AppActivity?

    /// The strip reads the TV's lists while it can show: the tab in front, the grid (not the list
    /// that pins), the TV in reach.
    private var refreshesRecents: Bool {
        guard !pinning, model.isOpen, session.power != .unreachable, !session.isClosingAllApps else { return false }
        #if os(iOS)
        return scenePhase == .active
        #else
        // NSPopover visibility comes from its delegate, not a SwiftUI scene's phase.
        return true
        #endif
    }

    /// The height the grid and the list scroll in, close to Remote's with a row of pins and the pad.
    static let macHeight: CGFloat = 430

    #if os(macOS)
    private static let tileSize: CGFloat = 52
    private static let rowIconSize: CGFloat = 30
    private static let rowHeight: CGFloat = 38
    private static let markSize: CGFloat = 11
    private static let stripTile: CGFloat = 40
    private static let stripName: CGFloat = 9.5
    #else
    private static let tileSize: CGFloat = 58
    private static let rowIconSize: CGFloat = 38
    private static let rowHeight: CGFloat = 50
    private static let markSize: CGFloat = 13
    private static let stripTile: CGFloat = 48
    private static let stripName: CGFloat = 10.5
    #endif
    private static let gap: CGFloat = 6
    /// A row's icon: the tile's corners, in proportion.
    private static let rowIconShape = AnyShape(RoundedRectangle(cornerRadius: Metrics.keyRadius * rowIconSize / tileSize))
    /// A tile of the strip: the grid's corners, in proportion.
    private static let stripShape = AnyShape(RoundedRectangle(cornerRadius: Metrics.keyRadius * stripTile / tileSize))
    /// Room above the strip's icons for the cross that sticks out of their corner.
    private static let stripTop: CGFloat = 6
    /// The strip's tiles: the icon, the gap, a line of name.
    private static let stripTiles: CGFloat = stripTop + stripTile + 5 + (stripName * Metrics.fontScale * 1.6).rounded(.up)
    private static let stripBottom: CGFloat = 14
    /// The header's height, as `header(_:)` sets it.
    private static let headerHeight: CGFloat = 12 * Metrics.fontScale + 7

    var body: some View {
        // The editor's list, in its order.
        let apps = session.actionContext.apps
        let activity = activityList
        // Its room is kept while the first list comes, so that the grid does not jump down.
        let loading = session.recentApps == nil && session.recentsError == nil
        let stripShown = !pinning && !apps.isEmpty && session.power != .unreachable
            && (loading || !(activity.recents.isEmpty && activity.background.isEmpty))
        VStack(alignment: .leading, spacing: 0) {
            if apps.isEmpty {
                // No stats yet in this session: nothing to list.
                Text("Apps appear once the TV answers")
                    .font(.manrope(10))
                    .foregroundStyle(palette.label)
            } else {
                if stripShown { recentStrip(activity) }
                header(apps)
                #if os(macOS)
                ScrollView {
                    content(apps)
                        // No scroller, like Settings and the pins.
                        .background(HiddenScrollers())
                }
                // The strip takes its room from the grid: the popover keeps its height.
                .frame(height: Self.macHeight - (stripShown ? Self.headerHeight + Self.stripTiles + Self.stripBottom : 0))
                #else
                content(apps)
                #endif
            }
        }
        .onDisappear { pinning = false; appToClose = nil; confirmsCloseAll = false }
        .task(id: ActivityRequest(session: ObjectIdentifier(session), active: refreshesRecents, foreground: foregroundID)) {
            guard refreshesRecents else { return }
            while !Task.isCancelled {
                await session.refreshApps()
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
        .alert("Close this app?", isPresented: Binding(get: { appToClose != nil }, set: { if !$0 { appToClose = nil } }), presenting: appToClose) { app in
            Button("Close app", role: .destructive) { close(app) }
            Button("Cancel", role: .cancel) {}
        } message: { app in
            Text("Closing \(app.title) will interrupt what is playing on the TV.")
        }
        .alert("Close all apps?", isPresented: $confirmsCloseAll) {
            Button("Close all", role: .destructive) {
                Task { @MainActor in
                    if await session.closeAllApps() {
                        #if os(iOS)
                        model.noteCommandSent()
                        #endif
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will close all apps and clear recent apps. Playback on the TV will be interrupted.")
        }
        // The popover's hosting controller stays alive when it closes, and may not send onDisappear.
        .onChange(of: model.isOpen) { if !model.isOpen { pinning = false; confirmsCloseAll = false } }
        .onChange(of: ObjectIdentifier(session)) { pinning = false; appToClose = nil; confirmsCloseAll = false }
        // Again for other apps, another TV, or a TV that answers again. The strip's apps too: an
        // input (HDMI4) or a settings app has a card but is not in the TV's app list.
        .task(id: IconRequest(apps: iconIDs(apps, activity), session: ObjectIdentifier(session), reachable: session.power != .unreachable)) {
            guard session.power != .unreachable else { return }
            await model.icons.refresh(iconIDs(apps, activity)) { await session.appIcon($0) }
        }
    }

    private func iconIDs(_ apps: [Stats.App], _ activity: AppActivityList) -> [String] {
        var seen = Set<String>()
        return (apps.map(\.id) + activity.recents.map(\.id) + activity.background.map(\.id)).filter { seen.insert($0).inserted }
    }

    private struct ActivityRequest: Equatable {
        let session: ObjectIdentifier
        let active: Bool
        let foreground: String?
    }

    private var foregroundID: String? {
        guard let stats = session.stats else { return nil }
        return session.appsOverview?.running?.first(where: { stats.isForeground(appID: $0.id) })?.id
    }

    /// The recent cards with the app on screen first, then the apps in memory without a card.
    private var activityList: AppActivityList {
        AppActivityList(recents: session.recentApps?.apps ?? [], running: session.appsOverview?.running ?? [],
                        foregroundID: foregroundID, transition: session.recentTransition)
    }

    private func recentStrip(_ list: AppActivityList) -> some View {
        // The app on screen leads, wherever the TV put its card.
        let recents = list.recents.filter(isOnScreen) + list.recents.filter { !isOnScreen($0) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Recent").sectionLabelStyle()
                Spacer(minLength: 8)
                PinsLink(session.isClosingAllApps ? "Closing…" : "Close all") { confirmsCloseAll = true }
                    .disabled(!session.canCloseAllApps)
            }
            .frame(height: 12 * Metrics.fontScale)
            .padding(.bottom, 7)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Self.gap + 2) {
                    ForEach(recents) { stripTile($0) }
                    if !list.background.isEmpty {
                        Rectangle().fill(palette.line)
                            .frame(width: 1, height: Self.stripTile * 0.8)
                            .padding(.top, Self.stripTop + Self.stripTile * 0.1)
                            .padding(.horizontal, 2)
                        ForEach(list.background) { stripTile($0) }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                #if os(macOS)
                .background(HiddenScrollers())
                .background(DragScroller())
                #endif
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Metrics.gutter)
            .frame(height: Self.stripTiles)
            .padding(.bottom, Self.stripBottom)
        }
    }

    private func isOnScreen(_ app: AppActivity) -> Bool { session.stats?.isForeground(appID: app.id) == true }

    private func stripTile(_ app: AppActivity) -> some View {
        let onScreen = isOnScreen(app)
        let unavailable = app.recent ? session.recentsError != nil : session.appsError != nil || session.appsOverview?.writable != true
        let canClose = session.canControl && !session.stale && session.closingApp == nil && !session.isClosingAllApps && !unavailable
        let launch = Stats.App(id: app.id, title: app.title)
        return RecentTile(app: launch, icons: model.icons, size: Self.stripTile, nameSize: Self.stripName,
                          shape: Self.stripShape, top: Self.stripTop, onScreen: onScreen,
                          inBackground: !app.recent, closing: session.closingApp == app.id,
                          status: status(app, onScreen: onScreen), canOpen: session.canTrigger(launch.launchAction),
                          canClose: canClose, open: { model.launch(launch) },
                          close: { if onScreen { appToClose = app } else { close(app) } })
    }

    /// "On screen · 113 MB", "In memory · 96 MB", or nil for a card whose app is not running.
    private func status(_ app: AppActivity, onScreen: Bool) -> String? {
        var parts: [String] = []
        if onScreen { parts.append(String(localized: "On screen")) }
        else if app.running != nil { parts.append(String(localized: "In memory")) }
        if let mb = app.running?.mb, mb.isFinite, mb >= 0, session.appsError == nil {
            let amount = mb.formatted(.number.precision(.fractionLength(0)))
            parts.append(String(localized: "\(amount) MB"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func close(_ app: AppActivity) {
        Task { @MainActor in
            if await session.closeApp(app.id) {
                #if os(iOS)
                model.noteCommandSent()
                #endif
            }
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

/// A tile of the recent apps' strip: the icon (the green dot of the app on screen), its name on a
/// line under it, greyed for an app in memory without a card. A click opens the app. On the Mac, a cross on
/// the icon's corner while the mouse is over it closes it, and the help says its state and memory;
/// the context menu (a long press on iOS) says them too, and opens or closes it.
private struct RecentTile: View {
    let app: Stats.App
    let icons: AppIconStore
    let size: CGFloat
    let nameSize: CGFloat
    let shape: AnyShape
    let top: CGFloat
    let onScreen: Bool
    let inBackground: Bool
    let closing: Bool
    let status: String?
    let canOpen: Bool
    let canClose: Bool
    let open: () -> Void
    let close: () -> Void
    @State private var hovered = false
    @Environment(\.palette) private var palette

    var body: some View {
        let iconShown = icons.icon(for: app.id).flatMap(Image.init(data:)) != nil
        Button(action: open) {
            VStack(spacing: 5) {
                AppIcon(app: app, icons: icons, size: size, shape: shape, titled: true, onScreen: onScreen, pinMark: nil)
                    .opacity(closing ? 0.4 : 1)
                Text(verbatim: app.title)
                    .font(.outfit(nameSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(inBackground ? palette.label : palette.fg.opacity(0.8))
                    .frame(width: size + 10)
                    .opacity(iconShown ? 1 : 0)
            }
            .padding(.top, top)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppCellStyle(dimmed: false))
        .disabled(!canOpen)
        #if os(macOS)
        .overlay(alignment: .topTrailing) {
            if (hovered && canClose) || closing { crossButton }
        }
        .onHover { hovered = $0 }
        .help(summary)
        #endif
        .contextMenu {
            Section {
                Button("Open", systemImage: "arrow.up.forward") { open() }.disabled(!canOpen)
                Button("Close", systemImage: "xmark", role: .destructive) { close() }.disabled(!canClose)
            } header: {
                Text(verbatim: summary)
            }
        }
        .accessibilityLabel(Text(verbatim: app.title))
        .accessibilityValue(Text(verbatim: status ?? ""))
        .accessibilityAction(named: Text("Close")) { if canClose { close() } }
        .accessibilityIdentifier("apps.recent.\(app.id)")
    }

    /// "Netflix · In memory · 96 MB".
    private var summary: String { status.map { app.title + " · " + $0 } ?? app.title }

    private var crossButton: some View {
        Button(action: close) {
            Group {
                if closing { ProgressView().controlSize(.mini) }
                else { Image(systemName: "xmark").font(.system(size: 7.5, weight: .bold)) }
            }
            .foregroundStyle(palette.fg)
            .frame(width: 16, height: 16)
            .background(Circle().fill(palette.key))
            .overlay(Circle().strokeInside(palette.line, style: StrokeStyle(lineWidth: 1)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canClose)
        .offset(x: -1, y: top - 6)
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
