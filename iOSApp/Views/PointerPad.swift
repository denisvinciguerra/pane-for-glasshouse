import PaneKit
import SwiftUI
import UIKit

/// The scroll view outside the pad keeps its pan; inside, it waits for the pad's gestures instead.
final class PointerUIView: UIView {
    private var scrollViews: [UIScrollView] = []

    func holdScrolling() {
        var parent = superview
        while let view = parent {
            if let scroll = view as? UIScrollView {
                scrollViews.append(scroll)
                scroll.isScrollEnabled = false
            }
            parent = view.superview
        }
    }

    func restoreScrolling() {
        for scroll in scrollViews { scroll.isScrollEnabled = true }
        scrollViews.removeAll()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        restoreScrolling()
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        restoreScrolling()
        super.touchesCancelled(touches, with: event)
    }

    override func didMoveToWindow() {
        if window == nil { restoreScrolling() }
        super.didMoveToWindow()
    }
}

/// A touch surface with separate one- and two-finger pans: the first moves, the second scrolls.
struct PointerPad: UIViewRepresentable {
    let controller: PointerController

    func makeUIView(context: Context) -> PointerUIView {
        let view = PointerUIView()
        view.isMultipleTouchEnabled = true
        let move = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.moved(_:)))
        move.minimumNumberOfTouches = 1
        move.maximumNumberOfTouches = 1
        move.delegate = context.coordinator
        view.addGestureRecognizer(move)
        let scroll = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.scrolled(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        scroll.delegate = context.coordinator
        view.addGestureRecognizer(scroll)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.require(toFail: scroll)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: PointerUIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let controller: PointerController
        private var moveCarry = CGPoint.zero
        private var scrollCarry = CGPoint.zero

        init(controller: PointerController) { self.controller = controller }

        func gestureRecognizer(_ first: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith second: UIGestureRecognizer) -> Bool { true }

        private func finish(_ gesture: UIGestureRecognizer) {
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                (gesture.view as? PointerUIView)?.restoreScrolling()
            }
        }

        @objc func moved(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                moveCarry = .zero
                (gesture.view as? PointerUIView)?.holdScrolling()
            }
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            moveCarry.x += translation.x * 1.5
            moveCarry.y += translation.y * 1.5
            let dx = Int(moveCarry.x)
            let dy = Int(moveCarry.y)
            moveCarry.x -= CGFloat(dx)
            moveCarry.y -= CGFloat(dy)
            if dx != 0 || dy != 0 { controller.move(dx: dx, dy: dy) }
            finish(gesture)
        }

        @objc func scrolled(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                scrollCarry = .zero
                (gesture.view as? PointerUIView)?.holdScrolling()
            }
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            scrollCarry.x -= translation.x / 4
            scrollCarry.y -= translation.y / 4
            let dx = Int(scrollCarry.x)
            let dy = Int(scrollCarry.y)
            scrollCarry.x -= CGFloat(dx)
            scrollCarry.y -= CGFloat(dy)
            if dx != 0 || dy != 0 { controller.scroll(dx: dx, dy: dy) }
            finish(gesture)
        }

        @objc func tapped() { controller.click() }
    }
}
