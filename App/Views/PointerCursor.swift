import AppKit

/// The Mac's cursor while it drives the TV's pointer. Frozen and hidden once per gesture: `freeze` and
/// `thaw` can be called again without effect, so the system's hide and unhide counts stay balanced.
/// No `deinit` can reach the main actor: the pad thaws it when it goes.
@MainActor final class PointerCursor {
    private var frozen = false
    /// Where the cursor stays during the gesture, in global display coordinates.
    private var heldAt: CGPoint?
    /// Apart from `frozen`: a gesture started with Pane inactive never hid anything.
    private var hidden = false

    /// Stops the cursor, first putting it at the centre of `centreOn` (a screen rect, in AppKit
    /// coordinates) when there is one.
    func freeze(centreOn rect: NSRect?) {
        guard !frozen else { return }
        frozen = true
        heldAt = CGEvent(source: nil)?.location
        if let rect, let primary = NSScreen.screens.first {
            // Global display coordinates start at the top left of the primary screen.
            let centre = CGPoint(x: rect.midX, y: primary.frame.maxY - rect.midY)
            CGWarpMouseCursorPosition(centre)
            heldAt = centre
        }
        CGAssociateMouseAndMouseCursorPosition(0)
        if NSApp.isActive {
            hidden = true
            NSCursor.hide()
        }
    }

    /// The system only disconnects the cursor for the app really in front, which Pane may not be even
    /// when it says it is active (the popover over an app in full screen): a cursor that got away is
    /// put back, or the next click would fall on another app.
    func keepHeld() {
        guard frozen, let heldAt, let now = CGEvent(source: nil)?.location,
              hypot(now.x - heldAt.x, now.y - heldAt.y) > 0.5 else { return }
        CGWarpMouseCursorPosition(heldAt)
    }

    /// Gives the cursor back where it is.
    func thaw() {
        guard frozen else { return }
        frozen = false
        heldAt = nil
        CGAssociateMouseAndMouseCursorPosition(1)
        if hidden {
            hidden = false
            NSCursor.unhide()
        }
    }
}
