import AppKit
import SwiftUI

/// Takes the scrollers off the enclosing scroll view, which still scrolls with the wheel and the trackpad.
/// `.scrollIndicators(.hidden)` leaves them on the Apps grid: the legacy scroller with a mouse plugged in,
/// the overlay one while scrolling, and both cover the last column.
struct HiddenScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ nsView: ProbeView, context: Context) { nsView.apply() }

    final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            // AppKit sets the scrollers up again when a mouse is plugged in or out. A selector
            // observer goes away with the view.
            NotificationCenter.default.removeObserver(self)
            guard window != nil else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(preferredStyleChanged),
                name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil
            )
        }

        @objc private func preferredStyleChanged() {
            // After AppKit's own handler.
            DispatchQueue.main.async { self.apply() }
        }

        func apply() {
            guard let scrollView = enclosingScrollView else { return }
            if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
            if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
        }
    }
}
