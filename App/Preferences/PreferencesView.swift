import Observation
import PaneKit
import SwiftUI

/// The panes of the preferences window.
enum PreferencesPane: String, CaseIterable {
    case general, tv, keys, pinned, about

    var title: LocalizedStringKey {
        switch self {
        case .tv: "TV"
        case .keys: "Keys"
        case .pinned: "Pinned"
        case .general: "General"
        case .about: "About"
        }
    }
}

/// What the window shows and how the Mac's keyboard types: set by its controller.
@MainActor @Observable final class PreferencesContext {
    var pane: PreferencesPane = .general
    /// Read again at each showing and when the input source changes.
    var layout = CurrentKeyboardLayout()
    /// How many times the window was closed: the panes start afresh after each closing (no key
    /// still waiting for Swap).
    var closings = 0
}

/// The preferences: the popover's tab bar, then the pane. Its palette follows the window's
/// appearance, which follows the theme.
struct PreferencesView: View {
    let model: AppModel
    @Bindable var context: PreferencesContext
    @Environment(\.colorScheme) private var colorScheme

    static let size = CGSize(width: 460, height: 540)
    static let gutter: CGFloat = 24

    var body: some View {
        let palette = Palette.of(colorScheme)
        VStack(spacing: 0) {
            TabBar(tabs: PreferencesPane.allCases, selection: $context.pane, title: \.title)
            switch context.pane {
            case .general: GeneralPane(model: model)
            case .tv: TVPane(model: model)
            case .keys: KeysPane(model: model, layout: context.layout).id(context.closings)
            case .pinned: PinnedPane(model: model)
            case .about: AboutPane()
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .font(.manrope(11))
        .foregroundStyle(palette.fg)
        .background(palette.bg)
        .environment(\.palette, palette)
        .environment(\.appModel, model)
    }
}

/// A pane's content, scrolled, with the window's margins.
struct PreferencesScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PreferencesView.gutter)
                .padding(.vertical, 18)
        }
    }
}

/// A line of secondary text, where a list has nothing to show.
struct PreferencesNote: View {
    let text: LocalizedStringKey
    @Environment(\.palette) private var palette

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.manrope(10.5))
            .foregroundStyle(palette.label)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A small text button in the label colour, full strength while pressed.
struct TextButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.manrope(10.5))
            .foregroundStyle(configuration.isPressed ? palette.fg : palette.label)
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
    }
}

/// One row of a preferences list: its line, what may come under it, a hairline at the bottom.
struct PreferencesRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Hairline().opacity(0.6) }
    }
}
