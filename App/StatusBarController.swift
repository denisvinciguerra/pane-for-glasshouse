import AppKit
import Observation
import PaneKit
import SwiftUI

/// The menu-bar icon and its popover. A click opens the popover; a right-click shows the
/// menu: the TVs (the active one ticked), the preferences, the update check, quitting.
@MainActor final class StatusBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    /// The keyboard while the popover is open.
    let keyboard: KeyboardController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    init(model: AppModel) {
        self.model = model
        keyboard = KeyboardController(model: model)
        super.init()
        let hosting = NSHostingController(rootView: PopoverRoot(model: model, keyboard: keyboard))
        // The popover takes the SwiftUI content's size: 328 pt wide, as tall as the tab needs.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: Metrics.width, height: 400)
        popover.behavior = .transient
        popover.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        follow()
    }

    // MARK: Icon and appearance

    /// Applies the power state and the theme now, and again each time either changes.
    private func follow() {
        withObservationTracking {
            apply(power: model.session?.power, theme: model.theme, updateAvailable: model.updates.available != nil)
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }

    private func apply(power: PowerState?, theme: ThemeMode, updateAvailable: Bool) {
        let name = power == .on ? "tv.fill" : "tv"
        // VoiceOver does not see the dot: the label says it.
        let label = updateAvailable ? String(localized: "Pane for Glasshouse, update available")
                                    : String(localized: "Pane for Glasshouse")
        var image = NSImage(systemSymbolName: name, accessibilityDescription: label)
        if updateAvailable, let symbol = image { image = Self.withDot(symbol) }
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.setAccessibilityTitle(label)
        popover.appearance = theme.appearance
    }

    /// The symbol with a filled 4 pt disc in its top right corner, drawn in the same template image.
    /// A ring around the disc is cleared first, so the dot stands out from the outline and from the
    /// solid body of `tv.fill`. The canvas grows by 2 pt on every side to leave the disc room; the
    /// symbol stays centred where it was, and the item's height is the button's, not the image's.
    private static func withDot(_ symbol: NSImage) -> NSImage {
        let margin: CGFloat = 2
        let size = NSSize(width: symbol.size.width + 2 * margin, height: symbol.size.height + 2 * margin)
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: NSRect(origin: NSPoint(x: margin, y: margin), size: symbol.size))
            let dot = NSRect(x: rect.maxX - 4, y: rect.maxY - 4, width: 4, height: 4)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.accessibilityDescription = symbol.accessibilityDescription
        return image
    }

    // MARK: Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            show()
        }
    }

    func show() {
        guard let button = statusItem.button else { return }
        // An agent app must be active for the popover to take the keyboard.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Closes the popover, so that a window opened from it is not left under it.
    func close() {
        popover.performClose(nil)
    }

    #if DEBUG
    /// Shows the popover and keeps it up: launched from a terminal the app is not made active,
    /// and a transient popover closes as soon as it loses the key window.
    func showForScreenshot() {
        popover.behavior = .applicationDefined
        show()
    }

    /// Draws the popover's content at twice its size into a PNG at `path`, whatever the screen's
    /// scale, then quits (-PaneSnapshot).
    func snapshot(to path: String) async {
        guard let view = popover.contentViewController?.view, let root = view.layer else { return }
        // SwiftUI's drawn layers (the text) are drawn again at 2x; its image layers keep their image.
        func sharpen(_ layer: CALayer) {
            if !String(describing: type(of: layer)).contains("ImageLayer") {
                layer.contentsScale = 2
                layer.setNeedsDisplay()
            }
            layer.sublayers?.forEach(sharpen)
        }
        sharpen(root)
        view.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(300))
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        NSApp.terminate(nil)
    }
    #endif

    private func showMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        menu.autoenablesItems = false
        for tv in model.store.tvs {
            let item = NSMenuItem(title: tv.name, action: #selector(activateTV(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tv.id
            item.state = model.store.activeID == tv.id ? .on : .off
            menu.addItem(item)
        }
        if !model.store.tvs.isEmpty { menu.addItem(.separator()) }
        let settings = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openPreferences(_:)),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let update = NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(checkForUpdates(_:)),
                                keyEquivalent: "")
        update.target = self
        update.isEnabled = model.updates.canCheck
        menu.addItem(update)
        menu.addItem(NSMenuItem(title: String(localized: "Quit"), action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func activateTV(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { model.activate(id) }
    }

    @objc private func checkForUpdates(_ sender: NSMenuItem) {
        model.updates.checkNow()
    }

    @objc private func openPreferences(_ sender: NSMenuItem) {
        model.openPreferences(nil)
    }

    // MARK: NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        model.isOpen = true
        model.restartPolling()
        if let window = popover.contentViewController?.view.window { keyboard.attach(to: window) }
    }

    func popoverDidClose(_ notification: Notification) {
        model.isOpen = false
        keyboard.detach()
    }
}
