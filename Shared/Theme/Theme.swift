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
    /// The foreground's opacity in `line` (.16; .13 in iOS's light theme), for an edge drawn a
    /// set amount stronger than the keys' (OK's on the ring).
    private(set) var lineOpacity: Double
    /// The foreground's opacity in `ink`.
    private var inkOpacity = 0.86
    /// Labels and secondary text (.62).
    let label: Color
    /// Separators (.18).
    let divider: Color
    /// The edge of the small framed things that are not keys (the HDR badge, the ⌥ of the pointer's
    /// help), at the strength `line` had before the keys' edge softened (.40; .13 in iOS's light theme).
    let frame: Color
    /// The active state.
    let on: Color
    /// Amber: the key capture only.
    let accent: Color
    /// Blue: the global shortcuts only.
    let global: Color
    /// The face of a button at rest: none, the background shows through, except in iOS's light theme.
    private(set) var key: Color
    /// The face of a selected button.
    let keyActive: Color
    /// The width of a selected button's edge.
    let activeLineWidth: CGFloat
    /// The edge of the key that swaps the d-pad and the pointer, which stands out from its row (.90;
    /// .40 in iOS's light theme, whose keys are white with a soft edge; mockups/2026-11-21-bascule).
    private let swapLineOpacity: Double

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
                               line: 0.13, label: 0.55, divider: 0.10, frame: 0.13,
                               key: .white, keyActive: .white, activeLineWidth: 1.5, swapLine: 0.40)
    #endif

    static func of(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }

    /// `line`, `label`, `divider`, `frame`: the foreground's opacity for each. `keyActive`: by default
    /// the foreground at .10.
    private init(fg: Color, bg: UInt32, on: Color, accent: Color, global: Color,
                 line: Double = 0.16, label: Double = 0.62, divider: Double = 0.18, frame: Double = 0.40,
                 key: Color = .clear, keyActive: Color? = nil, activeLineWidth: CGFloat = 1,
                 swapLine: Double = 0.90) {
        self.bg = Color(hex: bg)
        bgComponents = IconColor(hex: bg)
        self.fg = fg
        lineOpacity = line
        self.label = fg.opacity(label)
        self.divider = fg.opacity(divider)
        self.frame = fg.opacity(frame)
        self.on = on
        self.accent = accent
        self.global = global
        self.key = key
        self.keyActive = keyActive ?? fg.opacity(0.10)
        self.activeLineWidth = activeLineWidth
        swapLineOpacity = swapLine
    }

    /// The edge of anything that can be pressed or typed in.
    var line: Color { fg.opacity(lineOpacity) }
    /// A key's edge under the pointer (.45, as Glasshouse's `button:hover`), never weaker than at rest.
    var lineHover: Color { fg.opacity(max(lineOpacity, 0.45)) }
    /// A key's icon or text at rest (.86); full strength under the pointer, chosen or pressed.
    var ink: Color { fg.opacity(inkOpacity) }
    /// The face of a pressed key (.12).
    var pressed: Color { fg.opacity(0.12) }

    /// For the key that swaps the d-pad and the pointer: its edge drawn stronger.
    var swapKey: Palette {
        var palette = self
        palette.lineOpacity = swapLineOpacity
        return palette
    }

    /// For the ring d-pad's keys: no face of their own, the ring's plate under them is theirs (a face
    /// per part would leave a faint seam between two white parts).
    var ringKeys: Palette {
        var palette = self
        palette.key = .clear
        return palette
    }

    /// For a button awaiting its key: its text and edge in amber, at full strength.
    var awaitingKey: Palette {
        var palette = self
        palette.fg = accent
        palette.lineOpacity = 1
        palette.inkOpacity = 1
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
    /// A key's shape, for its face, its edge, where it is pressed and, on the Mac, right-clicked: a
    /// rounded rectangle, or a part of the ring d-pad.
    @Entry var keyShape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: Metrics.keyRadius))
    /// The point a keyed button's key tiles go a little out of, up and right, in its frame; `nil`, its
    /// top right corner (a ring part's tiles go by its chevron instead).
    @Entry var keyTileAnchor: CGPoint? = nil
    /// Whether the pointer is over a key, told by its container in place of the key's own hover: the
    /// ring's keys share one square, which only the ring can split among them. `nil`, the key's own.
    @Entry var keyHover: Bool? = nil
}

extension Shape {
    /// The shape's edge drawn inside its frame, as `strokeBorder` does, for a shape that cannot be
    /// inset (`AnyShape`).
    func strokeInside(_ content: some ShapeStyle, style: StrokeStyle) -> some View {
        stroke(content, style: style).padding(style.lineWidth / 2)
    }
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

    /// Outfit, bundled (OFL), as Glasshouse has it: names and numbers, as given, never in forced
    /// capitals. `.light` (300) for most, `.thin` (200) for the big titles and numbers. Scaled on iOS
    /// like `manrope`.
    static func outfit(_ size: CGFloat, _ weight: Font.Weight = .light) -> Font {
        .custom("Outfit", fixedSize: size * Metrics.fontScale).weight(weight)
    }

    #if os(iOS)
    /// Outfit at a size in the phone's points, unscaled.
    static func outfit(points size: CGFloat, _ weight: Font.Weight = .light) -> Font {
        .custom("Outfit", fixedSize: size).weight(weight)
    }
    #endif
}

extension String {
    /// The text as Outfit sets it: Outfit has no narrow no-break space (U+202F, the French thousands
    /// separator), which another font would fill in, wide; a no-break space in its place.
    var forOutfit: String { replacingOccurrences(of: "\u{202F}", with: "\u{00A0}") }
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
    /// A key icon's side (mockups/2026-11-20-icones).
    static let keyIcon: CGFloat = 23
    /// A key's corner radius (mockups/2026-11-21-finition, piste C).
    static let keyRadius: CGFloat = 8
    /// The ring d-pad's diameter, and its chevrons' side.
    static let ringDiameter: CGFloat = 170
    static let ringArrowIcon: CGFloat = 25
    /// OK's Outfit size on the ring, in points as drawn (unscaled on iOS: `Font.outfit(points:)`).
    static let okSize: CGFloat = 15
    /// A name's Outfit size on a key over two lines (on iOS, in the phone's points, unscaled).
    static let nameSizeTwoLines: CGFloat = 12.5
    #else
    static let gutter: CGFloat = 20
    static let fontScale: CGFloat = 1.25
    static let buttonHeight: CGFloat = 44
    static let minTouch: CGFloat = 44
    static let fieldHeight: CGFloat = 44
    static let keyIcon: CGFloat = 30
    static let keyRadius: CGFloat = 11
    /// 236 in the mockup, which made the Remote screen of a 390 x 844 iPhone (17e) scroll by 7 pt:
    /// 228 keeps it whole, as the cross had it.
    static let ringDiameter: CGFloat = 228
    static let ringArrowIcon: CGFloat = 32
    static let okSize: CGFloat = 20
    static let nameSizeTwoLines: CGFloat = 14
    #endif
    /// The corner radius of the small things: the HDR badge, the key tiles, the chips.
    static let smallRadius: CGFloat = 2
    /// A name's Outfit size on a key (scaled on iOS by `Font.outfit`).
    static let nameSize: CGFloat = 13.5
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
