import Foundation

/// How triggering an action ended.
public enum ActionResult: Equatable, Sendable {
    /// Every step went out.
    case sent
    /// The message is in the status line; nothing more was sent.
    case failed(String)
    /// Power was pressed while waiting for the TV, or the session ended.
    case cancelled
    /// A more recent trigger took over the wait.
    case replaced
}

extension TVSession {
    /// The pause between two steps of an action, on the injected clock.
    public static let stepPause: Duration = .milliseconds(1500)

    /// What the TV offers now: the stats and every row loaded so far.
    public var actionContext: ActionContext {
        let rows = (picture?.rows ?? []) + (game?.rows ?? []) + (audio?.lgSettings ?? []) + (hdmi?.settings ?? [])
        return ActionContext(stats: stats, rows: rows)
    }

    public func unavailableReason(_ action: CustomAction) -> String? { actionContext.unavailableReason(action) }

    /// About the longest wait for a TV turned on by `trigger` to take commands, polled every
    /// `powerOnPoll`: that many polls at most, and no new poll once that much time has passed (a read
    /// of an unreachable TV takes seconds, so the last poll can end a little later).
    nonisolated public static let powerOnTimeout: Duration = .seconds(40)
    nonisolated public static let powerOnPoll: Duration = .seconds(1)
    /// The pause between the TV taking commands and the first step: an app launched at once may not
    /// open. It is part of the shared wait: Power or another trigger during it still counts.
    nonisolated public static let settlePause: Duration = .seconds(2)

    /// A reason the action cannot run: said, nothing is sent. A TV that takes commands runs the
    /// steps. A TV that is off is turned on first, as the power button does, unless the action only
    /// turns things off, the TV is in panel maintenance (see `powersOnDuringMaintenance`), or
    /// something stops the power-on: its reason is said instead.
    /// One power-on at a time: a trigger during the wait takes over the pending action (the earlier
    /// one returns `.replaced`); the same action again changes nothing. Power during the wait, or
    /// `end()`, cancels it. After `end()`, nothing is sent.
    @discardableResult public func trigger(_ action: CustomAction) async -> ActionResult {
        if ended { return .cancelled }
        if let reason = unavailableReason(action) { return .failed(refused(reason)) }
        // A wait in progress: join it, whatever the TV reads meanwhile.
        if action.wakesTV, sharedPowerOn != nil { return await wait(for: action) }
        if canControl { return await runSteps(action) }
        if connecting || !action.wakesTV || power == .on || power == .screenOff {
            return .failed(refused(blockedReason ?? SessionText.sendFailed()))
        }
        // Controls turned off or a bad token: waking the TV would not make it take commands.
        if let powerBlock { return .failed(refused(powerBlock)) }
        if power == .maintenance, !powersOnDuringMaintenance { return .failed(refused(SessionText.maintenance())) }
        return await wait(for: action)
    }

    /// The power-on in progress, unless it was cancelled: a new wait then starts its own.
    private var sharedPowerOn: Task<String?, Never>? {
        guard let powerOnTask, !powerOnTask.isCancelled else { return nil }
        return powerOnTask
    }

    /// Makes `action` the pending one, waits for the power-on in progress or starts it (settle pause
    /// included), then runs the action if it is still the pending one.
    private func wait(for action: CustomAction) async -> ActionResult {
        if pendingAction?.id == action.id { return .replaced }
        let task = sharedPowerOn ?? startPowerOn()
        pendingAction = action
        pendingGeneration += 1
        let generation = pendingGeneration
        latestTrigger = generation
        let failure = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            // A cancelled caller stops the power-on unless a later trigger waits for it.
            Task { @MainActor [weak self] in
                if self?.latestTrigger == generation { task.cancel() }
            }
        }
        // The last trigger to wait clears the pending action, whoever else is still waiting.
        let latest = generation == latestTrigger
        let current = latest && generation == pendingGeneration && pendingAction?.id == action.id
        if latest { pendingAction = nil }
        if ended { return .cancelled }
        guard latest else { return .replaced }
        guard current else { return .cancelled }
        if let failure { return .failed(failure) }
        guard !Task.isCancelled else { return .cancelled }
        // The TV now says which apps and inputs it has.
        if let reason = unavailableReason(action) { return .failed(refused(reason)) }
        return await runSteps(action)
    }

    /// The steps in order, `stepPause` between two; the first failure stops the sequence.
    private func runSteps(_ action: CustomAction) async -> ActionResult {
        for (index, step) in action.steps.enumerated() {
            if index > 0 {
                await sleep(Self.stepPause)
                guard !Task.isCancelled, !ended else { return .cancelled }
            }
            // Asked now, not up front: a mute step reads the state the previous step left.
            guard let command = step.command(stats: stats) else { return .failed(refused(SessionText.sendFailed())) }
            guard await send(command) else {
                guard !Task.isCancelled else { return .cancelled }
                return .failed(transientMessage ?? SessionText.sendFailed())
            }
        }
        return .sent
    }

    /// Starts the power-on the waiting triggers share, followed by the settle pause; the task clears
    /// `powerOnTask` when it is done, unless a newer one replaced it (after a cancel).
    private func startPowerOn() -> Task<String?, Never> {
        powerOnRun += 1
        let run = powerOnRun
        let task = Task {
            let failure = await powerOn()
            if failure == nil, !Task.isCancelled { await sleep(Self.settlePause) }
            if powerOnRun == run { powerOnTask = nil }
            return failure
        }
        powerOnTask = task
        return task
    }

    /// Presses a button that is not an action, as a global shortcut does: Power toggles the TV, any
    /// other button sends its command. A refused or blocked send says why, as the status line did.
    @discardableResult public func press(_ id: ButtonID) async -> ActionResult {
        if id == .power { return await togglePower() }
        guard let command = ActionStep.button(id).command(stats: stats) else {
            return .failed(String(localized: "Unknown button", bundle: .module))
        }
        if await send(command) { return .sent }
        return Task.isCancelled ? .cancelled : .failed(transientMessage ?? SessionText.sendFailed())
    }

    /// Ends the session as the app drops it: a pending action is abandoned, nothing more is sent
    /// for an action, and a later `trigger` returns `.cancelled`.
    public func end() {
        ended = true
        pendingAction = nil
        pendingGeneration += 1
        powerOnTask?.cancel()
    }

    /// Turns the TV on with `turnOn()`, then reads it every `powerOnPoll` until it takes commands.
    /// Returns the message said when the power-on was refused, the TV answered with controls turned
    /// off or a bad token, or it did not turn on within `powerOnTimeout` (in polls and in time);
    /// `nil` once it takes commands, or when the task was cancelled.
    private func powerOn() async -> String? {
        let woken = power == .unreachable
        if let refusal = await turnOn() { return refusal }
        let deadline = ContinuousClock.now + Self.powerOnTimeout
        var pressed = false
        for _ in 0..<Int(Self.powerOnTimeout / Self.powerOnPoll) {
            guard !Task.isCancelled else { return nil }
            guard ContinuousClock.now < deadline else { break }
            await sleep(Self.powerOnPoll)
            guard !Task.isCancelled else { return nil }
            // The polling of `run` is every 30 s with the popover closed: too slow here.
            await refreshStats()
            // As in `run`: no caps read while the TV does not answer.
            if caps == nil, power != .unreachable { await loadCaps() }
            if canControl { return nil }
            if let powerBlock { return refused(powerBlock) }
            // Wake-on-LAN may bring the server up with the TV still in standby: power on, once.
            if woken, !pressed, power == .standby || power == .maintenance {
                pressed = true
                if power == .maintenance, !powersOnDuringMaintenance { return refused(SessionText.maintenance()) }
                if let refusal = await turnOn() { return refusal }
            }
        }
        guard !Task.isCancelled else { return nil }
        // The TV came on but its caps never did.
        if power == .on || power == .screenOff { return refused(SessionText.capsUnknown()) }
        return refused(SessionText.didNotTurnOn())
    }

    /// One message in the status line, cleared after 4 s.
    public func say(_ message: String) { post(message) }
}
