import AppKit
import PaneKit
import SwiftUI

/// A key in a ruled box, dashed without one. A click makes it amber and the next key pressed in
/// its window is handed on (`KeyRecording`): ⎋ cancels, ⌫ alone clears (nil), any other key is
/// recorded. A click elsewhere, or the window losing the keyboard, cancels. The keys it catches
/// go nowhere else: nothing reaches the TV from this window.
struct KeyRecorder: View {
    let binding: KeyBinding?
    let layout: CurrentKeyboardLayout
    let onRecord: (KeyBinding?) -> Void
    @State private var listener = KeyListener()
    @Environment(\.palette) private var palette

    init(binding: KeyBinding?, layout: CurrentKeyboardLayout, onRecord: @escaping (KeyBinding?) -> Void) {
        self.binding = binding
        self.layout = layout
        self.onRecord = onRecord
    }

    var body: some View {
        let recording = listener.isListening
        let label = binding.map { KeyLabel.text($0, layout: layout) }
        Button {
            listener.start { input in
                switch input {
                case .cancel, .ignore: break
                case .clear: onRecord(nil)
                case .record(let key): onRecord(key)
                }
            }
        } label: {
            Text(verbatim: recording ? "?" : label ?? "·")
                .font(.manrope(10.5, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(recording ? palette.accent : label == nil ? palette.label : palette.fg)
                .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
                .background(recording ? palette.accent.opacity(0.08) : .clear)
                .overlay(Rectangle().strokeBorder(recording ? palette.accent : palette.line,
                                                  style: StrokeStyle(lineWidth: 1, dash: label == nil && !recording ? [2, 2] : [])))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(WindowAnchor(listener: listener))
        .help(Text("Click, then press a key · ⎋ cancels · ⌫ clears"))
        .onDisappear { listener.stop() }
    }
}

/// The recorder's wait for a key: a local monitor that takes only the events of the recorder's
/// own window, and only while it waits.
@MainActor @Observable private final class KeyListener {
    private(set) var isListening = false
    @ObservationIgnored weak var view: NSView?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?

    func start(_ handle: @escaping (KeyRecording) -> Void) {
        stop()
        guard let window = view?.window else { return }
        isListening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self, weak window] event in
            MainActor.assumeIsolated {
                guard let self, let window, event.window === window else { return false }
                // A click anywhere in the window ends the wait; the click goes on.
                guard event.type == .keyDown else {
                    self.stop()
                    return false
                }
                let input = KeyRecording.input(KeyEvent(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
                                                        modifiers: KeyModifiers(event.modifierFlags)))
                if input != .ignore { self.stop() }
                handle(input)
                return true
            } ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
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
