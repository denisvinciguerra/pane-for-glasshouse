import Foundation

/// Pointer rates integrated into pixels, carrying fractions between samples.
public struct MotionPointer {
    private var previousTime: Double?
    private var carryX = 0.0
    private var carryY = 0.0

    public init() {}

    public mutating func reset() { self = MotionPointer() }

    public mutating func move(x: Double, y: Double, time: Double, sensitivity: Double) -> (dx: Int, dy: Int) {
        guard x.isFinite, y.isFinite, time.isFinite, sensitivity.isFinite else { return (0, 0) }
        defer { previousTime = time }
        guard let previousTime else { return (0, 0) }
        let dt = time - previousTime
        // A delayed sample must not move the cursor across the screen on resuming.
        guard dt > 0, dt <= 0.1 else { carryX = 0; carryY = 0; return (0, 0) }
        let scale = 1200 * min(max(sensitivity, 0.5), 2.5) * dt
        carryX += abs(y) < 0.02 ? 0 : -min(max(y, -5), 5) * scale
        carryY += abs(x) < 0.02 ? 0 : -min(max(x, -5), 5) * scale
        let dx = Int(carryX), dy = Int(carryY)
        carryX -= Double(dx)
        carryY -= Double(dy)
        return (dx, dy)
    }
}

/// Projects angular velocity onto the horizon, ignoring rotation around the pointing direction.
/// Picks the camera direction for an upright phone, or its top edge for a phone held flat.
public struct MotionPointerAxes {
    private var forward: SIMD3<Double>?

    public init() {}
    public mutating func reset() { forward = nil }

    public mutating func rates(rotation: SIMD3<Double>, gravity: SIMD3<Double>) -> (pitch: Double, yaw: Double) {
        func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { a.x*b.x + a.y*b.y + a.z*b.z }
        func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x)
        }
        guard rotation.x.isFinite, rotation.y.isFinite, rotation.z.isFinite,
              gravity.x.isFinite, gravity.y.isFinite, gravity.z.isFinite else { return (0, 0) }
        let length = sqrt(dot(gravity, gravity))
        guard length > 0.5 else { return (0, 0) }
        let up = -gravity / length
        if forward == nil {
            forward = abs(up.z) < 0.8 ? SIMD3(0, 0, -1) : SIMD3(0, 1, 0)
        }
        guard let forward else { return (0, 0) }
        let vertical = dot(up, forward)
        let horizontalSquared = 1 - vertical * vertical
        // Pointing almost straight up/down has no well-defined horizontal direction.
        guard horizontalSquared > 0.1 else { return (0, 0) }
        let right = cross(forward, up) / sqrt(horizontalSquared)
        return (dot(rotation, right), (dot(rotation, up) - vertical * dot(rotation, forward)) / horizontalSquared)
    }
}

/// A short, time-based filter for hand tremor; small cross-axis wobble fades without locking diagonals.
public struct MotionPointerFilter {
    private var previousTime: Double?
    private var pitch = 0.0
    private var yaw = 0.0

    public init() {}
    public mutating func reset() { self = MotionPointerFilter() }

    public mutating func rates(pitch nextPitch: Double, yaw nextYaw: Double, time: Double) -> (pitch: Double, yaw: Double) {
        guard nextPitch.isFinite, nextYaw.isFinite, time.isFinite else { return (0, 0) }
        defer { previousTime = time }
        guard let previousTime, time > previousTime, time - previousTime <= 0.1 else {
            pitch = 0; yaw = 0
            return (0, 0)
        }
        let speed = max(abs(nextPitch), abs(nextYaw))
        let smoothingTime = max(0.009, 0.045 / (1 + speed * speed * 8))
        let alpha = 1 - exp(-(time - previousTime) / smoothingTime)
        pitch += alpha * (nextPitch - pitch)
        yaw += alpha * (nextYaw - yaw)
        func minorAxis(_ minor: Double, major: Double) -> Double {
            guard abs(major) > 0.08 else { return minor }
            let ratio = abs(minor / major)
            let blend = min(max((ratio - 0.06) / 0.16, 0), 1)
            return minor * blend * blend * (3 - 2 * blend)
        }
        if abs(pitch) < abs(yaw) { return (minorAxis(pitch, major: yaw), yaw) }
        return (pitch, minorAxis(yaw, major: pitch))
    }
}
