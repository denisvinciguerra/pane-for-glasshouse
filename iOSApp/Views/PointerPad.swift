import PaneKit
import SwiftUI
import UIKit

/// The pointer's pad: the touch surface, the letters typed for the TV over the help, and in the
/// bottom right corner the keyboard icon, which raises the on-screen keyboard and lowers it again
/// (mockups/2026-11-19-saisie-texte/iphone-clavier.html, option 2). With a hardware keyboard, the
/// pad takes the keys as soon as it shows, as on the Mac. The keys go to the pad only while it can
/// send and nothing covers it: disabled ("Edit" of the pins, a TV out of reach), under a sheet or in
/// the background, the keyboard goes; a hardware keyboard's keys come back to the pad afterwards.
struct PointerPad: View {
    let controller: PointerController
    let typing: TextTyping
    @State private var field = PadField()
    @Environment(\.keyboard) private var keyboard
    @Environment(\.hardwareKeyboard) private var hardware
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.sheetOverRemote) private var sheetOverRemote
    @Environment(\.palette) private var palette

    /// The icon's face, and its room in the pad's corner.
    private static let icon = CGSize(width: 34, height: 28)
    private static let iconMargin: CGFloat = 8

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PointerSurface(controller: controller, typing: typing, field: field, keyboard: keyboard,
                           takesKeys: isEnabled && scenePhase != .background && !sheetOverRemote,
                           hardware: hardware?.connected == true, background: UIColor(palette.bg))
            TypingEchoView(typing: typing, cornerRoom: Self.icon.width + Self.iconMargin + 4)
            keyboardIcon
        }
    }

    /// Marked while the keyboard is up; a finger's target around its face.
    private var keyboardIcon: some View {
        Button { field.toggle() } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 13, weight: .light))
                .frame(width: Self.icon.width, height: Self.icon.height)
                .frame(width: Metrics.minTouch, height: Metrics.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyboardIconStyle(on: field.up, size: Self.icon))
        .padding(.trailing, Self.iconMargin - (Metrics.minTouch - Self.icon.width) / 2)
        .padding(.bottom, Self.iconMargin - (Metrics.minTouch - Self.icon.height) / 2)
        .accessibilityLabel(Text("Type on the TV"))
        .accessibilityIdentifier("remote.pointerKeyboard")
        .accessibilityAddTraits(field.up ? .isSelected : [])
    }
}

/// The icon's face as the mockup draws it: edged on the pad, filled while the keyboard is up; a key's
/// corners, in proportion to its height.
private struct KeyboardIconStyle: ButtonStyle {
    let on: Bool
    let size: CGSize
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.keyRadius * size.height / Metrics.buttonHeight)
        return configuration.label
            .foregroundStyle(on ? palette.bg : palette.fg)
            .background {
                ZStack {
                    // Over the letters, which may reach the corner.
                    palette.bg
                    on ? palette.fg.opacity(0.92) : palette.key
                    if configuration.isPressed { palette.fg.opacity(0.16) }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(on ? palette.fg : palette.line, lineWidth: 1))
                .frame(width: size.width, height: size.height)
            }
            .compositingGroup()
            .opacity(isEnabled ? 1 : 0.35)
    }
}

/// The pad's text field, as the keyboard icon sees it: whether it has the keys, and the touch that
/// gives them or takes them back.
@MainActor @Observable final class PadField {
    /// The field has the keys: the on-screen keyboard is up, unless a hardware keyboard types.
    fileprivate(set) var up = false
    @ObservationIgnored fileprivate weak var field: TypingTextField?

    func toggle() {
        guard let field else { return }
        if field.isFirstResponder {
            _ = field.resignFirstResponder()
        } else {
            _ = field.becomeFirstResponder()
        }
    }
}

/// The scroll view outside the pad keeps its pan; inside, it waits for the pad's gestures instead.
/// The text field sits at the bottom of the pad; when the on-screen keyboard rises, the scroll view
/// scrolls the pad above it.
final class PointerUIView: UIView {
    /// The room left under the pad, above the keyboard.
    private static let keyboardMargin: CGFloat = 8

    let field: TypingTextField
    private var scrollViews: [UIScrollView] = []
    /// The pad can send (enabled, in front): otherwise the keyboard goes.
    private(set) var takesKeys = false
    /// A hardware keyboard is attached: the field takes the keys as the pad shows.
    private var hardware = false

    init(field: TypingTextField) {
        self.field = field
        super.init(frame: .zero)
        addSubview(field)
        let center = NotificationCenter.default
        for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardDidShowNotification] {
            center.addObserver(self, selector: #selector(keyboardShows), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        // At the bottom: the system, should it scroll to the field itself, shows the whole pad.
        field.frame = CGRect(x: bounds.midX, y: bounds.maxY - 1, width: 1, height: 1)
    }

    func update(takesKeys: Bool, hardware: Bool) {
        let focus = takesKeys && hardware && !(self.takesKeys && self.hardware)
        self.takesKeys = takesKeys
        self.hardware = hardware
        if !takesKeys, field.isFirstResponder { _ = field.resignFirstResponder() }
        if focus { focusSoon() }
    }

    /// Gives the field the keys on the next turn, once SwiftUI has placed the pad.
    private func focusSoon() {
        Task { @MainActor [weak self] in
            guard let self, self.window != nil, self.takesKeys, self.hardware,
                  !self.field.isFirstResponder else { return }
            _ = self.field.becomeFirstResponder()
        }
    }

    // MARK: Keyboard

    @objc private func keyboardShows(_ notification: Notification) {
        guard field.isFirstResponder,
              let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        // After SwiftUI has made room for the keyboard.
        Task { @MainActor [weak self] in self?.keepAbove(keyboard: frame) }
    }

    /// Scrolls the nearest scroll view just enough for the pad to show above the keyboard, its top
    /// first should it not fit.
    private func keepAbove(keyboard: CGRect) {
        guard let window, let scroll = enclosingScrollView else { return }
        window.layoutIfNeeded()
        let pad = convert(bounds, to: scroll)
        let keyboardTop = scroll.convert(keyboard, from: window.screen.coordinateSpace).minY
        let insets = scroll.adjustedContentInset
        let visibleTop = scroll.bounds.minY + insets.top
        let visibleBottom = min(keyboardTop, scroll.bounds.maxY - insets.bottom)
        let needed = min(pad.maxY + Self.keyboardMargin - visibleBottom, pad.minY - visibleTop)
        guard needed > 0.5 else { return }
        let most = max(-insets.top, scroll.contentSize.height + insets.bottom - scroll.bounds.height)
        let y = min(scroll.contentOffset.y + needed, most)
        guard y > scroll.contentOffset.y else { return }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: true)
    }

    private var enclosingScrollView: UIScrollView? {
        var parent = superview
        while let view = parent {
            if let scroll = view as? UIScrollView { return scroll }
            parent = view.superview
        }
        return nil
    }

    // MARK: Scrolling held

    func holdScrolling() {
        var parent = superview
        while let view = parent {
            if let scroll = view as? UIScrollView {
                scrollViews.append(scroll)
                scroll.isScrollEnabled = false
            }
            parent = view.superview
        }
    }

    func restoreScrolling() {
        for scroll in scrollViews { scroll.isScrollEnabled = true }
        scrollViews.removeAll()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        restoreScrolling()
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        restoreScrolling()
        super.touchesCancelled(touches, with: event)
    }

    override func didMoveToWindow() {
        if window == nil { restoreScrolling() }
        super.didMoveToWindow()
        if window != nil, takesKeys, hardware { focusSoon() }
    }
}

/// A touch surface with separate one- and two-finger pans: the first moves, the second scrolls. Each
/// gesture forgets the text on Pane's side: the TV's focus may move.
private struct PointerSurface: UIViewRepresentable {
    let controller: PointerController
    let typing: TextTyping
    let field: PadField
    let keyboard: KeyboardController?
    let takesKeys: Bool
    let hardware: Bool
    /// The screen's, under the iPhone's bar above the keyboard.
    let background: UIColor

    func makeUIView(context: Context) -> PointerUIView {
        let text = TypingTextField(typing: typing)
        text.keyboard = keyboard
        text.accessoryBackground = background
        let view = PointerUIView(field: text)
        view.isMultipleTouchEnabled = true
        let move = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.moved(_:)))
        move.minimumNumberOfTouches = 1
        move.maximumNumberOfTouches = 1
        move.delegate = context.coordinator
        view.addGestureRecognizer(move)
        let scroll = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.scrolled(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        scroll.delegate = context.coordinator
        view.addGestureRecognizer(scroll)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.require(toFail: scroll)
        view.addGestureRecognizer(tap)
        field.field = text
        text.addAction(UIAction { [weak field, weak text, weak view] _ in
            let holds = text?.isFirstResponder == true
            field?.up = holds
            // The keys are the pad's while its field holds them: once lowered, a hardware keyboard's
            // keys press the buttons again. Lowered by a sheet, the background or the pad turning off,
            // `takesKeys` is false already: left as it is (`closeTyping` ends it where it must), so a
            // letter caught while a sheet goes still can't fire a pin.
            if holds { text?.keyboard?.typing = true }
            else if view?.takesKeys == true { text?.keyboard?.typing = false }
        }, for: [.editingDidBegin, .editingDidEnd])
        typing.clearField = { [weak text] in text?.setText("") }
        view.update(takesKeys: takesKeys, hardware: hardware)
        return view
    }

    func updateUIView(_ view: PointerUIView, context: Context) {
        view.field.keyboard = keyboard
        view.field.accessoryBackground = background
        view.update(takesKeys: takesKeys, hardware: hardware)
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller, typing: typing) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let controller: PointerController
        private let typing: TextTyping
        private var moveCarry = CGPoint.zero
        private var scrollCarry = CGPoint.zero

        init(controller: PointerController, typing: TextTyping) {
            self.controller = controller
            self.typing = typing
        }

        func gestureRecognizer(_ first: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith second: UIGestureRecognizer) -> Bool { true }

        private func finish(_ gesture: UIGestureRecognizer) {
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                (gesture.view as? PointerUIView)?.restoreScrolling()
            }
        }

        @objc func moved(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                moveCarry = .zero
                typing.forget()
                (gesture.view as? PointerUIView)?.holdScrolling()
            }
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            moveCarry.x += translation.x * 1.5
            moveCarry.y += translation.y * 1.5
            let dx = Int(moveCarry.x)
            let dy = Int(moveCarry.y)
            moveCarry.x -= CGFloat(dx)
            moveCarry.y -= CGFloat(dy)
            if dx != 0 || dy != 0 { controller.move(dx: dx, dy: dy) }
            finish(gesture)
        }

        @objc func scrolled(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                scrollCarry = .zero
                typing.forget()
                (gesture.view as? PointerUIView)?.holdScrolling()
            }
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            scrollCarry.x -= translation.x / 4
            scrollCarry.y -= translation.y / 4
            let dx = Int(scrollCarry.x)
            let dy = Int(scrollCarry.y)
            scrollCarry.x -= CGFloat(dx)
            scrollCarry.y -= CGFloat(dy)
            if dx != 0 || dy != 0 { controller.scroll(dx: dx, dy: dy) }
            finish(gesture)
        }

        @objc func tapped() {
            typing.forget()
            controller.click()
        }
    }
}
