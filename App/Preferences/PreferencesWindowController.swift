import AppKit
import Carbon.HIToolbox
import Observation
import PaneKit
import SwiftUI

/// The preferences window: our own `NSWindow`, not SwiftUI's `Settings` scene, which an agent app
/// does not open reliably. One window, kept when closed; it follows the theme.
@MainActor final class PreferencesWindowController {
    private let model: AppModel
    private let context = PreferencesContext()
    private lazy var window: NSWindow = makeWindow()
    private var layoutObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
    }

    /// Activates the app and brings the window to the front, on this pane (nil: the one it shows).
    func show(_ pane: PreferencesPane? = nil) {
        if let pane { context.pane = pane }
        context.layout = CurrentKeyboardLayout()
        let window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    #if DEBUG
    /// Launched from a terminal the app is not made active: the window is put in front all the same.
    func showForScreenshot(_ pane: PreferencesPane) {
        show(pane)
        window.orderFrontRegardless()
    }
    #endif

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: PreferencesView.size),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = String(localized: "Pane for Glasshouse Settings")
        window.isReleasedWhenClosed = false
        // The title bar takes the popover's background too.
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? .black : NSColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255, alpha: 1)
        }
        let hosting = NSHostingController(rootView: PreferencesView(model: model, context: context))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(PreferencesView.size)
        window.center()
        follow(window)
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.context.closings += 1 }
        }
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.context.layout = CurrentKeyboardLayout() }
        }
        return window
    }

    /// Applies the theme now, and again each time it changes.
    private func follow(_ window: NSWindow) {
        withObservationTracking {
            window.appearance = model.theme.appearance
        } onChange: { [weak self, weak window] in
            Task { @MainActor in if let self, let window { self.follow(window) } }
        }
    }
}
