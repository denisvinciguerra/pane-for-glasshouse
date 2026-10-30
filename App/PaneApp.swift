import AppKit
import PaneKit
import SwiftUI

@main
struct PaneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                // ⌘, from any of our windows, the editor's sheet included: our preferences window,
                // never this empty scene's.
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.showPreferences() }
                        .keyboardShortcut(",")
                }
            }
    }
}

/// Builds the model, the menu-bar icon and the preferences window at launch; the model polls the
/// TV until quit.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusBar: StatusBarController?
    private var preferences: PreferencesWindowController?
    /// A screenshot argument opens the popover itself.
    private var opensItself = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The language the app started with, before the Language pane can change it.
        _ = LanguageChoice.atLaunch
        #if DEBUG
        let model = Self.debugModel()
        #else
        let model = AppModel(updates: Updates(start: true))
        #endif
        self.model = model
        let statusBar = StatusBarController(model: model)
        self.statusBar = statusBar
        let preferences = PreferencesWindowController(model: model)
        self.preferences = preferences
        model.openPreferences = { [weak preferences, weak statusBar] pane in
            statusBar?.close()
            preferences?.show(pane)
        }
        #if DEBUG
        // Screenshots without clicking the menu bar: -PaneTheme dark|light|auto, -PaneTab remote|…,
        // -PaneOpenOnLaunch YES, and with it -PaneKeys show|edit; -PaneDemoPins YES (two pins) and
        // -PaneEditAction demo (the editor on two steps), both on throwaway actions;
        // -PaneOpenPreferences general|tv|keys|pinned|about (the preferences window on that pane);
        // -PaneFirstLaunch YES (no TV, the welcome screen, all on throwaway defaults and tokens);
        // -PaneUpdates YES (Sparkle starts and contacts the feed; else it stays off);
        // -PaneDemoUpdate 1.0.1 (the update bar and the icon's dot for that version, Sparkle off);
        // -PaneDemoSecondTV YES (with -PaneFirstLaunch: a second TV "Bedroom" at 192.0.2.50, written without a probe; it may become the active TV, which then shows as unreachable).
        let args = UserDefaults.standard
        let firstLaunch = args.bool(forKey: "PaneFirstLaunch")
        opensItself = firstLaunch || args.bool(forKey: "PaneOpenOnLaunch")
        if let theme = args.string(forKey: "PaneTheme").flatMap(ThemeMode.init) { model.theme = theme }
        if let tab = args.string(forKey: "PaneTab").flatMap(PaneTab.init) { model.selectedTab = tab }
        Self.seedDemo(model, pins: args.bool(forKey: "PaneDemoPins"), editor: args.string(forKey: "PaneEditAction") == "demo")
        if opensItself {
            let keys = args.string(forKey: "PaneKeys")
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                statusBar.showForScreenshot()
                if let keys { statusBar.keyboard.enterForScreenshot(keys) }
                if let path = args.string(forKey: "PaneSnapshot") {
                    try? await Task.sleep(for: .seconds(6))
                    await statusBar.snapshot(to: path)
                }
            }
        }
        if let pane = args.string(forKey: "PaneOpenPreferences").flatMap(PreferencesPane.init) {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                preferences.showForScreenshot(pane)
            }
        }
        #endif
        // First launch: without a TV the popover opens by itself.
        if model.store.tvs.isEmpty && !opensItself {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                statusBar.show()
            }
        }
    }

    #if DEBUG
    private static let demoSuite = "fr.synlink.pane.demo"

    /// The model: on throwaway defaults and in-memory tokens under -PaneFirstLaunch (keys, actions,
    /// theme and TVs never touch the real settings or the keychain), else the real one.
    private static func debugModel() -> AppModel {
        let args = UserDefaults.standard
        // Sparkle stays off, and the feed untouched, unless -PaneUpdates YES.
        let updates = Updates(start: args.bool(forKey: "PaneUpdates"))
        if let version = args.string(forKey: "PaneDemoUpdate") { updates.demo(version: version) }
        if args.bool(forKey: "PaneFirstLaunch"), let demo = UserDefaults(suiteName: demoSuite) {
            demo.removePersistentDomain(forName: demoSuite)
            let store = TVConfigStore(defaults: demo, secrets: EphemeralSecretStore())
            if args.bool(forKey: "PaneDemoSecondTV") {
                store.upsert(TVConfig(name: "Bedroom", host: "192.0.2.50"), token: nil)
            }
            return AppModel(updates: updates, store: store,
                            defaults: demo, actions: ActionStore(defaults: demo))
        }
        return AppModel(updates: updates, actions: demoActions())
    }

    /// For -PaneDemoPins or -PaneEditAction: the actions in their own defaults, emptied at each
    /// launch, so the screenshots leave nothing in the real settings.
    private static func demoActions() -> ActionStore? {
        let args = UserDefaults.standard
        guard args.bool(forKey: "PaneDemoPins") || args.string(forKey: "PaneEditAction") != nil,
              let defaults = UserDefaults(suiteName: demoSuite) else { return nil }
        defaults.removePersistentDomain(forName: demoSuite)
        return ActionStore(defaults: defaults)
    }

    /// Six pins (three apps shown as their icons, an input with a setting, the screen, the sleep
    /// timer) and an action of two steps open in the editor, for the active TV.
    private static func seedDemo(_ model: AppModel, pins: Bool, editor: Bool) {
        guard let tv = model.store.activeID else { return }
        let game = ActionStep.setting(id: "gameOptimization", section: "game", title: "VRR & G-Sync",
                                      value: .bool(true), valueLabel: "ON")
        if pins {
            let demo: [(String?, [ActionStep])] = [
                (nil, [.launchApp(id: "com.apple.appletv", title: "Apple TV")]),
                (nil, [.launchApp(id: "netflix", title: "Netflix")]),
                (nil, [.launchApp(id: "spotify-beehive", title: "Spotify")]),
                ("PS5 + Game", [.button(.source("hdmi4")), game]),
                (nil, [.screenOff]),
                (nil, [.sleepTimer("30")]),
            ]
            for (title, steps) in demo {
                let action = CustomAction(title: title ?? CustomAction.defaultTitle(steps, sources: []), steps: steps)
                model.actions.save(action, for: tv)
                model.actions.pin(action.id, for: tv)
            }
        }
        if editor {
            let action = CustomAction(title: "PS5 + Game", steps: [.button(.source("hdmi4")), game])
            model.actions.save(action, for: tv)
            model.edit(action)
        }
    }
    #endif

    /// The preferences window in front, on the pane it shows.
    func showPreferences() {
        preferences?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }
}

#if DEBUG
/// Tokens in memory only, for the throwaway first-launch mode.
final class EphemeralSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [UUID: String] = [:]

    func token(for id: UUID) -> String? {
        lock.lock(); defer { lock.unlock() }
        return tokens[id]
    }

    func setToken(_ token: String?, for id: UUID) {
        lock.lock(); defer { lock.unlock() }
        tokens[id] = token
    }
}
#endif
