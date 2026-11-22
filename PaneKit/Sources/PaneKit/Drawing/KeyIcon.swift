import CoreGraphics

/// The icons drawn on the remote's keys, on a 24 × 24 grid, stroked at `strokeWidth`.
/// Most paths are Glasshouse 0.157's; `stop`, `pointer`, `dpad` and the mute cross are Pane's.
public enum KeyIcon: String, CaseIterable, Sendable {
    case back, home, settings, pointer, dpad
    case rewind, playPause, stop, fastForward
    case volumeDown, volumeUp, mute
    case up, down, left, right
    case power

    public static let grid: CGFloat = 24
    public static let strokeWidth: CGFloat = 1.6

    /// The arrow icon for a directional key.
    public init(arrow: RemoteKey) {
        switch arrow {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        default: preconditionFailure("\(arrow) is not a directional key")
        }
    }

    /// The icon's outline, built once per icon and cached.
    public var path: CGPath { Self.paths[self]! }

    // CGPath is not Sendable, but the cache is written once at first use and never mutated.
    private nonisolated(unsafe) static let paths: [KeyIcon: CGPath] =
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, build($0)) })

    private static func build(_ icon: KeyIcon) -> CGPath {
        let path = CGMutablePath()
        for d in subpaths(icon) {
            // A malformed path string is a programming error; the tests parse every icon.
            path.addPath(try! SVGPath.path(d))
        }
        switch icon {
        case .settings:
            path.addEllipse(in: CGRect(x: 9.2, y: 9.2, width: 5.6, height: 5.6))
        case .dpad:
            path.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
        case .stop:
            path.addRoundedRect(in: CGRect(x: 6.5, y: 6.5, width: 11, height: 11), cornerWidth: 1.2, cornerHeight: 1.2)
        default:
            break
        }
        return path.copy()!
    }

    /// The SVG path strings of an icon, without its circles and rounded rectangle.
    private static func subpaths(_ icon: KeyIcon) -> [String] {
        switch icon {
        case .back:
            return ["M9 14L4 9l5-5", "M4 9h10a6 6 0 0 1 0 12h-3"]
        case .home:
            return ["M4 11l8-7 8 7", "M6 10v10h12V10"]
        case .settings:
            return ["M18.10 9.48 L20.89 10.59 L20.89 13.41 L18.10 14.52 L18.09 14.54 L19.28 17.29 L17.29 19.28 L14.54 18.09 L14.52 18.10 L13.41 20.89 L10.59 20.89 L9.48 18.10 L9.46 18.09 L6.71 19.28 L4.72 17.29 L5.91 14.54 L5.90 14.52 L3.11 13.41 L3.11 10.59 L5.90 9.48 L5.91 9.46 L4.72 6.71 L6.71 4.72 L9.46 5.91 L9.48 5.90 L10.59 3.11 L13.41 3.11 L14.52 5.90 L14.54 5.91 L17.29 4.72 L19.28 6.71 L18.09 9.46Z"]
        case .pointer:
            return ["M6.5 3.5l11 10.2-5.2.4 3 5.4-2.4 1.3-3-5.4-3.4 3.7z"]
        case .dpad:
            // The ring's chevrons around its OK disc (mockups/2026-11-22-icone-anneau, variant D).
            return ["M9.4 6L12 4l2.6 2", "M9.4 18l2.6 2 2.6-2", "M6 9.4L4 12l2 2.6", "M18 9.4l2 2.6-2 2.6"]
        case .rewind:
            return ["M12 6l-7 6 7 6z", "M20 6l-7 6 7 6z"]
        case .playPause:
            return ["M7 5v14l7-7z", "M16 6v12M20 6v12"]
        case .stop:
            return []
        case .fastForward:
            return ["M4 6l7 6-7 6z", "M12 6l7 6-7 6z"]
        case .volumeDown:
            return ["M6 12h12"]
        case .volumeUp:
            return ["M12 6v12M6 12h12"]
        case .mute:
            return ["M5 9h3l5-4v14l-5-4H5z", "M17 10l4 4M21 10l-4 4"]
        case .up:
            return ["M6 15l6-6 6 6"]
        case .down:
            return ["M6 9l6 6 6-6"]
        case .left:
            return ["M15 6l-6 6 6 6"]
        case .right:
            return ["M9 6l6 6-6 6"]
        case .power:
            return ["M12 3v8", "M6.3 6.3a8 8 0 1 0 11.4 0"]
        }
    }
}
