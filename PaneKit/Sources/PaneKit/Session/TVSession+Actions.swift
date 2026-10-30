import Foundation

extension TVSession {
    /// The pause between two steps of an action, on the injected clock.
    public static let stepPause: Duration = .milliseconds(1500)

    /// What the TV offers now: the stats and every row loaded so far.
    public var actionContext: ActionContext {
        let rows = (picture?.rows ?? []) + (game?.rows ?? []) + (audio?.lgSettings ?? []) + (hdmi?.settings ?? [])
        return ActionContext(stats: stats, rows: rows)
    }

    public func unavailableReason(_ action: CustomAction) -> String? { actionContext.unavailableReason(action) }

    /// A reason the action cannot run, or the TV's blocked reason: said, nothing is sent. Otherwise
    /// the steps in order, `stepPause` between two; the first failure stops the sequence.
    public func trigger(_ action: CustomAction) async {
        if let reason = unavailableReason(action) ?? blockedReason {
            post(reason)
            return
        }
        for (index, step) in action.steps.enumerated() {
            if index > 0 {
                await sleep(Self.stepPause)
                guard !Task.isCancelled else { return }
            }
            // Asked now, not up front: a mute step reads the state the previous step left.
            guard let command = step.command(stats: stats) else { return }
            guard await send(command) else { return }
        }
    }

    /// One message in the status line, cleared after 4 s.
    public func say(_ message: String) { post(message) }
}
