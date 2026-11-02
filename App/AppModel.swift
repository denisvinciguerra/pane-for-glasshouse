import AppKit
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
    /// The icons of the apps the pins launch, kept in the app's caches.
    let icons: AppIconStore
    /// The updates, through Sparkle.
    let updates: Updates
    /// The global shortcuts, registered with the system.
    let hotKeys = GlobalHotKeys()
    private(set) var session: TVSession?
    /// The active TV's client, for the dashboard links.
    private(set) var client: GlasshouseClient?
    var selectedTab: PaneTab = .remote
    /// The action open in the popover's editor, which then takes the place of the tab bar and the tab.
    var editingAction: CustomAction?
    /// Whether the popover is shown: the session polls every 2 s then, every 30 s otherwise.
    var isOpen = false
    /// Whether a recorder of global shortcuts is listening: the shortcuts are suspended meanwhile,
    /// so that a combination Pane holds reaches the recorder.
    var keyRecorderActive = false
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

    /// Opens the preferences window on a pane (set by the app delegate).
    /// `nil`: the pane it showed last.
    @ObservationIgnored var openPreferences: (PreferencesPane?) -> Void = { _ in }
    /// The search for TVs on the network and the check of one address, for the add screen.
    @ObservationIgnored let discovery = Discovery()
    @ObservationIgnored let probe = TVProbe(makeDetailAPI: { GlasshouseClient(endpoint: $0, timeout: Discovery.detailTimeout) })

    private static let maintenanceKey = "powerOnDuringMaintenance"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var throttle = RelocationThrottle()
    @ObservationIgnored private var relocateTasks: [UUID: Task<Void, Never>] = [:]

    /// `actions` and `keymap`: the stores of the custom actions and of the keys, by default in `defaults`.
    init(updates: Updates, store: TVConfigStore = TVConfigStore(), defaults: UserDefaults = .standard,
         actions: ActionStore? = nil, keymap: KeymapStore? = nil) {
        self.updates = updates
        self.store = store
        self.defaults = defaults
        self.keymap = keymap ?? KeymapStore(defaults: defaults)
        self.actions = actions ?? ActionStore(defaults: defaults)
        icons = AppIconStore(directory: Self.iconsDirectory)
        theme = defaults.string(forKey: ThemeMode.defaultsKey).flatMap(ThemeMode.init) ?? .auto
        powersOnDuringMaintenance = defaults.bool(forKey: Self.maintenanceKey)
        startSession()
    }

    /// `~/Library/Caches/<bundle ID>/AppIcons`.
    private static var iconsDirectory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let bundle = Bundle.main.bundleIdentifier else { return nil }
        return caches.appendingPathComponent(bundle).appendingPathComponent("AppIcons")
    }

    // MARK: TVs

    /// Makes the TV the active one, with a new session.
    func activate(_ id: UUID) {
        guard store.activeID != id, store.tvs.contains(where: { $0.id == id }) else { return }
        store.activeID = id
        startSession()
    }

    /// Adds the TV found (or updates the one it is), makes it the active one and talks to it.
    @discardableResult func add(_ found: FoundTV) -> TVConfig {
        let tv = store.add(found)
        store.activeID = tv.id
        startSession()
        return tv
    }

    /// Forgets the TV with its pins, actions and token. When it was the active one, the next TV
    /// takes over, else the welcome screen comes back.
    func remove(_ id: UUID) {
        let wasActive = store.activeID == id
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
        if store.activeID == id && (address != nil || token != nil) { startSession() }
    }

    /// A new session with the active TV, replacing the previous one and its polling. An action
    /// open in the editor belonged to the previous TV: it is closed.
    private func startSession() {
        // An action still waiting for the TV to come on belongs to the previous session.
        session?.end()
        runTask?.cancel()
        runTask = nil
        editingAction = nil
        guard let tv = store.active else {
            session = nil
            client = nil
            return
        }
        let client = GlasshouseClient(endpoint: store.endpoint(for: tv), timeout: Discovery.detailTimeout)
        self.client = client
        var api: any GlasshouseAPI = client
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "PaneDemoInputs") { api = DemoInputsAPI(base: client) }
        #endif
        // The MAC the TV reports is stored: once it is off, it no longer reports one to wake it with.
        session = TVSession(api: api, mac: tv.mac, learnedMAC: { [weak self] mac in
            self?.remember(mac: mac, for: tv.id)
        }, lostContact: { [weak self] in
            self?.relocate(tv.id)
        }, answered: { [weak self] in
            self?.throttle.reset(tv.id)
        })
        session?.powersOnDuringMaintenance = powersOnDuringMaintenance
        restartPolling()
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
        guard let tv = store.tvs.first(where: { $0.id == id }), let mac = tv.mac,
              Subnet.isLocal(tv.host, interfaces: Subnet.interfaces()),
              throttle.allow(id, at: .now) else { return }
        relocateTasks[id]?.cancel()
        relocateTasks[id] = Task { [weak self] in
            let host = await Relocator().locate(mac: mac, port: tv.port, excluding: tv.host)
            guard let self, !Task.isCancelled else { return }
            relocateTasks[id] = nil
            guard let host, var current = store.tvs.first(where: { $0.id == id }), current.host != host else { return }
            current.host = host
            store.update(current)
            if store.activeID == id { startSession() }
        }
    }

    /// Restarts the session's loop, so a popover that just opened gets fresh stats at once
    /// and the 2 s cadence from there (the session drops the results of the cancelled loop).
    func restartPolling() {
        runTask?.cancel()
        guard let session else { return }
        runTask = Task { [weak self] in
            await session.run(open: { self?.isOpen ?? false })
        }
    }

    // MARK: Keys

    /// Every key in play: the shared ones, and those of the active TV's actions (`.action(id)`).
    var assignments: KeyAssignments {
        var slots = keymap.slots
        if let tv = store.activeID {
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
        guard let tv = store.activeID else { return }
        for action in actions.actions(for: tv) {
            let key = assignments.slots[.action(action.id)]?.primary
            if key != action.key { actions.setKey(key, action: action.id, for: tv) }
        }
    }

    /// What a click on the button does: its command, or the custom action's steps.
    func press(_ id: ButtonID) {
        guard let session else { return }
        if let actionID = id.actionID {
            guard let tv = store.activeID,
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
        if let tv = store.activeID {
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
        guard let tv = store.activeID else { return }
        for action in actions.actions(for: tv) {
            let key = assignments.slots[.action(action.id)]?.primary
            if key != action.globalKey { actions.setGlobalKey(key, action: action.id, for: tv) }
        }
    }

    /// What a global shortcut does: the active TV's action, or the button's press; its result, for
    /// the feedback card.
    func fire(_ id: ButtonID) async -> ActionResult {
        guard let session else { return .failed(String(localized: "No TV")) }
        if let actionID = id.actionID, let tv = store.activeID,
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
        guard let tv = store.activeID else { return }
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
        guard let tv = store.activeID else { return }
        actions.delete(id, for: tv)
        if editingAction?.id == id { editingAction = nil }
    }

    func pin(_ id: UUID) {
        guard let tv = store.activeID else { return }
        actions.pin(id, for: tv)
    }

    /// Moves the pin to the place of the target pin, the others making room.
    func movePin(_ id: UUID, to target: UUID) {
        guard let tv = store.activeID else { return }
        let ids = actions.pinned(for: tv).map(\.id)
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target), from != to else { return }
        actions.movePin(for: tv, from: [from], to: to > from ? to + 1 : to)
    }

    /// The active TV's actions that no pin shows, in their order: the pins' "+" offers them again.
    var unpinnedActions: [CustomAction] {
        guard let tv = store.activeID else { return [] }
        return actions.actions(for: tv).filter { !actions.isPinned($0.id, for: tv) }
    }

    func unpin(_ id: UUID) {
        guard let tv = store.activeID else { return }
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
        guard let tv = store.activeID, let session else { return }
        if actions.isPinned(onlyStep: step, for: tv) {
            session.say(String(localized: "Already pinned"))
            return
        }
        let action = CustomAction(title: step.defaultTitle(sources: currentSources), steps: [step])
        actions.save(action, for: tv)
        actions.pin(action.id, for: tv)
        session.say(String(localized: "Pinned to Remote"))
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
        NSWorkspace.shared.open(url)
    }
}

extension EnvironmentValues {
    /// The app's model, for the key recorders of Settings.
    @Entry var appModel: AppModel?
}
