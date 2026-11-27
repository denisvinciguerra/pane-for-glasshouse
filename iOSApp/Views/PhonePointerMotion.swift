import Observation
import CoreMotion
import PaneKit
import UIKit

@MainActor @Observable final class PhonePointerMotion {
    private(set) var isDriving = false
    var hapticsEnabled = true
    var sensitivity = 1.0
    @ObservationIgnored private let feedback = PointerPadHaptics()
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var movement = MotionPointer()
    @ObservationIgnored private var axes = MotionPointerAxes()
    @ObservationIgnored private var filter = MotionPointerFilter()
    @ObservationIgnored private var lastSampleTime: TimeInterval?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private weak var controller: PointerController?

    let available: Bool

    init() {
        available = UIDevice.current.userInterfaceIdiom == .phone && manager.isDeviceMotionAvailable
    }

    func start(controller: PointerController) {
        stop()
        guard available else { return }
        self.controller = controller
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        // Poll at a steady screen cadence instead of forwarding uneven sensor callback tasks.
        let target = MotionFrameTarget { [weak self] link in self?.frame(link) }
        let link = CADisplayLink(target: target, selector: #selector(MotionFrameTarget.frame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        isDriving = true
    }

    private func frame(_ link: CADisplayLink) {
        guard let data = manager.deviceMotion else { return }
        guard link.timestamp - data.timestamp < 0.1 else { stop(); return }
        guard data.timestamp.isFinite, lastSampleTime.map({ data.timestamp > $0 }) ?? true else { return }
        lastSampleTime = data.timestamp
        // Sensor time keeps speed independent of display callbacks that repeat or skip samples.
        let rotation = SIMD3(data.rotationRate.x, data.rotationRate.y, data.rotationRate.z)
        let gravity = SIMD3(data.gravity.x, data.gravity.y, data.gravity.z)
        let rates = axes.rates(rotation: rotation, gravity: gravity)
        let smooth = filter.rates(pitch: rates.pitch, yaw: rates.yaw, time: data.timestamp)
        let delta = movement.move(x: smooth.pitch, y: smooth.yaw, time: data.timestamp, sensitivity: sensitivity)
        if delta.dx != 0 || delta.dy != 0 { controller?.move(dx: delta.dx, dy: delta.dy) }
    }

    func impact() {
        feedback.impact(enabled: hapticsEnabled)
    }

    func stop() {
        guard displayLink != nil else { return }
        isDriving = false
        controller?.discardPendingMoves()
        displayLink?.invalidate()
        displayLink = nil
        controller = nil
        manager.stopDeviceMotionUpdates()
        lastSampleTime = nil
        movement.reset()
        axes.reset()
        filter.reset()
        impact()
    }
}

@MainActor private final class MotionFrameTarget: NSObject {
    let tick: (CADisplayLink) -> Void
    init(_ tick: @escaping (CADisplayLink) -> Void) { self.tick = tick }
    @objc func frame(_ link: CADisplayLink) { tick(link) }
}
