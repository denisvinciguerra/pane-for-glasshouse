import Foundation

extension TVSession {
    /// Sends a text command and returns the server's answer, even when it says `ok: false`.
    /// `nil` when controls are blocked (nothing is sent) or the request fails. No session message,
    /// no optimistic change and no stats read: the caller decides what the answer means.
    public func sendText(_ command: Command) async -> ControlResult? {
        guard blockedReason == nil else { return nil }
        return try? await api.sendForResult(command)
    }
}
