import AppKit
import PaneKit
import SwiftUI

/// A key in a ruled box, dashed without one. A click makes it amber and the next key pressed in
/// its window is handed on (`KeyRecording`): ⎋ cancels, ⌫ alone clears (nil), any other key is
/// recorded. A click elsewhere, or the window losing the keyboard, cancels. The keys it catches
/// go nowhere else: nothing reaches the TV from this window.
///
/// `global`: a global shortcut's recorder, blue while it waits. The key goes through `GlobalKey`:
/// one without ⌘, ⌃ or ⌥ is refused, and the recorder asks for one under its box and keeps waiting.
struct KeyRecorder: View {
    let binding: KeyBinding?
    let layout: CurrentKeyboardLayout
    let global: Bool
    let onRecord: (KeyBinding?) -> Void
    @State private var listener = KeyListener()
    /// A key without ⌘, ⌃ or ⌥ was pressed during this wait (global only).
    @State private var needsModifier = false
    @Environment(\.palette) private var palette
    @Environment(\.appModel) private var model

    init(binding: KeyBinding?, layout: CurrentKeyboardLayout, global: Bool = false,
         onRecord: @escaping (KeyBinding?) -> Void) {
        self.binding = binding
        self.layout = layout
        self.global = global
        self.onRecord = onRecord
    }

    var body: some View {
        let recording = listener.isListening
        let label = binding.map { KeyLabel.text($0, layout: layout) }
        let tint = global ? palette.global : palette.accent
        VStack(spacing: 4) {
            Button {
                needsModifier = false
                listener.start(model: model) { event in
                    global ? handle(GlobalKey.input(event)) : handle(KeyRecording.input(event))
                }
            } label: {
                Text(verbatim: recording ? "?" : label ?? "·")
                    .font(.manrope(10.5, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(recording ? tint : label == nil ? palette.label : palette.fg)
                    .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
                    .background(recording ? tint.opacity(0.08) : .clear)
                    .overlay(Rectangle().strokeBorder(recording ? tint : palette.line,
                                                      style: StrokeStyle(lineWidth: 1, dash: label == nil && !recording ? [2, 2] : [])))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(WindowAnchor(listener: listener))
            .help(Text("Click, then press a key · ⎋ cancels · ⌫ clears"))
            if recording && needsModifier {
                Text("Add ⌘, ⌃ or ⌥")
                    .font(.manrope(10))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .onDisappear { listener.stop() }
    }

    /// Whether the wait is over.
    private func handle(_ input: KeyRecording) -> Bool {
        switch input {
        case .ignore: return false
        case .cancel: break
        case .clear: onRecord(nil)
        case .record(let key): onRecord(key)
        }
        return true
    }

    private func handle(_ input: GlobalRecording) -> Bool {
        switch input {
        case .ignore: return false
        case .needsModifier:
            needsModifier = true
            return false
        case .cancel: break
        case .clear: onRecord(nil)
        case .record(let key): onRecord(key)
        }
        return true
    }
}

/// The recorder's wait for a key: a local monitor that takes only the events of the recorder's
/// own window, and only while it waits. Meanwhile `model.keyRecorderActive` suspends the global
/// shortcuts, so that a combination Pane holds reaches the recorder instead of pressing its button.
@MainActor @Observable private final class KeyListener {
    private(set) var isListening = false
    @ObservationIgnored weak var view: NSView?
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?

    /// `handle` gets each key pressed and says whether the wait is over; the keys go no further.
    func start(model: AppModel?, _ handle: @escaping (KeyEvent) -> Bool) {
        stop()
        guard let window = view?.window else { return }
        isListening = true
        self.model = model
        model?.keyRecorderActive = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self, weak window] event in
            MainActor.assumeIsolated {
                guard let self, let window, event.window === window else { return false }
                // A click anywhere in the window ends the wait; the click goes on.
                guard event.type == .keyDown else {
                    self.stop()
                    return false
                }
                let key = KeyEvent(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
                                   modifiers: KeyModifiers(event.modifierFlags))
                if handle(key) { self.stop() }
                return true
            } ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    /// The global shortcuts come back on the next turn of the main loop, after a recording made
    /// with the key that ended the wait.
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if isListening { model?.keyRecorderActive = false }
        isListening = false
    }
}

/// An empty view behind the recorder, through which the listener finds its window.
private struct WindowAnchor: NSViewRepresentable {
    let listener: KeyListener

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        listener.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        listener.view = nsView
    }
}
