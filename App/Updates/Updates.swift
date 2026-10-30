import Observation
import Sparkle
import UserNotifications

/// The updates, through Sparkle: it checks once a day by itself and says in the popover when a
/// version is out, instead of opening its own window while the user is elsewhere.
@MainActor @Observable final class Updates: NSObject {
    /// The short version Sparkle found and nobody has looked at yet, `nil` otherwise.
    private(set) var available: String?
    /// Whether the bar announcing it was closed.
    private(set) var barDismissed = false
    /// Whether Sparkle checks by itself (its own setting, kept in the defaults).
    var automaticallyChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
    /// False while a check or an install is under way.
    private(set) var canCheck = false

    // Sparkle keeps its delegates from init, when `self` is not ready: the controller comes after.
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    /// `start`: whether Sparkle starts, and so contacts the feed.
    init(start: Bool) {
        automaticallyChecks = false
        super.init()
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let can = change.newValue ?? false
            Task { @MainActor in self?.canCheck = can }
        }
        // The delegate from the start: a click on a notification may be what launched the app.
        UNUserNotificationCenter.current().delegate = self
        if start { controller.startUpdater() }
    }

    /// A check with Sparkle's own window.
    func checkNow() {
        #if DEBUG
        if demoing { return }
        #endif
        controller?.checkForUpdates(nil)
    }

    func dismissBar() {
        barDismissed = true
    }

    /// The system notification: asks for the permission (once; the system remembers the answer)
    /// and posts only if it was given. Refused, the dot and the bar still say it.
    private func notify(version: String) {
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Update available")
            content.body = String(localized: "Pane for Glasshouse \(version) is ready to install.")
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "update", content: content, trigger: nil))
        }
    }

    #if DEBUG
    @ObservationIgnored private var demoing = false

    /// For -PaneDemoUpdate: the bar and the dot, without Sparkle and without a notification.
    func demo(version: String) {
        demoing = true
        available = version
    }
    #endif
}

extension Updates: UNUserNotificationCenterDelegate {
    /// A click on the notification opens Sparkle's window.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in checkNow() }
        completionHandler()
    }

    /// Shown even when Pane is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(.banner)
    }
}

extension Updates: SPUUpdaterDelegate {
    /// `PaneFeedURL` in the defaults replaces the feed; without it, `SUFeedURL`.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "PaneFeedURL")
    }
}

extension Updates: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// A scheduled update shows its window only if the user is looking at the app; else the popover says it.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            available = version
            barDismissed = false
            notify(version: version)
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { available = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { available = nil }
    }
}
