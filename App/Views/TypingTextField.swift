import AppKit

/// The pointer pad's text field: it gives the typing for the TV its accents, dead keys, input methods,
/// paste and dictation, and `TypingEchoView` draws what it holds. Transparent and 1 × 1 pt, but never
/// hidden: a hidden field could not keep the keys. Its own field editor, so that Space can mean
/// play/pause when nothing is typed, and so that the window's shared one is left as it is.
final class TypingTextField: NSTextField {
    /// Space with nothing typed: not a space.
    var spaceOnEmpty: (() -> Void)? {
        get { editor.spaceOnEmpty }
        set { editor.spaceOnEmpty = newValue }
    }

    /// The text being composed changed (a dead key, an input method): the field reports no change for it.
    var compositionChanged: (() -> Void)? {
        get { editor.markedTextChanged }
        set { editor.markedTextChanged = newValue }
    }

    /// `setText` is writing: what the field reports then is not the user's typing.
    private(set) var isWriting = false

    private var editor: TypingFieldEditor { (cell as! TypingFieldCell).editor }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        let cell = TypingFieldCell(textCell: "")
        cell.isEditable = true
        cell.isScrollable = true
        cell.usesSingleLineMode = true
        cell.lineBreakMode = .byClipping
        self.cell = cell
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        isAutomaticTextCompletionEnabled = false
        alphaValue = 0
        // `TypingEchoView` is where the text is read.
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    /// A click on its point is the pad's.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// What the field holds, read from its editor: asking the field itself would end the editing.
    var text: String { currentEditor()?.string ?? stringValue }

    /// A dead key or an input method is composing: the text is not final.
    var isComposing: Bool { (currentEditor() as? NSTextView)?.hasMarkedText() ?? false }

    /// Replaces the text, the caret after it. Ending a composition reports a change: `isWriting` says
    /// it is not the user's.
    func setText(_ text: String) {
        guard let editor = currentEditor() as? NSTextView else {
            stringValue = text
            return
        }
        isWriting = true
        defer { isWriting = false }
        editor.unmarkText()
        editor.string = text
        editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    /// Takes the keys, the caret after the text, unless it has them already.
    func focus() {
        guard let window, currentEditor() == nil else { return }
        window.makeFirstResponder(self)
        let end = (text as NSString).length
        currentEditor()?.selectedRange = NSRange(location: end, length: 0)
    }
}

private final class TypingFieldCell: NSTextFieldCell {
    let editor: TypingFieldEditor = {
        let editor = TypingFieldEditor()
        editor.isFieldEditor = true
        // The text goes to a TV's search: no replacement of what is typed, as on iOS.
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.smartInsertDeleteEnabled = false
        editor.inlinePredictionType = .no
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

private final class TypingFieldEditor: NSTextView {
    var spaceOnEmpty: (() -> Void)?
    var markedTextChanged: (() -> Void)?

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        markedTextChanged?()
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let inserted = (string as? String) ?? (string as? NSAttributedString)?.string
        if inserted == " ", self.string.isEmpty, !hasMarkedText(), let spaceOnEmpty {
            // A held Space plays or pauses once.
            if !NSApp.isKeyRepeat { spaceOnEmpty() }
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }
}

extension NSApplication {
    /// The event being handled is a key held down. Asked only of a key event: `isARepeat` raises
    /// for any other, and dictation or the Character Viewer insert text outside one.
    var isKeyRepeat: Bool {
        guard let event = currentEvent, event.type == .keyDown else { return false }
        return event.isARepeat
    }
}
