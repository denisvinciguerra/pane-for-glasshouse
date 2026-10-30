import AppKit
import SwiftUI

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

    /// The popover's appearance: `nil` follows macOS.
    var appearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
    }
}

/// The Glasshouse dashboard's colours (ui.css): pure black or light grey, the foreground at a few opacities.
struct Palette {
    let bg: Color
    private(set) var fg: Color
    /// The edge of anything that can be pressed or typed in (.40).
    private(set) var line: Color
    /// Labels and secondary text (.62).
    let label: Color
    /// Separators (.18).
    let divider: Color
    /// The active state.
    let on: Color
    /// Amber: the edit mode and the key capture only.
    let accent: Color

    static let dark = Palette(fg: .white, bg: Color(red: 0, green: 0, blue: 0), on: Color(hex: 0x30DE61),
                              accent: Color(hex: 0xFFDEA1))
    static let light = Palette(fg: .black, bg: Color(hex: 0xF5F5F5), on: Color(hex: 0x157F37),
                               accent: Color(hex: 0x8C5E00))

    static func of(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }

    private init(fg: Color, bg: Color, on: Color, accent: Color) {
        self.bg = bg
        self.fg = fg
        self.line = fg.opacity(0.40)
        self.label = fg.opacity(0.62)
        self.divider = fg.opacity(0.18)
        self.on = on
        self.accent = accent
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

extension EnvironmentValues {
    @Entry var palette: Palette = .dark
}

extension Font {
    /// Manrope, bundled (OFL). Fixed size: the window has a fixed width.
    static func manrope(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Manrope", fixedSize: size).weight(weight)
    }
}

/// Type sizes and tracking shared by the views (mockups/remote-v2.html).
enum Metrics {
    static let width: CGFloat = 328
    static let gutter: CGFloat = 18
    /// Section labels: 9.5 pt capitals, tracking .14 em.
    static let labelSize: CGFloat = 9.5
    static let labelTracking: CGFloat = 1.3
}
