import AppKit
import SwiftUI

/// Lets the mouse move the enclosing horizontal scroll view (the Apps tab's strip of recent apps)
/// as a finger would: hold the button and drag it sideways, or turn the wheel over it (a wheel has
/// no other axis). A click that does not move still opens the app under it; a drag opens nothing.
/// A trackpad's sideways swipe keeps scrolling it as usual.
struct DragScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ nsView: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        /// Added while the view is in a window, removed when it leaves it.
        private var monitor: Any?
        /// The press being followed: where it started, and the strip's offset then.
        private var press: (x: CGFloat, origin: CGFloat)?
        private var dragging = false
        /// Where the release of a tile is sent, far from the window: passed on untouched.
        private static let away = NSPoint(x: -10_000, y: -10_000)
        /// A move shorter than this is still a click.
        private static let slop: CGFloat = 4

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            press = nil
            dragging = false
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        /// nil when the event moved the strip, so that nothing else acts on it.
        private func handle(_ event: NSEvent) -> NSEvent? {
            guard event.window === window, let scrollView = enclosingScrollView,
                  event.locationInWindow.x > Self.away.x / 2 else { return event }
            switch event.type {
            case .scrollWheel:
                guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), inside(event, scrollView) else { return event }
                // A wheel's notch is a line; a trackpad's or a Magic Mouse's deltas are already points.
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
                return scroll(scrollView, to: scrollView.contentView.bounds.origin.x - delta) ? nil : event
            case .leftMouseDown:
                press = inside(event, scrollView) ? (event.locationInWindow.x, scrollView.contentView.bounds.origin.x) : nil
                dragging = false
                return event
            case .leftMouseDragged:
                guard let press else { return event }
                let moved = event.locationInWindow.x - press.x
                if !dragging {
                    guard abs(moved) > Self.slop else { return event }
                    dragging = true
                    // The tile under the press lets go, far from it: it neither stays pressed nor opens.
                    if let release = Self.release(like: event) { window?.sendEvent(release) }
                }
                _ = scroll(scrollView, to: press.origin - moved)
                return nil
            case .leftMouseUp:
                defer { press = nil; dragging = false }
                return dragging ? nil : event
            default:
                return event
            }
        }

        private func inside(_ event: NSEvent, _ scrollView: NSScrollView) -> Bool {
            scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil))
        }

        /// Whether there was room to move.
        private func scroll(_ scrollView: NSScrollView, to x: CGFloat) -> Bool {
            guard let document = scrollView.documentView else { return false }
            let clip = scrollView.contentView
            let room = document.frame.width - clip.bounds.width
            guard room > 0 else { return false }
            clip.scroll(to: NSPoint(x: min(max(x, 0), room), y: clip.bounds.origin.y))
            scrollView.reflectScrolledClipView(clip)
            return true
        }

        /// A button release outside the window, at the time of `event`.
        private static func release(like event: NSEvent) -> NSEvent? {
            NSEvent.mouseEvent(with: .leftMouseUp, location: away,
                               modifierFlags: event.modifierFlags, timestamp: event.timestamp,
                               windowNumber: event.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: 0)
        }
    }
}
