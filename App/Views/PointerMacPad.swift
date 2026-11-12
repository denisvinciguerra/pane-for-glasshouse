import AppKit
import PaneKit
import SwiftUI

/// Mouse and trackpad input: drag moves, a press without movement clicks, the wheel scrolls.
struct PointerMacPad: NSViewRepresentable {
    let controller: PointerController

    func makeNSView(context: Context) -> PointerMacView { PointerMacView(controller: controller) }
    func updateNSView(_ view: PointerMacView, context: Context) {}
}

final class PointerMacView: NSView {
    private let controller: PointerController
    private var moved = false
    private var moveCarry = CGPoint.zero
    private var scrollCarry = CGPoint.zero

    init(controller: PointerController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        moved = false
        moveCarry = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        moveCarry.x += event.deltaX * 1.5
        moveCarry.y += event.deltaY * 1.5
        let dx = Int(moveCarry.x)
        let dy = Int(moveCarry.y)
        moveCarry.x -= CGFloat(dx)
        moveCarry.y -= CGFloat(dy)
        if dx != 0 || dy != 0 {
            moved = true
            controller.move(dx: dx, dy: dy)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !moved { controller.click() }
    }

    override func scrollWheel(with event: NSEvent) {
        scrollCarry.x += event.scrollingDeltaX / 4
        scrollCarry.y += event.scrollingDeltaY / 4
        let dx = Int(scrollCarry.x)
        let dy = Int(scrollCarry.y)
        scrollCarry.x -= CGFloat(dx)
        scrollCarry.y -= CGFloat(dy)
        if dx != 0 || dy != 0 { controller.scroll(dx: dx, dy: dy) }
    }
}
