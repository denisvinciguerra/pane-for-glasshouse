import PaneKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The theme chosen by the user, stored in the defaults under "theme".
enum ThemeMode: String, CaseIterable {
    case auto, dark, light

    static let defaultsKey = "theme"

    var title: LocalizedStringKey {
        switch self {
        case .auto: "Auto"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    #if os(macOS)
    /// The popover's appearance: `nil` follows macOS.
    var appearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
    }
    #endif

    /// The colour scheme forced on the views: `nil` follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

/// The Glasshouse dashboard's colours (ui.css): pure black or light grey, the foreground at a few opacities.
struct Palette {
    let bg: Color
    /// The background's sRGB components, which a pin's colour must stand out from.
    let bgComponents: IconColor
    private(set) var fg: Color
    /// The edge of anything that can be pressed or typed in (.40; .13 in iOS's light theme).
    private(set) var line: Color
    /// Labels and secondary text (.62).
    let label: Color
    /// Separators (.18).
    let divider: Color
    /// The active state.
    let on: Color
    /// Amber: the key capture only.
    let accent: Color
    /// Blue: the global shortcuts only.
    let global: Color
    /// The face of a button at rest: none, the background shows through, except in iOS's light theme.
    let key: Color
    /// The face of a selected button.
    let keyActive: Color
    /// The width of a selected button's edge.
    let activeLineWidth: CGFloat

    static let dark = Palette(fg: .white, bg: 0x000000, on: Color(hex: 0x30DE61),
                              accent: Color(hex: 0xFFDEA1), global: Color(hex: 0x7FB8FF))
    #if os(macOS)
    static let light = Palette(fg: .black, bg: 0xF5F5F5, on: Color(hex: 0x157F37),
                               accent: Color(hex: 0x8C5E00), global: Color(hex: 0x1F6FD1))
    #else
    /// White keys on a warm grey, a soft edge, the selected one ruled in full
    /// (mockups/2026-11-02-ios/iphone-compact.html).
    static let light = Palette(fg: Color(hex: 0x111111), bg: 0xECECEA, on: Color(hex: 0x157F37),
                               accent: Color(hex: 0x8C5E00), global: Color(hex: 0x1F6FD1),
                               line: 0.13, label: 0.55, divider: 0.10,
                               key: .white, keyActive: .white, activeLineWidth: 1.5)
    #endif

    static func of(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }

    /// `line`, `label`, `divider`: the foreground's opacity for each. `keyActive`: by default the
    /// foreground at .10.
    private init(fg: Color, bg: UInt32, on: Color, accent: Color, global: Color,
                 line: Double = 0.40, label: Double = 0.62, divider: Double = 0.18,
                 key: Color = .clear, keyActive: Color? = nil, activeLineWidth: CGFloat = 1) {
        self.bg = Color(hex: bg)
        bgComponents = IconColor(hex: bg)
        self.fg = fg
        self.line = fg.opacity(line)
        self.label = fg.opacity(label)
        self.divider = fg.opacity(divider)
        self.on = on
        self.accent = accent
        self.global = global
        self.key = key
        self.keyActive = keyActive ?? fg.opacity(0.10)
        self.activeLineWidth = activeLineWidth
    }

    /// For a button awaiting its key: its text and edge in amber.
    var awaitingKey: Palette {
        var palette = self
        palette.fg = accent
        palette.line = accent
        return palette
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension IconColor {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension EnvironmentValues {
    @Entry var palette: Palette = .dark
}

extension Font {
    /// Manrope, bundled (OFL). Fixed size: the window has a fixed width. The sizes are the Mac's,
    /// scaled on iOS by `Metrics.fontScale`.
    static func manrope(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Manrope", fixedSize: size * Metrics.fontScale).weight(weight)
    }

    #if os(iOS)
    /// Manrope at a size in the phone's points, unscaled: the iOS screens drawn in points
    /// (mockups/2026-11-02-ios/iphone-compact.html).
    static func manrope(points size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Manrope", fixedSize: size).weight(weight)
    }
    #endif
}

/// Type sizes and tracking shared by the views (mockups/remote-v2.html). On iOS, the same design
/// at the size of a phone held in the hand (mockups/2026-11-02-ios/iphone-structure.html).
enum Metrics {
    static let width: CGFloat = 328
    #if os(macOS)
    static let gutter: CGFloat = 18
    /// The factor of every Manrope size and tracking.
    static let fontScale: CGFloat = 1
    /// A dashboard button's height.
    static let buttonHeight: CGFloat = 34
    /// The least height of anything pressed.
    static let minTouch: CGFloat = 0
    /// A text field's height.
    static let fieldHeight: CGFloat = 30
    #else
    static let gutter: CGFloat = 20
    static let fontScale: CGFloat = 1.25
    static let buttonHeight: CGFloat = 44
    static let minTouch: CGFloat = 44
    static let fieldHeight: CGFloat = 44
    #endif
    /// Section labels: 9.5 pt capitals, tracking .14 em.
    static let labelSize: CGFloat = 9.5
    static let labelTracking: CGFloat = 1.3 * fontScale
}

#if os(iOS)
/// The one strength of Pane's taps under the finger (a command sent, a pin added or moved): tuned
/// here only.
enum Haptics {
    static let tap: SensoryFeedback = .impact(weight: .medium)
}
#endif
