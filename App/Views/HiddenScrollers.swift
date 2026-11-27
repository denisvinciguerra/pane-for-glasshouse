import AppKit
import SwiftUI

/// Takes the scrollers off the enclosing scroll view, which still scrolls with the wheel and the trackpad.
/// `.scrollIndicators(.hidden)` leaves them on the Apps grid: the legacy scroller with a mouse plugged in,
/// the overlay one while scrolling, and both cover the last column. SwiftUI puts them back when the
/// scroll view changes size (the grid's, when the strip of recent apps comes or goes): they are taken
/// off again as soon as they are.
struct HiddenScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ nsView: ProbeView, context: Context) { nsView.apply() }

    final class ProbeView: NSView {
        /// The scroll view watched, and its scrollers' flags.
        private weak var watched: NSScrollView?
        private var observations: [NSKeyValueObservation] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            // AppKit sets the scrollers up again when a mouse is plugged in or out. A selector
            // observer goes away with the view.
            NotificationCenter.default.removeObserver(self)
            guard window != nil else { observations = []; watched = nil; return }
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
            Self.hide(scrollView)
            guard watched !== scrollView else { return }
            watched = scrollView
            // Not in the setter's call: after whoever set it back is done.
            observations = [
                scrollView.observe(\.hasVerticalScroller) { scrollView, _ in
                    DispatchQueue.main.async { Self.hide(scrollView) }
                },
                scrollView.observe(\.hasHorizontalScroller) { scrollView, _ in
                    DispatchQueue.main.async { Self.hide(scrollView) }
                },
            ]
        }

        private static func hide(_ scrollView: NSScrollView) {
            if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
            if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
        }
    }
}
