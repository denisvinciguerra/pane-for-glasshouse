import Foundation
import Observation

/// What the typing answers say about the field in front of the TV.
public enum TypingNotice: Equatable, Sendable {
    /// `method: "none"`: no text field takes the typing.
    case noField
    /// `method: "keys"`: the text arrives in lowercase.
    case lowercase
    /// The last text request got no answer.
    case notSent
}

/// Sends what is typed in the pointer pad to the TV, one request at a time, and keeps the echo the
/// pad shows. The view reports its field's changes and the few keys that mean something else when
/// nothing is typed; it calls `forget()` when the TV's focus may have moved.
@MainActor @Observable public final class TextTyping {
    public private(set) var echo: TypingEcho
    public private(set) var notice: TypingNotice?
    /// When "Sent" was last shown; the view shows it for 1.4 s.
    public private(set) var sentAt: TimeInterval?
    /// The view empties its field (after a partial `keys` send, Esc, Return, forget).
    @ObservationIgnored public var clearField: (@MainActor () -> Void)?

    /// The TV the text goes to: a view makes a new `TextTyping` for another one.
    @ObservationIgnored public let session: TVSession
    @ObservationIgnored private let now: @MainActor () -> TimeInterval
    @ObservationIgnored private var sync = TextSync()
    /// The text the field holds, composition aside.
    @ObservationIgnored private var typed = ""
    /// An edit's answer is awaited.
    @ObservationIgnored private var editOut = false
    /// A submit's answer is awaited: edits wait for it, in `typed`.
    @ObservationIgnored private var submitOut = false
    /// Return was pressed: the submit goes once the text has reached the TV.
    @ObservationIgnored private var submitQueued = false
    /// Bumped when the text is forgotten: an answer to an older request is about what was in front then.
    @ObservationIgnored private var generation = 0

    public init(session: TVSession, reducedMotion: Bool = false,
                now: @escaping @MainActor () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }) {
        self.session = session
        self.now = now
        echo = TypingEcho(reducedMotion: reducedMotion)
    }

    // MARK: Field and keys

    /// The field changed. Returns the text the field must hold (cut by `TextSync.limited`).
    /// What is being composed shows like the rest, but goes out only once committed.
    @discardableResult public func fieldChanged(_ text: String, composing: Bool = false) -> String {
        if composing {
            echo.textChanged(text, at: now())
            return text
        }
        let limited = TextSync.limited(text)
        typed = limited
        echo.textChanged(limited, at: now())
        advanceText()
        return limited
    }

    /// Submits the text on the TV, or presses OK when nothing is typed.
    public func returnPressed() {
        guard !typed.isEmpty else {
            send(.rcu(.ok))
            return
        }
        echo.leave(at: now())
        submitQueued = true
        advanceText()
    }

    /// The TV's field may hold text Pane does not know of.
    public func backspaceOnEmpty() {
        send(.keyboardKey("backspace"))
    }

    /// Esc. True when there was text: emptied here and on the TV, echo leaves. False: nothing done,
    /// the key goes on as it does today.
    public func escapePressed() -> Bool {
        guard !typed.isEmpty else { return false }
        echo.leave(at: now())
        submitQueued = false
        clearField?()
        fieldChanged("")
        return true
    }

    /// Mac and hardware keyboards only: on the on-screen keyboard, space is always a space.
    public func spaceOnEmpty() {
        send(.media(.playPause))
    }

    /// The session's `focusEpoch` then moves, and the view forgets the text.
    public func arrow(_ key: RemoteKey) {
        send(.rcu(key))
    }

    /// The remote's Back, for the Mac pad's right button. The focus moves, as with an arrow.
    public func back() {
        send(.rcu(.back))
    }

    /// The TV's focus may have moved: the text is forgotten, on Pane's side only. Nothing is sent.
    public func forget() {
        sync.forget()
        generation += 1
        submitQueued = false
        typed = ""
        echo.reset()
        notice = nil
        clearField?()
    }

    private func send(_ command: Command) {
        Task { [session] in await session.send(command) }
    }

    // MARK: Text

    /// Moves the text along: an edit if the field has changed, else the submit waiting. While an edit
    /// is out, `edited(to:)` only notes the text; while a submit is out, it all waits for its answer.
    private func advanceText() {
        guard !submitOut else { return }
        if let command = sync.edited(to: typed) {
            sendEdit(command)
        } else if !editOut, submitQueued {
            sendSubmit()
        }
    }

    private func sendEdit(_ command: Command) {
        editOut = true
        request(command) { $0.editAnswered($1) }
    }

    /// A failure leaves the text as it is, and the next change tries again: it is not retried from here.
    /// The submit waiting is dropped: Enter would land on a field missing the last keystrokes.
    private func editAnswered(_ result: ControlResult?) {
        editOut = false
        let answer = sync.acknowledged(ok: result?.ok ?? false, sent: result?.sent)
        if answer.clearField {
            // Part of it reached the TV: nothing is typed again, nothing is submitted.
            submitQueued = false
            emptyField()
        } else if let next = answer.next {
            // After a success, or a stale answer, which says nothing of the text now.
            sendEdit(next)
        } else if result?.ok == true {
            if submitQueued { sendSubmit() }
        } else {
            submitQueued = false
        }
    }

    private func sendSubmit() {
        submitQueued = false
        let command = sync.submit()
        emptyField()
        submitOut = true
        // Not for `acknowledged`, which would take it for an edit's answer.
        request(command) { typing, result in
            typing.submitOut = false
            if result?.ok == true { typing.sentAt = typing.now() }
            typing.advanceText()
        }
    }

    /// Sends one text request. The answer is read for the notice unless the text was forgotten since.
    private func request(_ command: Command,
                         answered: @escaping @MainActor (TextTyping, ControlResult?) -> Void) {
        let asked = generation
        Task { [weak self, session] in
            let result = await session.sendText(command)
            guard let self else { return }
            if asked == self.generation { self.read(result) }
            answered(self, result)
        }
    }

    /// The way the text went; nil for a request that failed or was blocked. A refusal shows "not sent"
    /// unless its method says why.
    private func read(_ result: ControlResult?) {
        guard let result else {
            notice = .notSent
            return
        }
        switch result.method {
        case "none": notice = .noField
        case "keys": notice = .lowercase
        default:
            if !result.ok { notice = .notSent }
            else if result.method == "ime" || result.method == "page" || notice == .notSent { notice = nil }
        }
    }

    /// Empties the field here and in the view; the echo, if leaving, keeps leaving.
    private func emptyField() {
        typed = ""
        echo.textChanged("", at: now())
        clearField?()
    }
}
