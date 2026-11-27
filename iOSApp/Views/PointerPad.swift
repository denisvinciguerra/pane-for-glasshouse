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
    @State private var settingsShown = false
    @State private var clickCount = 0
    @State private var clickFlash = false
    @State private var touchDriving = false
    @AppStorage("phonePointerHaptics") private var hapticsEnabled = true
    @AppStorage("phoneTouchpadSensitivity") private var touchSensitivity = 1.0
    @AppStorage("phoneTouchpadHaptics") private var touchHaptics = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var field = PadField()
    @State private var motion = PhonePointerMotion()
    @AppStorage("phonePointerMotion") private var motionSelected = false
    @AppStorage("phonePointerSensitivity") private var sensitivity = 1.0
    @Environment(\.keyboard) private var keyboard
    @Environment(\.hardwareKeyboard) private var hardware
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.sheetOverRemote) private var sheetOverRemote
    @Environment(\.palette) private var palette

    /// The icon's face, and its room in the pad's corner.
    private static let icon = CGSize(width: 38, height: 28)
    private static let iconMargin: CGFloat = 8

    private var motionMode: Bool { motion.available && motionSelected }
    private var canDrive: Bool { isEnabled && scenePhase == .active && !sheetOverRemote && !field.up && !settingsShown }

    private var pointerActive: Bool { motionMode ? motion.isDriving : touchDriving }
    private var borderVisible: Bool { clickFlash || pointerActive }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Under the pad, whose letters cover it while they show.
            VStack(spacing: 4) {
                Group {
                    if motionMode {
                        if motion.isDriving { Text("Pointer active") }
                        else { Text("Hold and point · Tap to click") }
                        Text("Use two fingers to scroll")
                    } else {
                        Text("Slide to move · Tap to click\nUse two fingers to scroll")
                    }
                }
                .foregroundStyle(palette.label)
                Text("Tap the keyboard to type on the TV")
                    .foregroundStyle(palette.fg.opacity(0.85))
            }
            .font(.manrope(points: 13))
            .multilineTextAlignment(.center)
            .padding(.top, motion.available ? 14 : 0)
            .allowsHitTesting(false)
            // Fills the touch surface and carries its id: the app previews read the pad's frame from it.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.accessibility, Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hint + Text(verbatim: " ") + Text("Tap the keyboard to type on the TV"))
            .accessibilityIdentifier("remote.pointerPad")
            PointerSurface(controller: controller, typing: typing, field: field, keyboard: keyboard,
                           takesKeys: isEnabled && scenePhase != .background && !sheetOverRemote && !settingsShown,
                           hardware: hardware?.connected == true, background: UIColor(palette.bg),
                           motion: motion, motionMode: motionMode, canDrive: canDrive,
                           touchEnabled: isEnabled && scenePhase == .active && !sheetOverRemote && !settingsShown,
                           touchSensitivity: touchSensitivity, touchHaptics: touchHaptics,
                           clicked: { clickCount &+= 1 }, drivingChanged: { touchDriving = $0 })
            TypingEchoView(typing: typing, cornerRoom: 2 * Metrics.minTouch + 16)
            padControls
            if motion.available { modePicker }
        }
        .overlay {
            if borderVisible {
                RoundedRectangle(cornerRadius: Metrics.keyRadius)
                    .strokeBorder(palette.fg.opacity(clickFlash ? 1 : 0.65), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: borderVisible)
        .task(id: clickCount) {
            guard clickCount > 0 else { return }
            clickFlash = true
            do { try await Task.sleep(for: .milliseconds(120)) }
            catch { return }
            clickFlash = false
        }
        .sheet(isPresented: $settingsShown, onDismiss: { keyboard?.typing = false }) {
            PointerSettingsView(includesMotion: motion.available)
        }
        .onChange(of: hapticsEnabled, initial: true) { _, value in motion.hapticsEnabled = value }
        .onChange(of: sensitivity, initial: true) { _, value in motion.sensitivity = value }
        .onChange(of: canDrive) { _, enabled in if !enabled { motion.stop() } }
        .onChange(of: motionMode) { settingsShown = false; motion.stop() }
        .onDisappear {
            motion.stop()
            clickFlash = false
            touchDriving = false
            clickCount = 0
        }
    }

    /// The help for the pad's mode, as VoiceOver reads it.
    private var hint: Text {
        guard motionMode else { return Text("Slide to move · Tap to click\nUse two fingers to scroll") }
        return (motion.isDriving ? Text("Pointer active") : Text("Hold and point · Tap to click"))
            + Text(verbatim: " ") + Text("Use two fingers to scroll")
    }

    /// "Touchpad  Motion" in the pad's top left corner, the chosen one underlined, as the Mac's
    /// "Drag | ⌥ held" (mockups/2026-11-27-mode-pointeur/mode.html, A). Only on an iPhone with a gyroscope.
    private var modePicker: some View {
        HStack(spacing: 0) {
            modeWord("Touchpad", motion: false)
            modeWord("Motion", motion: true)
        }
        .padding(.leading, 12 - Self.wordRoom)
        .padding(.top, 10 - Self.wordRoom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Pointer mode"))
    }

    /// Room around a word for a finger, beyond its letters.
    private static let wordRoom: CGFloat = 8

    private func modeWord(_ title: LocalizedStringKey, motion chosenMotion: Bool) -> some View {
        let chosen = motionSelected == chosenMotion
        return Button { motionSelected = chosenMotion } label: {
            Text(title)
                .sectionLabelStyle()
                .foregroundStyle(chosen ? palette.fg : palette.label)
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(chosen ? palette.fg : .clear).frame(height: 1)
                }
                .padding(Self.wordRoom)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var padControls: some View {
        HStack(spacing: 0) {
            Button {
                motion.stop()
                controller.discardPendingMoves()
                field.dismiss()
                keyboard?.typing = true
                settingsShown = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .light))
                    .frame(width: Metrics.minTouch, height: Metrics.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KeyboardIconStyle(on: false, size: Self.icon))
            .accessibilityLabel(Text("Pointer settings"))
            .accessibilityIdentifier("remote.pointerSettings")
            keyboardButton
        }
        .padding(.trailing, Self.iconMargin - (Metrics.minTouch - Self.icon.width) / 2)
        .padding(.bottom, Self.iconMargin - (Metrics.minTouch - Self.icon.height) / 2)
    }

    private var keyboardButton: some View {
        Button { field.toggle() } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 13, weight: .light))
                .frame(width: Self.icon.width, height: Self.icon.height)
                .frame(width: Metrics.minTouch, height: Metrics.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyboardIconStyle(on: field.up, size: Self.icon))
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

    func dismiss() { _ = field?.resignFirstResponder() }

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
    var touchBegan: (() -> Void)?
    var touchEnded: (() -> Void)?
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

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if event?.allTouches?.count == 1 { touchBegan?() }
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchEnded?()
        restoreScrolling()
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchEnded?()
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
    let motion: PhonePointerMotion
    let motionMode: Bool
    let canDrive: Bool
    let touchEnabled: Bool
    let touchSensitivity: Double
    let touchHaptics: Bool
    let clicked: () -> Void
    let drivingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> PointerUIView {
        let text = TypingTextField(typing: typing)
        text.keyboard = keyboard
        text.accessoryBackground = background
        let view = PointerUIView(field: text)
        view.touchBegan = { [weak coordinator = context.coordinator] in coordinator?.touchBegan() }
        view.touchEnded = { [weak motion] in motion?.stop() }
        view.isMultipleTouchEnabled = true
        let move = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.moved(_:)))
        move.minimumNumberOfTouches = 1
        move.maximumNumberOfTouches = 1
        move.delegate = context.coordinator
        view.addGestureRecognizer(move)
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.15
        hold.cancelsTouchesInView = false
        hold.allowableMovement = 1000
        hold.numberOfTouchesRequired = 1
        hold.delegate = context.coordinator
        view.addGestureRecognizer(hold)
        context.coordinator.moveGesture = move
        context.coordinator.holdGesture = hold
        let scroll = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.scrolled(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        scroll.delegate = context.coordinator
        view.addGestureRecognizer(scroll)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.require(toFail: scroll)
        tap.require(toFail: hold)
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
        context.coordinator.update(motionMode: motionMode, canDrive: canDrive, touchEnabled: touchEnabled, sensitivity: touchSensitivity, haptics: touchHaptics, clicked: clicked, drivingChanged: drivingChanged)
        return view
    }

    func updateUIView(_ view: PointerUIView, context: Context) {
        context.coordinator.update(motionMode: motionMode, canDrive: canDrive, touchEnabled: touchEnabled, sensitivity: touchSensitivity, haptics: touchHaptics, clicked: clicked, drivingChanged: drivingChanged)
        view.field.keyboard = keyboard
        view.field.accessoryBackground = background
        view.update(takesKeys: takesKeys, hardware: hardware)
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller, typing: typing, motion: motion) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let controller: PointerController
        private let typing: TextTyping
        private let motion: PhonePointerMotion
        weak var moveGesture: UIPanGestureRecognizer?
        weak var holdGesture: UILongPressGestureRecognizer?
        private let touchFeedback = PointerPadHaptics()
        private var clicked: () -> Void = {}
        private var drivingChanged: (Bool) -> Void = { _ in }
        private var touchDriving = false
        private var sensitivity = 1.0
        private var haptics = true
        private var usesMotion = false
        private var moveCarry = CGPoint.zero
        private var scrollCarry = CGPoint.zero

        init(controller: PointerController, typing: TextTyping, motion: PhonePointerMotion) {
            self.controller = controller
            self.typing = typing
            self.motion = motion
        }

        func update(motionMode: Bool, canDrive: Bool, touchEnabled: Bool, sensitivity: Double, haptics: Bool, clicked: @escaping () -> Void, drivingChanged: @escaping (Bool) -> Void) {
            self.clicked = clicked
            self.drivingChanged = drivingChanged
            usesMotion = motionMode
            self.sensitivity = sensitivity.isFinite ? min(max(sensitivity, 0.5), 2.5) : 1
            self.haptics = haptics
            moveGesture?.isEnabled = !motionMode && touchEnabled
            holdGesture?.isEnabled = motionMode && canDrive
            if !motionMode || !canDrive { motion.stop() }
        }

        func touchBegan() {
            guard usesMotion, holdGesture?.isEnabled == true else { return }
            motion.impact()
        }

        @objc func held(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began {
                typing.forget()
                (gesture.view as? PointerUIView)?.holdScrolling()
                motion.start(controller: controller)
            } else if gesture.state != .changed {
                motion.stop()
                (gesture.view as? PointerUIView)?.restoreScrolling()
            }
        }

        func gestureRecognizer(_ first: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith second: UIGestureRecognizer) -> Bool { true }

        private func finish(_ gesture: UIGestureRecognizer) {
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                (gesture.view as? PointerUIView)?.restoreScrolling()
                if touchDriving {
                    touchDriving = false
                    drivingChanged(false)
                    touchFeedback.impact(enabled: haptics)
                }
            }
        }

        @objc func moved(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                touchDriving = true
                drivingChanged(true)
                touchFeedback.impact(enabled: haptics)
                moveCarry = .zero
                typing.forget()
                (gesture.view as? PointerUIView)?.holdScrolling()
            }
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            moveCarry.x += translation.x * 1.5 * sensitivity
            moveCarry.y += translation.y * 1.5 * sensitivity
            let dx = Int(moveCarry.x)
            let dy = Int(moveCarry.y)
            moveCarry.x -= CGFloat(dx)
            moveCarry.y -= CGFloat(dy)
            if dx != 0 || dy != 0 { controller.move(dx: dx, dy: dy) }
            finish(gesture)
        }

        @objc func scrolled(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                motion.stop()
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
            clicked()
            // In Motion, the finger's touch already buzzed.
            if !usesMotion { touchFeedback.impact(enabled: haptics) }
            typing.forget()
            controller.click()
        }
    }
}
