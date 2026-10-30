import Foundation
import Observation

public enum PaneTab: String, CaseIterable, Sendable { case remote, picture, audio, game, hdmi, stats }

/// The texts the session shows in `transientMessage`.
enum SessionText {
    static func controlsOff(_ bundle: Bundle = .module) -> String {
        String(localized: "Controls are turned off on this TV", bundle: bundle)
    }
    static func unreachable(_ bundle: Bundle = .module) -> String {
        String(localized: "TV unreachable", bundle: bundle)
    }
    static func noWakeOnLAN(_ bundle: Bundle = .module) -> String {
        String(localized: "Wake-on-LAN isn't available for this TV", bundle: bundle)
    }
    static func wakeFailed(_ bundle: Bundle = .module) -> String {
        String(localized: "Couldn't send Wake-on-LAN", bundle: bundle)
    }
    static func rejected(_ bundle: Bundle = .module) -> String {
        String(localized: "The TV refused the command", bundle: bundle)
    }
    static func badToken(_ bundle: Bundle = .module) -> String {
        String(localized: "Wrong or missing token", bundle: bundle)
    }
    static func wakeOnLANOff(_ bundle: Bundle = .module) -> String {
        String(localized: "Wake-on-LAN is turned off on this TV", bundle: bundle)
    }
    static func powerOff(_ bundle: Bundle = .module) -> String {
        String(localized: "Power control is turned off on this TV", bundle: bundle)
    }
    static func sendFailed(_ bundle: Bundle = .module) -> String {
        String(localized: "Couldn't send the command", bundle: bundle)
    }
    static func capsUnknown(_ bundle: Bundle = .module) -> String {
        String(localized: "Couldn't read this TV's permissions", bundle: bundle)
    }
    static func connecting(_ bundle: Bundle = .module) -> String {
        String(localized: "Connecting…", bundle: bundle)
    }
    static func localNetworkDenied(_ bundle: Bundle = .module) -> String {
        String(localized: "Local network access is off for Pane", bundle: bundle)
    }
    static func standby(_ bundle: Bundle = .module) -> String {
        String(localized: "TV is in standby", bundle: bundle)
    }
}

/// When to ask again for something that failed: after 2 s of waiting, then 4 s, 8 s… up to 60 s.
struct RetryBackoff {
    private var delay: Duration = .seconds(2)
    private var waited: Duration = .zero

    mutating func wait(_ d: Duration) { waited += d }

    /// Whether the retry is due; if so, the wait starts over, twice as long.
    mutating func due() -> Bool {
        guard waited >= delay else { return false }
        waited = .zero
        delay = min(delay * 2, .seconds(60))
        return true
    }
}

/// Orders the reads of one resource. A result, success or failure, lands only if it is newer
/// than the last one that landed and than the last optimistic change; otherwise it is dropped.
struct ReadGate {
    private var next = 0
    private var floor = 0

    /// The number of a read about to be asked.
    mutating func issue() -> Int {
        defer { next += 1 }
        return next
    }

    /// Whether read `seq` may land; if so, it becomes the newest.
    mutating func land(_ seq: Int) -> Bool {
        guard seq >= floor else { return false }
        floor = seq + 1
        return true
    }

    /// The reads already asked are older than a local change: their results will be dropped.
    mutating func invalidate() { floor = next }
}

/// One TV's state, read from its server, and the commands sent to it. The views only read it.
@MainActor @Observable public final class TVSession {
    public private(set) var stats: Stats?
    public private(set) var caps: Caps?
    public private(set) var power: PowerState = .unreachable
    public private(set) var lastError: APIError?
    /// True until the first stats read and the first caps attempt have both completed.
    public private(set) var connecting = true
    /// macOS refuses this app the local network.
    public var localNetworkDenied: Bool { lastError == .localNetworkDenied }
    /// The server's version when it is older than the Picture tab's; `nil` when current or unreadable.
    public var outdatedVersion: String? {
        guard let version = caps?.version, let parsed = ServerVersion(version), parsed < .pictureTab else { return nil }
        return version
    }
    public private(set) var transientMessage: String?
    public private(set) var picture: PicturePayload?
    public private(set) var game: GamePayload?
    public private(set) var audio: AudioPayload?
    public private(set) var hdmi: HDMIOverview?
    /// The tabs to show, in `PaneTab.allCases` order. A tab goes when its payload says it is not
    /// available or its request answers 404, and comes back when a later read says otherwise.
    public private(set) var availableTabs: [PaneTab] = PaneTab.allCases
    public private(set) var webTabs: [DashboardTab] = DashboardTabs.fallback

    /// The commands other than power: allowed by the caps, the TV on (its screen may be off).
    public var canControl: Bool {
        caps?.allowControl == true && (power == .on || power == .screenOff)
    }
    /// Power commands and Wake-on-LAN; allowed unless the server says otherwise.
    public var canPower: Bool { caps?.allowPower != false }

    /// Why the commands are off, in one line; `nil` when they are on.
    public var blockedReason: String? {
        if canControl { return nil }
        if connecting { return SessionText.connecting() }
        if localNetworkDenied { return SessionText.localNetworkDenied() }
        if let powerBlock { return powerBlock }
        switch power {
        case .unreachable: return SessionText.unreachable()
        case .standby, .maintenance: return SessionText.standby()
        // The TV answers but its caps did not come: they are asked for again, with a backoff.
        case .on, .screenOff: return SessionText.capsUnknown()
        }
    }

    /// What also stops the power commands, which work in standby and with the caps unknown.
    private var powerBlock: String? {
        if caps?.allowControl == false { return SessionText.controlsOff() }
        if lastError == .badToken { return SessionText.badToken() }
        return nil
    }

    @ObservationIgnored private let api: any GlasshouseAPI
    /// The stored MAC, replaced by each different one the TV reports.
    @ObservationIgnored private var mac: String?
    /// Told each MAC the TV reports that differs from `mac`, so the app can store it for Wake-on-LAN.
    @ObservationIgnored private let learnedMAC: @MainActor (String) -> Void
    @ObservationIgnored let sleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private let wake: @Sendable (String) async throws -> Void
    /// Clears `transientMessage` after 4 s.
    @ObservationIgnored private(set) var messageTask: Task<Void, Never>?
    /// Bumped by every read that lands, so a failed command does not roll back over a fresher read.
    @ObservationIgnored private var readCount = 0
    @ObservationIgnored private var statsRead = false
    @ObservationIgnored private var capsTried = false
    /// Consecutive stats reads that found the TV unreachable.
    @ObservationIgnored private var unreachableReads = 0
    /// Told on every third consecutive unreachable read, so the app can look for the TV's new address.
    @ObservationIgnored private let lostContact: @MainActor () -> Void
    /// Told on every stats read the TV answers, so the app can forget how often it looked for it.
    @ObservationIgnored private let answered: @MainActor () -> Void
    @ObservationIgnored private var statsGate = ReadGate()
    @ObservationIgnored private var pictureGate = ReadGate()
    @ObservationIgnored private var gameGate = ReadGate()
    @ObservationIgnored private var audioGate = ReadGate()
    @ObservationIgnored private var hdmiGate = ReadGate()

    public init(api: any GlasshouseAPI, mac: String?,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                wake: @escaping @Sendable (String) async throws -> Void = { try await WakeOnLAN.send(mac: $0) },
                learnedMAC: @escaping @MainActor (String) -> Void = { _ in },
                lostContact: @escaping @MainActor () -> Void = {},
                answered: @escaping @MainActor () -> Void = {}) {
        self.api = api
        self.mac = mac
        self.learnedMAC = learnedMAC
        self.sleep = sleep
        self.wake = wake
        self.lostContact = lostContact
        self.answered = answered
    }

    // MARK: Reads

    /// A failure keeps the last stats but marks the TV unreachable. When the task is cancelled
    /// (window closed, app quitting), nothing changes: the client reports that as unreachable too.
    /// A read overtaken by a newer one, or by a command, changes nothing either.
    public func refreshStats() async {
        let seq = statsGate.issue()
        let result = await load("/api/stats", as: Stats.self)
        guard !Task.isCancelled, statsGate.land(seq) else { return }
        switch result {
        case .success(let s):
            stats = s
            power = PowerState.from(s)
            lastError = nil
            unreachableReads = 0
            readCount += 1
            answered()
            if let reported = s.mac, !reported.isEmpty, reported != mac {
                mac = reported
                learnedMAC(reported)
            }
        case .failure(let error):
            lastError = error
            power = .unreachable
            if error == .unreachable {
                unreachableReads += 1
                if unreachableReads % 3 == 0 { lostContact() }
            } else {
                unreachableReads = 0
            }
        }
        statsRead = true
        connecting = !capsTried
    }

    public func refresh(_ tab: PaneTab) async {
        switch tab {
        case .remote, .stats:
            await refreshStats()
        case .picture:
            let seq = pictureGate.issue()
            let r = await load("/api/picture", as: PicturePayload.self)
            if let p = land(r, seq, \.pictureGate, tab: .picture) {
                picture = p
                setAvailable(.picture, p.available)
            }
        case .game:
            let seq = gameGate.issue()
            let r = await load("/api/game", as: GamePayload.self)
            if let g = land(r, seq, \.gameGate, tab: .game) {
                game = g
                setAvailable(.game, g.available)
            }
        case .audio:
            let seq = audioGate.issue()
            let r = await load("/api/audio?with=settings", as: AudioPayload.self)
            if let a = land(r, seq, \.audioGate, tab: .audio) {
                audio = a
                setAvailable(.audio, true)
            }
        case .hdmi:
            let hdmiSeq = hdmiGate.issue(), audioSeq = audioGate.issue()
            async let h = load("/api/hdmi", as: HDMIPayload.self)
            async let a = load("/api/audio?with=settings", as: AudioPayload.self)
            async let l = load("/api/lgsettings?section=hdmi,devices", as: LGSettingsPayload.self)
            let (hr, ar, lr) = await (h, a, l)
            guard !Task.isCancelled, hdmiGate.land(hdmiSeq) else { return }
            note([error(hr), error(ar), error(lr)])
            if case .failure(.http(404)) = hr { setAvailable(.hdmi, false) }
            let audioPayload = try? ar.get()
            if let audioPayload, audioGate.land(audioSeq) { audio = audioPayload }
            guard case .success(let payload) = hr else { return }
            setAvailable(.hdmi, true)
            hdmi = HDMIOverview(hdmi: payload, stats: stats, audio: audioPayload, lgSettings: try? lr.get())
            readCount += 1
        }
    }

    /// The caps, and the web dashboard's tabs (the built-in list when the page gives none).
    /// The page failing changes nothing but the tabs: it is not the TV's state.
    public func loadCapsAndTabs() async {
        async let c: Void = loadCaps()
        async let t = loadText("/")
        // Learn which tabs the TV offers: also asked on every popover open, so a tab that came
        // back (a server update) shows again.
        async let p: Void = refresh(.picture)
        async let g: Void = refresh(.game)
        async let a: Void = refresh(.audio)
        // HDMI costs three reads: asked here only to learn whether a hidden tab came back.
        async let h: Void = refreshHDMIIfHidden()
        let tr = await t
        _ = await (c, p, g, a, h)
        guard !Task.isCancelled else { return }
        let parsed = (try? tr.get()).map { DashboardTabs.parse(html: $0) } ?? []
        webTabs = parsed.isEmpty ? DashboardTabs.fallback : parsed
    }

    private func refreshHDMIIfHidden() async {
        if !availableTabs.contains(.hdmi) { await refresh(.hdmi) }
    }

    /// A 404 is a server without caps: everything is allowed. Another failure leaves the caps
    /// unknown (`nil`), or as last read.
    private func loadCaps() async {
        let result = await load("/api/caps", as: Caps.self)
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let value): caps = value
        case .failure(.http(404)): caps = .permissive
        case .failure(let error): lastError = error
        }
        capsTried = true
        connecting = !statsRead
    }

    /// The app's icon as the TV serves it; `nil` when the TV does not answer or has none. It
    /// changes nothing in the session.
    public nonisolated func appIcon(_ appID: String) async -> Data? {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "id", value: appID)]
        guard let encoded = query.percentEncodedQuery else { return nil }
        return try? await api.getData("/api/apps/icon?" + encoded)
    }

    /// Polls the stats every 2 s while `open()`, every 30 s otherwise, until the task is cancelled.
    /// The first stats read does not wait for the caps and the page (638 KB): a popover that just
    /// opened shows the TV's state at once.
    public func run(open: @escaping @MainActor () -> Bool) async {
        async let setup: Void = loadCapsAndTabs()
        await refreshStats()
        await setup
        var capsRetry = RetryBackoff()
        while !Task.isCancelled {
            // The caps did not come (the TV away, a server error): ask for them alone, now and
            // then, while the TV answers.
            if caps == nil, power != .unreachable, capsRetry.due() { await loadCaps() }
            guard !Task.isCancelled else { return }
            let pause: Duration = open() ? .seconds(2) : .seconds(30)
            await sleep(pause)
            capsRetry.wait(pause)
            guard !Task.isCancelled else { return }
            await refreshStats()
        }
    }

    private nonisolated func load<T: Decodable & Sendable>(_ path: String, as: T.Type) async -> Result<T, APIError> {
        do { return .success(try await api.get(path, as: T.self)) } catch { return .failure(error) }
    }

    private nonisolated func loadText(_ path: String) async -> Result<String, APIError> {
        do { return .success(try await api.getText(path)) } catch { return .failure(error) }
    }

    /// The value of a single read, recording its error; `nil` without a change once cancelled or
    /// when a newer read or a local change got there first.
    private func land<T>(_ result: Result<T, APIError>, _ seq: Int,
                         _ gate: ReferenceWritableKeyPath<TVSession, ReadGate>, tab: PaneTab? = nil) -> T? {
        guard !Task.isCancelled, self[keyPath: gate].land(seq) else { return nil }
        note([error(result)])
        if let tab, case .failure(.http(404)) = result { setAvailable(tab, false) }
        guard case .success(let value) = result else { return nil }
        readCount += 1
        return value
    }

    private func setAvailable(_ tab: PaneTab, _ available: Bool) {
        let tabs = PaneTab.allCases.filter { $0 == tab ? available : availableTabs.contains($0) }
        if tabs != availableTabs { availableTabs = tabs }
    }

    private func error<T>(_ result: Result<T, APIError>) -> APIError? {
        if case .failure(let e) = result { e } else { nil }
    }

    /// `lastError` becomes the first failure of the batch, or nil when everything answered.
    private func note(_ errors: [APIError?]) {
        lastError = errors.lazy.compactMap { $0 }.first
    }

    // MARK: Commands

    /// Sends a command, showing its effect at once for volume, mute, input and settings. A failed
    /// command puts the previous values back and says why for 4 s. Whether it went out and was accepted.
    @discardableResult public func send(_ command: Command) async -> Bool {
        if let blockedReason {
            post(blockedReason)
            return false
        }
        return await perform(command)
    }

    @discardableResult private func perform(_ command: Command) async -> Bool {
        let before = (stats, picture, game, audio, hdmi)
        let readsBefore = readCount
        applyOptimistically(command)
        do {
            try await api.send(command)
            lastError = nil
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            lastError = error
            if readCount == readsBefore { (stats, picture, game, audio, hdmi) = before }
            switch error {
            case .rejected(let message): post(message.isEmpty ? SessionText.rejected() : message)
            case .badToken: post(SessionText.badToken())
            default: post(SessionText.sendFailed())
            }
            return false
        }
    }

    /// On or screen off → power off; standby or maintenance → power on, after a power off when the TV
    /// shows Always Ready; unreachable → Wake-on-LAN, to the MAC the TV last reported, else the stored
    /// one, unless the TV has it turned off.
    /// Standby and unknown caps do not stop it; controls turned off and a bad token do.
    public func togglePower() async {
        guard canPower else {
            post(SessionText.powerOff())
            return
        }
        switch power {
        case .on, .screenOff, .standby, .maintenance:
            if let powerBlock {
                post(powerBlock)
                return
            }
            if stats?.powerState?.raw == "Always Ready" {
                await leaveAlwaysReady()
                return
            }
            await perform(power == .on || power == .screenOff ? .powerOff : .powerOn)
        case .unreachable:
            // A refused local network cannot reach any TV: waking it would not help.
            if localNetworkDenied {
                post(SessionText.localNetworkDenied())
                return
            }
            // A 401 also reads as unreachable, but the TV is up: waking it would not help.
            if lastError == .badToken {
                post(SessionText.badToken())
                return
            }
            if stats?.wakeOnLan == false {
                post(SessionText.wakeOnLANOff())
                return
            }
            guard let target = [stats?.mac, mac].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
                post(SessionText.noWakeOnLAN())
                return
            }
            do {
                try await wake(target)
            } catch {
                guard !Task.isCancelled else { return }
                post(SessionText.wakeFailed())
            }
        }
    }

    /// LG's Always Ready screen ignores powerOn: powerOff takes the TV to Active Standby first
    /// (seen on the G4 with Glasshouse 0.135). powerOn goes once it gets there, or after 10 s.
    private func leaveAlwaysReady() async {
        guard await perform(.powerOff) else { return }
        for _ in 0..<10 {
            await sleep(.seconds(1))
            guard !Task.isCancelled else { return }
            await refreshStats()
            if stats?.powerState?.raw != "Always Ready" { break }
        }
        guard !Task.isCancelled else { return }
        await perform(.powerOn)
    }

    private func applyOptimistically(_ command: Command) {
        switch command {
        case .volume, .volumeStep, .mute, .input:
            statsGate.invalidate()
        case .lgSetting:
            pictureGate.invalidate(); gameGate.invalidate(); audioGate.invalidate(); hdmiGate.invalidate()
        default:
            break
        }
        switch command {
        case .volume(let v):
            stats?.volume = min(max(v, 0), 100)
        case .volumeStep(let step):
            if let v = stats?.volume { stats?.volume = min(max(v + step, 0), 100) }
        case .mute(let m):
            stats?.muted = m
        case .input(let id):
            stats?.app = id
        case .lgSetting(let id, let value):
            // Each new array is built before the assignment starts: reading the property inside
            // its own optional-chained assignment is an exclusivity violation.
            if let rows = picture?.rows { picture?.rows = Self.set(id, value, in: rows) }
            if let rows = game?.rows { game?.rows = Self.set(id, value, in: rows) }
            if let rows = audio?.lgSettings { audio?.lgSettings = Self.set(id, value, in: rows) }
            if let rows = hdmi?.settings { hdmi?.settings = Self.set(id, value, in: rows) }
        default:
            break
        }
    }

    /// The rows with the one of that id set to the value, when the value fits the row's kind.
    private static func set(_ id: String, _ value: SettingValue, in rows: [SettingRow]) -> [SettingRow] {
        rows.map { row in
            guard row.id == id else { return row }
            var row = row
            switch (row.kind, value) {
            case (.toggle, .bool(let on)): row.kind = .toggle(on: on)
            case (.number(_, let lo, let hi), .number(let n)): row.kind = .number(value: n, min: lo, max: hi)
            case (.choice(_, let choices), .string(let s)): row.kind = .choice(value: s, choices: choices)
            default: break
            }
            return row
        }
    }

    func post(_ message: String) {
        transientMessage = message
        messageTask?.cancel()
        messageTask = Task { [weak self, sleep] in
            await sleep(.seconds(4))
            guard !Task.isCancelled else { return }
            self?.transientMessage = nil
        }
    }
}
