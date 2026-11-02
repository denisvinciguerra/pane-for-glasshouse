import Foundation

/// What the feedback card of a global shortcut shows.
public enum ShortcutPhase: Equatable, Sendable {
    case running
    case done(String)
    case failed(String)

    /// The phase the card moves to once the press has ended; `nil` when a later shortcut took the
    /// card over.
    public static func after(_ result: ActionResult, launchesApp: Bool) -> ShortcutPhase? {
        after(result, launchesApp: launchesApp, bundle: .module)
    }

    static func after(_ result: ActionResult, launchesApp: Bool, bundle: Bundle) -> ShortcutPhase? {
        switch result {
        case .sent:
            .done(launchesApp ? String(localized: "Launched on the TV", bundle: bundle)
                              : String(localized: "Sent to the TV", bundle: bundle))
        case .failed(let message): .failed(message)
        case .cancelled: .failed(SessionText.cancelled(bundle))
        case .replaced: nil
        }
    }
}
