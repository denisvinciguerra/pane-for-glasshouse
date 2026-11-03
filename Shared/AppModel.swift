import Observation
import PaneKit
import SwiftUI

/// The app's state: the TVs, the session with the active one, the visible tab, the theme, the
/// keys and the custom actions. It owns the session's polling task, from launch to quit.
@MainActor @Observable final class AppModel {
    let store: TVConfigStore
    /// The keys of Remote's buttons and of the sources, shared by every TV.
    let keymap: KeymapStore
    /// The custom actions, their keys and the pins, per TV.
    let actions: ActionStore
    /// The icons of the apps the pins launch, kept in the app's caches; in memory only during the
    /// demo, whose placeholder icons must not replace the real ones.
    private(set) var icons: AppIconStore
    #if os(macOS)
    /// The updates, through Sparkle.
    let updates: Updates
    /// The global shortcuts, registered with the system.
    let hotKeys = GlobalHotKeys()
    #endif
    private(set) var session: TVSession?
    /// The active TV's client, for the dashboard links.
    private(set) var client: GlasshouseClient?
    var selectedTab: PaneTab = .remote
    /// The action open in the popover's editor, which then takes the place of the tab bar and the tab.
    var editingAction: CustomAction?
    /// Whether the popover is shown: the session polls every 2 s then, every 30 s otherwise. On iOS,
    /// whether the app is in the foreground.
    var isOpen = false
    /// The demo TV while the demo runs: in memory only, never in `store`, served by `DemoTV`. It
    /// takes the place of the active TV meanwhile.
    private(set) var demo: TVConfig?
    var isDemo: Bool { demo != nil }
    #if os(macOS)
    /// Whether a recorder of global shortcuts is listening: the shortcuts are suspended meanwhile,
    /// so that a combination Pane holds reaches the recorder.
    var keyRecorderActive = false
    #else
    /// The active TV stopped answering, and it has a token (never searched for on iOS: nothing proves
    /// which host has its MAC), it cannot be searched for (no MAC known, saved off the local
    /// network) or the search by its MAC ended without it: Remote offers to find it by hand.
    /// Cleared once it answers or has a new session.
    private(set) var lostTV: UUID?
    /// Counts the commands sent from the screen, for their haptic feedback.
    private(set) var commandsSent = 0
    /// Counts the returns to the foreground, from the background as from an alert: the searches on
    /// screen start again then if the system refused them or they found nothing.
    private(set) var foregroundReturns = 0
    @ObservationIgnored private var launched = false
    #endif
    var theme: ThemeMode {
        didSet { defaults.set(theme.rawValue, forKey: ThemeMode.defaultsKey) }
    }
    /// Whether an action turns the TV on even during panel maintenance, which it then interrupts.
    var powersOnDuringMaintenance: Bool {
        didSet {
            defaults.set(powersOnDuringMaintenance, forKey: Self.maintenanceKey)
            session?.powersOnDuringMaintenance = powersOnDuringMaintenance
        }
    }

    #if os(macOS)
    /// Opens the preferences window on a pane (set by the app delegate).
    /// `nil`: the pane it showed last.
    @ObservationIgnored var openPreferences: (PreferencesPane?) -> Void = { _ in }
    #endif
    /// The search for TVs on the network and the check of one address, for the add screen.
    @ObservationIgnored let discovery: Discovery
    @ObservationIgnored let probe = TVProbe(makeDetailAPI: { GlasshouseClient(endpoint: $0, timeout: Discovery.detailTimeout) })

    private static let maintenanceKey = "powerOnDuringMaintenance"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var runTask: Task<Void, Never>?
    /// The app is in the background (iOS): no polling until it comes back.
    @ObservationIgnored private var paused = false
    /// The demo's server, kept for the demo's length so its state survives a new session.
    @ObservationIgnored private var demoAPI: DemoTV?
    @ObservationIgnored private var throttle = RelocationThrottle()
    @ObservationIgnored private var relocateTasks: [UUID: Task<Void, Never>] = [:]
    /// Finds a lost TV again by its MAC.
    @ObservationIgnored private let relocator: Relocator

    #if os(macOS)
    /// `actions` and `keymap`: the stores of the custom actions and of the keys, by default in `defaults`.
    init(updates: Updates, store: TVConfigStore = TVConfigStore(), defaults: UserDefaults = .standard,
         actions: ActionStore? = nil, keymap: KeymapStore? = nil, relocator: Relocator = Relocator()) {
        self.updates = updates
        self.store = store
        self.defaults = defaults
        self.keymap = keymap ?? KeymapStore(defaults: defaults)
        self.actions = actions ?? ActionStore(defaults: defaults)
        self.relocator = relocator
        discovery = Discovery()
        icons = AppIconStore(directory: Self.iconsDirectory)
        theme = defaults.string(forKey: ThemeMode.defaultsKey).flatMap(ThemeMode.init) ?? .auto
        powersOnDuringMaintenance = defaults.bool(forKey: Self.maintenanceKey)
        startSession()
    }
    #else
    /// `actions` and `keymap`: the stores of the custom actions and of the keys, by default in `defaults`.
    init(store: TVConfigStore = TVConfigStore(), defaults: UserDefaults = .standard,
         actions: ActionStore? = nil, keymap: KeymapStore? = nil, relocator: Relocator = Relocator(),
         discovery: Discovery = Discovery()) {
        self.store = store
        self.defaults = defaults
        self.keymap = keymap ?? KeymapStore(defaults: defaults)
        self.actions = actions ?? ActionStore(defaults: defaults)
        self.relocator = relocator
        self.discovery = discovery
        icons = AppIconStore(directory: Self.iconsDirectory)
        theme = defaults.string(forKey: ThemeMode.defaultsKey).flatMap(ThemeMode.init) ?? .auto
        powersOnDuringMaintenance = defaults.bool(forKey: Self.maintenanceKey)
        // The pins of a demo the app quit during.
        self.actions.forget(tv: Self.demoID)
        // No polling before the app is in the foreground: `resume()`.
        paused = true
        startSession()
    }
    #endif

    /// `~/Library/Caches/<bundle ID>/AppIcons`.
    private static var iconsDirectory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let bundle = Bundle.main.bundleIdentifier else { return nil }
        return caches.appendingPathComponent(bundle).appendingPathComponent("AppIcons")
    }

    // MARK: TVs

    /// The id of the TV the session talks to: the demo's while it runs, else the store's active one.
    var activeID: UUID? { demo?.id ?? store.activeID }

    /// The TV the session talks to: the demo while it runs, else the store's active one.
    var activeTV: TVConfig? { demo ?? store.active }

    /// Makes the TV the active one, with a new session. It ends the demo.
    func activate(_ id: UUID) {
        guard activeID != id, store.tvs.contains(where: { $0.id == id }) else { return }
        leaveDemo()
        store.activeID = id
        startSession()
    }

    /// Adds the TV found (or updates the one it is), makes it the active one and talks to it.
    /// It ends the demo.
    @discardableResult func add(_ found: FoundTV) -> TVConfig {
        let tv = store.add(found)
        store.activeID = tv.id
        leaveDemo()
        startSession()
        return tv
    }

    /// Forgets the TV with its pins, actions and token. When it was the active one, the next TV
    /// takes over, else the welcome screen comes back.
    func remove(_ id: UUID) {
        let wasActive = activeID == id
        actions.forget(tv: id)
        store.remove(id)
        if wasActive { startSession() }
    }

    /// Saves what the editor changed: the name if not empty, the address (and the token its link
    /// carries), then `token` if given (nil or empty deletes it). One new session if the TV is active.
    func edit(_ id: UUID, name: String, address: TVAddress?, token: String??) {
        guard var tv = store.tvs.first(where: { $0.id == id }) else { return }
        if let address {
            // A search still running would put back the address it finds over the one given.
            relocateTasks.removeValue(forKey: id)?.cancel()
            tv.host = address.host
            tv.port = address.port
            store.update(tv)
            if address.token != nil { store.setToken(address.token, for: id) }
        }
        if !name.isEmpty && name != tv.name { store.rename(id, to: name) }
        if let token { store.setToken(token, for: id) }
        if activeID == id && (address != nil || token != nil) { startSession() }
    }

    /// A new session with the active TV, replacing the previous one and its polling. An action
    /// open in the editor belonged to the previous TV: it is closed.
    private func startSession() {
        // An action still waiting for the TV to come on belongs to the previous session.
        session?.end()
        runTask?.cancel()
        runTask = nil
        editingAction = nil
        #if os(iOS)
        lostTV = nil
        #endif
        if let demoAPI {
            // Offline: no dashboard, no MAC to learn or to wake it by, never relocated.
            client = nil
            session = TVSession(api: demoAPI, mac: nil, wake: { _ in }, rereadsAfterCommands: true)
            session?.powersOnDuringMaintenance = powersOnDuringMaintenance
            restartPolling()
            return
        }
        guard let tv = store.active else {
            session = nil
            client = nil
            return
        }
        let client = GlasshouseClient(endpoint: store.endpoint(for: tv), timeout: Discovery.detailTimeout)
        self.client = client
        #if DEBUG && os(macOS)
        let api: any GlasshouseAPI = UserDefaults.standard.bool(forKey: "PaneDemoInputs") ? DemoInputsAPI(base: client) : client
        #else
        let api: any GlasshouseAPI = client
        #endif
        // The MAC the TV reports is stored: once it is off, it no longer reports one to wake it with.
        session = TVSession(api: api, mac: tv.mac, learnedMAC: { [weak self] mac in
            self?.remember(mac: mac, for: tv.id)
        }, lostContact: { [weak self] in
            self?.relocate(tv.id)
        }, answered: { [weak self] in
            self?.throttle.reset(tv.id)
            #if os(iOS)
            if self?.lostTV != nil { self?.lostTV = nil }
            #endif
        })
        session?.powersOnDuringMaintenance = powersOnDuringMaintenance
        restartPolling()
    }

    /// Back from the demo, without a new session: its pins go, the real icons come back.
    private func leaveDemo() {
        guard let demo else { return }
        actions.forget(tv: demo.id)
        icons = AppIconStore(directory: Self.iconsDirectory)
        demoAPI = nil
        self.demo = nil
    }

    private func remember(mac: String, for id: UUID) {
        guard var tv = store.tvs.first(where: { $0.id == id }) else { return }
        tv.mac = mac
        store.update(tv)
    }

    /// The TV stopped answering: looks for it by its MAC (the add screen's search, then the ARP table),
    /// only when it is saved by an address of the Mac's own network, and after `RelocationThrottle`'s
    /// intervals. At a new address, stores it and restarts the session if the TV is still active.
    private func relocate(_ id: UUID) {
        #if os(iOS)
        // Without an ARP table, a TV with a token is never looked for: the user finds it.
        if store.token(for: id) != nil {
            lost(id)
            return
        }
        #endif
        guard let tv = store.tvs.first(where: { $0.id == id }), let mac = tv.mac,
              Subnet.isLocal(tv.host, interfaces: Subnet.interfaces()) else {
            #if os(iOS)
            // Nothing to look for it by: the user finds it.
            lost(id)
            #endif
            return
        }
        guard throttle.allow(id, at: .now) else { return }
        relocateTasks[id]?.cancel()
        let relocator = relocator
        relocateTasks[id] = Task { [weak self] in
            let host = await relocator.locate(mac: mac, port: tv.port, excluding: tv.host)
            guard let self, !Task.isCancelled else { return }
            relocateTasks[id] = nil
            guard let host, var current = store.tvs.first(where: { $0.id == id }), current.host != host else {
                #if os(iOS)
                lost(id)
                #endif
                return
            }
            current.host = host
            store.update(current)
            if activeID == id { startSession() }
        }
    }

    /// Restarts the session's loop, so a popover that just opened gets fresh stats at once
    /// and the 2 s cadence from there (the session drops the results of the cancelled loop).
    func restartPolling() {
        runTask?.cancel()
        guard let session, !paused else { return }
        runTask = Task { [weak self] in
            await session.run(open: { self?.isOpen ?? false })
        }
    }

    // MARK: Keys

    /// Every key in play: the shared ones, and those of the active TV's actions (`.action(id)`).
    var assignments: KeyAssignments {
        var slots = keymap.slots
        if let tv = activeID {
            slots.merge(actions.keySlots(for: tv)) { shared, _ in shared }
        }
        return KeyAssignments(slots: slots)
    }

    /// Whether these keys would replace the Custom profile: a change of the shared keys made on
    /// Arrows or Gaming while a Custom profile exists. Ask first.
    func replacesCustom(_ assignments: KeyAssignments) -> Bool {
        keymap.replacesCustom(with: assignments.slots)
    }

    /// Stores new keys: the buttons' and sources' in the shared keymap, the actions' with the active TV.
    /// A change of the shared keys on Arrows or Gaming makes the Custom profile from it.
    func apply(_ assignments: KeyAssignments) {
        keymap.set(assignments.slots)
        guard let tv = activeID else { return }
        for action in actions.actions(for: tv) {
            let key = assignments.slots[.action(action.id)]?.primary
            if key != action.key { actions.setKey(key, action: action.id, for: tv) }
        }
    }

    /// What a click on the button does: its command, or the custom action's steps.
    func press(_ id: ButtonID) {
        guard let session else { return }
        #if os(iOS)
        noteCommandSent()
        #endif
        if let actionID = id.actionID {
            guard let tv = activeID,
                  let action = actions.actions(for: tv).first(where: { $0.id == actionID }) else { return }
            Task { await session.trigger(action) }
        } else {
            Task { await session.press(id) }
        }
    }

    // MARK: Global shortcuts

    /// Every global shortcut in play: the shared ones, and those of the active TV's actions.
    var globalAssignments: KeyAssignments {
        var slots = keymap.globals.mapValues { KeySlot(primary: $0) }
        if let tv = activeID {
            slots.merge(actions.globalSlots(for: tv)) { shared, _ in shared }
        }
        return KeyAssignments(slots: slots)
    }

    /// Stores new global shortcuts: the buttons' and sources' in the shared keymap, the actions'
    /// with the active TV.
    func applyGlobals(_ assignments: KeyAssignments) {
        let shared = Set(keymap.globals.keys).union(assignments.slots.keys).filter { $0.actionID == nil }
        for id in shared {
            let key = assignments.slots[id]?.primary
            if key != keymap.globals[id] { keymap.setGlobal(key, for: id) }
        }
        guard let tv = activeID else { return }
        for action in actions.actions(for: tv) {
            let key = assignments.slots[.action(action.id)]?.primary
            if key != action.globalKey { actions.setGlobalKey(key, action: action.id, for: tv) }
        }
    }

    /// What a global shortcut does: the active TV's action, or the button's press; its result, for
    /// the feedback card.
    func fire(_ id: ButtonID) async -> ActionResult {
        guard let session else { return .failed(String(localized: "No TV")) }
        if let actionID = id.actionID, let tv = activeID,
           let action = actions.actions(for: tv).first(where: { $0.id == actionID }) {
            return await session.trigger(action)
        }
        return await session.press(id)
    }

    // MARK: Actions and pins

    /// The active TV's inputs, to name the steps that choose one.
    private var currentSources: [Source] { session?.stats.map(sources(from:)) ?? [] }

    /// Opens the editor on an empty action.
    func newAction() {
        editingAction = CustomAction(title: "", steps: [])
    }

    func edit(_ action: CustomAction) {
        editingAction = action
    }

    /// Stores the action with the active TV, under its steps' title when it has none, and pins it
    /// if asked. Its key stays the one stored.
    func save(_ action: CustomAction, pin: Bool) {
        guard let tv = activeID else { return }
        var action = action
        if action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            action.title = CustomAction.defaultTitle(action.steps, sources: currentSources)
        }
        action.key = actions.actions(for: tv).first { $0.id == action.id }?.key ?? action.key
        actions.save(action, for: tv)
        if pin { actions.pin(action.id, for: tv) }
    }

    /// Deletes the action, and closes the popover's editor if it is open on it.
    func deleteAction(_ id: UUID) {
        guard let tv = activeID else { return }
        actions.delete(id, for: tv)
        if editingAction?.id == id { editingAction = nil }
    }

    func pin(_ id: UUID) {
        guard let tv = activeID else { return }
        actions.pin(id, for: tv)
    }

    /// Moves the pin to the place of the target pin, the others making room.
    func movePin(_ id: UUID, to target: UUID) {
        guard let tv = activeID else { return }
        let ids = actions.pinned(for: tv).map(\.id)
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target), from != to else { return }
        actions.movePin(for: tv, from: [from], to: to > from ? to + 1 : to)
    }

    /// The active TV's actions that no pin shows, in their order: the pins' "+" offers them again.
    var unpinnedActions: [CustomAction] {
        guard let tv = activeID else { return [] }
        return actions.actions(for: tv).filter { !actions.isPinned($0.id, for: tv) }
    }

    func unpin(_ id: UUID) {
        guard let tv = activeID else { return }
        actions.unpin(id, for: tv)
    }

    /// Pins the row at its current value, as a one-step action.
    func pin(row: SettingRow) {
        guard let step = ActionStep(currentValueOf: row) else { return }
        pin(step)
    }

    func pinPictureMode(_ value: String, label: String) {
        pin(.pictureMode(value: value, label: label))
    }

    /// A new pinned action of this one step, unless a pinned action does just that already.
    private func pin(_ step: ActionStep) {
        guard let tv = activeID, let session else { return }
        if actions.isPinned(onlyStep: step, for: tv) {
            session.say(String(localized: "Already pinned"))
            return
        }
        let action = CustomAction(title: step.defaultTitle(sources: currentSources), steps: [step])
        actions.save(action, for: tv)
        actions.pin(action.id, for: tv)
        #if os(iOS)
        // iOS calls the tab the remote.
        session.say(String(localized: "Pinned to the remote"))
        #else
        session.say(String(localized: "Pinned to Remote"))
        #endif
    }

    func stop() {
        session?.end()
        runTask?.cancel()
        runTask = nil
        relocateTasks.values.forEach { $0.cancel() }
        relocateTasks = [:]
    }

    /// Opens the web dashboard, on one of its tabs or on its own default.
    func openDashboard(tab: String?) {
        guard let url = client?.dashboardURL(tab: tab) else { return }
        openExternal(url)
    }
}

#if os(iOS)
extension AppModel {
    // MARK: Foreground (iOS)

    /// The app went to the background: the session stops polling, and stays, its state marked old
    /// until the first read on return. A search for a lost TV stops too, and may start again at
    /// once when the TV still does not answer on return.
    func pause() {
        paused = true
        isOpen = false
        runTask?.cancel()
        runTask = nil
        session?.markStale()
        for (id, task) in relocateTasks {
            task.cancel()
            throttle.reset(id)
        }
        relocateTasks = [:]
    }

    /// The app is in the foreground again: the session reads the TV at once (`run` starts with a
    /// read), then every 2 s.
    func resume() {
        paused = false
        isOpen = true
        // The launch is no return: the add screen's first search is under way.
        if launched { foregroundReturns &+= 1 }
        launched = true
        restartPolling()
    }

    /// Back in the foreground from an alert (the local network prompt) or the Control Center, not
    /// from the background: the polling goes on. A read the system refused is made again at once,
    /// since the user may just have allowed the local network.
    func reactivate() {
        foregroundReturns &+= 1
        if session?.localNetworkDenied == true { restartPolling() }
    }

    /// The TV searched for was not found: Remote says so while it is still the active one.
    fileprivate func lost(_ id: UUID) {
        if activeID == id { lostTV = id }
    }

    /// A command leaves the screen: a light tap under the finger.
    func noteCommandSent() {
        commandsSent &+= 1
    }

    // MARK: Demo (iOS)

    /// The demo TV's id, for its pins.
    fileprivate static let demoID = UUID(uuidString: "00000000-0000-0000-0000-00000000DE70")!

    /// Puts a fake TV, offline, in place of the active one: for App Review and the screenshots.
    /// Its pins are the README's; the saved TVs stay as they are. `standby`: the demo TV starts in
    /// Active Standby (for the App Store preview, which opens on turning it on).
    func startDemo(standby: Bool = false) {
        guard demo == nil else { return }
        let tv = TVConfig(id: Self.demoID, name: String(localized: "Demo"), host: DemoTV.host)
        actions.forget(tv: tv.id)
        for action in Self.demoActions {
            actions.save(action, for: tv.id)
            actions.pin(action.id, for: tv.id)
        }
        icons = AppIconStore(directory: nil)
        demoAPI = DemoTV(standby: standby)
        demo = tv
        startSession()
    }

    /// Back to the active TV, or to the welcome screen without one.
    func endDemo() {
        guard demo != nil else { return }
        leaveDemo()
        startSession()
    }

    /// Three apps shown as their icons, an input with a setting, and the screen.
    private static var demoActions: [CustomAction] {
        let game = ActionStep.setting(id: "gameOptimization", section: "game", title: "VRR & G-Sync",
                                      value: .bool(true), valueLabel: "ON")
        let demo: [(String?, [ActionStep])] = [
            (nil, [.launchApp(id: "com.apple.appletv", title: "PearTV")]),
            (nil, [.launchApp(id: "netflix", title: "NetMovies")]),
            (nil, [.launchApp(id: "spotify-beehive", title: "Musicify")]),
            (String(localized: "PS7 + Game"), [.button(.source("hdmi2")), game]),
            (nil, [.screenOff]),
        ]
        return demo.map { title, steps in
            CustomAction(title: title ?? CustomAction.defaultTitle(steps, sources: []), steps: steps)
        }
    }
}
#endif

extension EnvironmentValues {
    /// The app's model, for the key recorders of Settings.
    @Entry var appModel: AppModel?
}
