import PaneKit
import SwiftUI

/// Picture, Audio and Game: the TV's setting rows, grouped as the web dashboard groups them.
struct SettingsTab: View {
    enum Kind {
        case picture, audio, game

        var tab: PaneTab {
            switch self {
            case .picture: .picture
            case .audio: .audio
            case .game: .game
            }
        }
        /// The web dashboard's tab of the same name.
        var webTab: String {
            switch self {
            case .picture: "picture"
            case .audio: "audio"
            case .game: "game"
            }
        }
    }

    let kind: Kind
    let model: AppModel
    let session: TVSession
    @Environment(\.palette) private var palette
    @State private var hoveringMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Only the rows go grey: the scroll and the link to the dashboard keep working.
            #if os(iOS)
            // The rows lock themselves (`locked`), so that their ⓘ keeps working.
            CappedScroll { content }
            #else
            CappedScroll { content.disabled(!session.canControl) }
            #endif
            if model.client?.dashboardURL(tab: kind.webTab) != nil {
                Button("All settings ↗") { model.openDashboard(tab: kind.webTab) }
                    .buttonStyle(AllSettingsStyle())
                    .padding(.top, 10)
            }
        }
        .refreshing(kind.tab, model: model, session: session)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch kind {
        case .picture: pictureContent
        case .audio: groupsView(RowLayout.plain(session.audio?.lgSettings ?? [], section: "sound"))
        case .game: gameContent
        }
    }

    @ViewBuilder private var pictureContent: some View {
        if let picture = session.picture {
            let layout = RowLayout.picture(picture.rows)
            VStack(alignment: .leading, spacing: 0) {
                if let mode = layout.mode { modeHeader(mode, dimension: picture.dimension, inputs: picture.inputs) }
                groupsView(layout.groups)
            }
        }
    }

    @ViewBuilder private var gameContent: some View {
        if let game = session.game {
            if game.available {
                groupsView(RowLayout.plain(game.rows ?? [], section: "game"))
            } else {
                Text("Game Optimizer isn't available on this TV")
                    .foregroundStyle(palette.label)
            }
        }
    }

    private func modeHeader(_ mode: SettingRow, dimension: PicturePayload.Dimension?,
                            inputs: [String: String]?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let scope = Self.scope(dimension, inputs) {
                Text(verbatim: scope).sectionLabelStyle()
            }
            if case .choice(let value, let choices) = mode.kind {
                let label = choices.first { $0.value == value }?.label ?? value
                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 6) {
                        #if os(iOS)
                        // One line, shrunk as far as needed to fit (« HDR Cinema Bright » on a 390 pt
                        // iPhone): mockups/2026-11-03-app-preview/picture-title.html, option A.
                        Text(verbatim: label)
                            .font(.manrope(points: 32, .light))
                            .pinMenu(session.canControl ? { model.pinPictureMode(value, label: label) } : nil)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        #else
                        Text(verbatim: label)
                            .font(.manrope(24, .light))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        PinButton(visible: hoveringMode) { model.pinPictureMode(value, label: label) }
                        #endif
                        #if os(iOS)
                        if let desc = mode.desc, !desc.isEmpty {
                            DescInfoButton(text: desc).accessibilityIdentifier("setting.\(mode.id).info")
                        }
                        #endif
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ChoiceMenu(value: value, choices: choices, title: String(localized: "Mode")) { send("pictureMode", .string($0)) }
                        .accessibilityIdentifier("picture.mode")
                        #if os(iOS)
                        // At its own width: its frame would otherwise take up to 210 pt from the title.
                        .fixedSize()
                        .disabled(!mode.active || !session.canControl)
                        #else
                        .disabled(!mode.active)
                        #endif
                }
                .contentShape(Rectangle())
                .onHover { hoveringMode = $0 }
                .help(mode.desc ?? "")
            }
        }
        .padding(.bottom, 12)
    }

    private func groupsView(_ groups: [RowGroup]) -> some View {
        #if os(iOS)
        // Room for a finger between the groups.
        let spacing: CGFloat = 30
        #else
        let spacing: CGFloat = 10
        #endif
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    if let title = group.title {
                        Text(verbatim: title)
                            #if os(iOS)
                            .font(.manrope(points: 16, .medium))
                            #else
                            .font(.manrope(13))
                            #endif
                            .padding(.bottom, 3)
                    }
                    ForEach(group.rows) { row in
                        SettingRowView(row: row, locked: !session.canControl) { send(row.id, $0) } onPin: { model.pin(row: row) }
                        Hairline().opacity(0.6)
                    }
                }
            }
        }
    }

    private func send(_ id: String, _ value: SettingValue) {
        #if os(iOS)
        model.noteCommandSent()
        #endif
        Task { await session.send(.lgSetting(id: id, value)) }
    }

    // MARK: Picture header

    /// "HDMI 4 · HDR": the input and the dynamic range of the moment, as the dashboard names them.
    static func scope(_ dimension: PicturePayload.Dimension?, _ inputs: [String: String]?) -> String? {
        guard let dimension else { return nil }
        let input = dimension.input.map { inputName($0, inputs) }
        let range = dimension.dynamicRange.map(rangeName)
        let parts = [input, range].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func inputName(_ input: String, _ inputs: [String: String]?) -> String {
        if input.hasPrefix("hdmi"), let port = Int(input.dropFirst(4)) {
            let name = inputs?[input]
            let squashed = name?.filter { !$0.isWhitespace }.lowercased()
            return (name != nil && squashed != input) ? name! : "HDMI \(port)"
        }
        switch input {
        case "default": return String(localized: "apps")
        case "dtv", "atv", "tv": return String(localized: "TV channels")
        default: return input.isEmpty ? String(localized: "this input") : input
        }
    }

    private static func rangeName(_ range: String) -> String {
        switch range {
        case "sdr": "SDR"
        case "hdr": "HDR"
        case "hlg": "HLG"
        case "dolbyHdr": "Dolby Vision"
        case "technicolorHdr": "Technicolor HDR"
        default: range
        }
    }
}

/// Reads a tab now and every 4 s while the popover is open. The loop is keyed on the open state:
/// closing the popover ends it even if the hosted view stays alive, reopening starts it again.
private struct TabRefresh: Hashable {
    let tab: PaneTab
    let open: Bool
}

extension View {
    func refreshing(_ tab: PaneTab, model: AppModel, session: TVSession) -> some View {
        task(id: TabRefresh(tab: tab, open: model.isOpen)) {
            guard model.isOpen else { return }
            while !Task.isCancelled && model.isOpen {
                await session.refresh(tab)
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}

/// The link at the foot of a tab: label text, full strength while pressed.
struct AllSettingsStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sectionLabelStyle()
            .foregroundStyle(configuration.isPressed ? palette.fg : palette.label)
            #if os(iOS)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            #endif
    }
}

/// A tab's scrolling body: as tall as its content up to 520 pt, then it scrolls. On iOS, the
/// content as it is: the whole screen scrolls.
struct CappedScroll<Content: View>: View {
    @ViewBuilder let content: Content
    #if os(macOS)
    @State private var contentHeight: CGFloat = 120

    private static var maxHeight: CGFloat { 520 }
    #endif

    var body: some View {
        #if os(iOS)
        content.frame(maxWidth: .infinity, alignment: .leading)
        #else
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                // Room for a legacy scroller, which does not hide and would cover the controls.
                .padding(.trailing, contentHeight > Self.maxHeight ? 16 : 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.hidden)
        .frame(height: min(contentHeight, Self.maxHeight))
        #endif
    }
}
