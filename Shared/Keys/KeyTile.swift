import PaneKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension View {
    /// A button that can carry a key: its tiles while the keys show, its edge while it is the one
    /// chosen, and, on the Mac, the area a right-click finds it by.
    func keyed(_ id: ButtonID) -> some View {
        modifier(Keyed(id: id))
    }
}

private struct Keyed: ViewModifier {
    let id: ButtonID
    @Environment(\.keyboard) private var keyboard
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let awaiting = keyboard?.state.mode == .capturing(id)
        let chosen = keyboard?.state.selected == id
        content
            .environment(\.palette, awaiting ? palette.awaitingKey : palette)
            .background(awaiting ? palette.accent.opacity(0.08) : chosen ? palette.fg.opacity(0.08) : .clear)
            // The button chosen in the keys shown: a white edge (amber while it awaits its key), drawn
            // over its own, which a pin's coloured tile may not have.
            .overlay {
                if chosen {
                    Rectangle().strokeBorder(awaiting ? palette.accent : palette.fg, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            // Its key in the top right corner and, in blue on its left, its global shortcut when it has
            // one or awaits one: nothing sticks out under the button, onto the key of the one below.
            .overlay(alignment: .topTrailing) {
                if keyboard?.state.showsTiles == true {
                    HStack(spacing: 2) {
                        #if os(macOS)
                        let awaitingGlobal = keyboard?.state.mode == .capturingGlobal(id)
                        if let global = awaitingGlobal ? "?" : keyboard?.globalLabel(for: id) {
                            KeyTile(text: global, fill: palette.global, ring: awaitingGlobal)
                        }
                        #endif
                        KeyTile(text: awaiting ? "?" : keyboard?.label(for: id), amber: awaiting)
                    }
                    .offset(x: 5, y: -6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            #if os(macOS)
            .background(KeyAreaView(id: id).allowsHitTesting(false).accessibilityHidden(true))
            #endif
    }
}

/// The small inverted tile in a button's top right corner: its key, a dashed "·" without one,
/// an amber "?" while it awaits one. With `fill`, that colour under the text (the global shortcut),
/// ringed with it while the button awaits its shortcut.
private struct KeyTile: View {
    let text: String?
    var amber = false
    var fill: Color?
    var ring = false
    @Environment(\.palette) private var palette

    var body: some View {
        Text(verbatim: text ?? "·")
            .font(.manrope(8.5, .semibold))
            .textCase(nil)
            .tracking(0)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 3)
            .frame(minWidth: 14, minHeight: 14, maxHeight: 14)
            .foregroundStyle(text == nil ? palette.fg.opacity(0.5) : palette.bg)
            .background(amber ? palette.accent : fill ?? (text == nil ? palette.bg : palette.fg))
            .overlay {
                if text == nil {
                    Rectangle().strokeBorder(palette.fg.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            .background {
                if ring, let fill { Rectangle().fill(fill.opacity(0.35)).padding(-2) }
            }
    }
}

#if os(macOS)
/// An empty AppKit view under a keyed button, where it is in the window: the keyboard controller's
/// monitor looks for the one under a right-click, as SwiftUI has no right-click gesture. It takes no
/// click itself.
final class KeyArea: NSView {
    var id: ButtonID?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The button whose area holds the point, in window coordinates, among the views under `root`.
    static func button(at point: NSPoint, in root: NSView) -> ButtonID? {
        if let area = root as? KeyArea, let id = area.id, !area.isHiddenOrHasHiddenAncestor,
           area.convert(area.bounds, to: nil).contains(point) {
            return id
        }
        for view in root.subviews.reversed() {
            if let id = button(at: point, in: view) { return id }
        }
        return nil
    }
}

private struct KeyAreaView: NSViewRepresentable {
    let id: ButtonID

    func makeNSView(context: Context) -> KeyArea { KeyArea() }

    func updateNSView(_ view: KeyArea, context: Context) { view.id = id }
}
#endif

/// A row's key or shortcut on its colour, or a dashed "none" without one.
struct Chip: View {
    let text: String?
    let fill: Color
    let none: LocalizedStringKey
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if let text {
                Text(verbatim: text)
                    .fontWeight(.bold)
                    .foregroundStyle(palette.bg)
            } else {
                Text(none)
                    .foregroundStyle(palette.label)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 5)
        .frame(minWidth: 26, minHeight: 20, maxHeight: 20)
        .background(text == nil ? .clear : fill)
        .overlay {
            if text == nil {
                Rectangle().strokeBorder(palette.label, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
    }
}
