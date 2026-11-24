import UIKit

@MainActor final class PointerPadHaptics {
    private lazy var generator = UIImpactFeedbackGenerator(style: .medium)

    func impact(enabled: Bool) {
        guard enabled, UIApplication.shared.applicationState == .active else { return }
        generator.impactOccurred()
        generator.prepare()
    }
}
