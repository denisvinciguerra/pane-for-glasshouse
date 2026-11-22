import Foundation

/// Decides what to send to the TV as the text typed in the pointer pad changes. Pure logic: one request is out at a
/// time, and the text typed meanwhile goes out, as a single diff, when the answer arrives.
public struct TextSync {
    public static let maxLength = 500

    /// What the TV is believed to hold (UTF-16 units).
    private var confirmed: [UInt16] = []
    /// What the typed text holds now.
    private var latest: [UInt16] = []
    private var inFlight = false
    /// What `confirmed` becomes if the request out succeeds.
    private var sentTarget: [UInt16] = []
    /// Bumped by `forget()` and `submit()`; answers to older requests are stale.
    private var generation = 0
    private var requestGeneration = 0

    public init() {}

    /// The command to send, or nil when there is nothing to do or a request is still out.
    /// The caller applies `limited(_:)` to the text first.
    public mutating func edited(to text: String) -> Command? {
        latest = Array(text.utf16)
        return inFlight ? nil : nextCommand()
    }

    public mutating func acknowledged(ok: Bool, sent: Int?) -> (next: Command?, clearField: Bool) {
        guard inFlight else { return (nil, false) }
        inFlight = false
        guard requestGeneration == generation else { return (nextCommand(), false) }
        if ok {
            confirmed = sentTarget
            return (nextCommand(), false)
        }
        if let sent, sent > 0 {
            // Part of the text reached the TV: retyping would duplicate it, so start again from empty.
            confirmed = []
            latest = []
            return (nil, true)
        }
        return (nil, false)
    }

    /// The command that submits the field; the next edit starts from an empty field.
    /// Contract: the submit's answer must NOT be passed to `acknowledged`, which would take it for an
    /// edit's answer. The caller sends the submit and any following edit one after the other on the wire.
    public mutating func submit() -> Command {
        let command: Command = .submitText(full: String(decoding: latest, as: UTF16.self))
        generation += 1
        confirmed = []
        latest = []
        return command
    }

    /// Forgets the text, on Pane's side only. Nothing is sent.
    public mutating func forget() {
        generation += 1
        confirmed = []
        latest = []
    }

    /// Cuts to 500 UTF-16 units without splitting a character.
    public static func limited(_ text: String) -> String {
        var count = 0
        var result = ""
        for character in text {
            count += character.utf16.count
            if count > maxLength { break }
            result.append(character)
        }
        return result
    }

    private mutating func nextCommand() -> Command? {
        guard latest != confirmed else { return nil }
        var prefix = 0
        let limit = min(latest.count, confirmed.count)
        while prefix < limit, latest[prefix] == confirmed[prefix] { prefix += 1 }
        if prefix > 0, UTF16.isLeadSurrogate(latest[prefix - 1]) { prefix -= 1 }
        sentTarget = latest
        requestGeneration = generation
        inFlight = true
        return .sendText(
            text: String(decoding: latest[prefix...], as: UTF16.self),
            replace: confirmed.count - prefix,
            full: String(decoding: latest, as: UTF16.self))
    }
}
