import XCTest
@testable import PaneKit

final class MotionPointerTests: XCTestCase {
    func testRotationDirectionsAndSensitivity() {
        var pointer = MotionPointer()
        _ = pointer.move(x: 0, y: 0, time: 1, sensitivity: 1)
        let delta = pointer.move(x: 0.5, y: -1, time: 1.05, sensitivity: 2)
        XCTAssertEqual(delta.dx, 120)
        XCTAssertEqual(delta.dy, -60)
    }

    func testSamplesKeepFractionalMovement() {
        var pointer = MotionPointer()
        _ = pointer.move(x: 0, y: 0, time: 0, sensitivity: 1)
        var total = 0
        for i in 1...60 {
            total += pointer.move(x: 0, y: -0.025, time: Double(i) / 60, sensitivity: 1).dx
        }
        XCTAssertEqual(Double(total), 30, accuracy: 1)
    }

    func testRateDoesNotChangeDistance() {
        func distance(rate: Int) -> Int {
            var pointer = MotionPointer()
            _ = pointer.move(x: 0, y: 0, time: 0, sensitivity: 1)
            return (1...rate).reduce(0) { total, i in
                total + pointer.move(x: 0, y: -1, time: Double(i) / Double(rate), sensitivity: 1).dx
            }
        }
        XCTAssertEqual(Double(distance(rate: 30)), Double(distance(rate: 60)), accuracy: 1)
    }

    func testUnevenSampleIntervalsKeepDistance() {
        var pointer = MotionPointer()
        let times = [0.0, 0.016, 0.05, 0.067, 0.1]
        let distance = times.reduce(0) { total, time in
            total + pointer.move(x: 0, y: -1, time: time, sensitivity: 1).dx
        }
        XCTAssertEqual(Double(distance), 120, accuracy: 1)
    }

    func testRestAndInvalidSamplesDoNotMove() {
        var pointer = MotionPointer()
        _ = pointer.move(x: 0, y: 0, time: 0, sensitivity: 1)
        let rest = pointer.move(x: 0.01, y: -0.01, time: 0.05, sensitivity: 1)
        XCTAssertEqual(rest.dx, 0)
        XCTAssertEqual(rest.dy, 0)
        XCTAssertEqual(pointer.move(x: .nan, y: 1, time: 0.06, sensitivity: 1).dx, 0)
    }

    func testResetAndLongGapDiscardOldMovement() {
        var pointer = MotionPointer()
        _ = pointer.move(x: 0, y: 1, time: 1, sensitivity: 1)
        XCTAssertEqual(pointer.move(x: 0, y: 1, time: 2, sensitivity: 1).dx, 0)
        pointer.reset()
        XCTAssertEqual(pointer.move(x: 0, y: 1, time: 3, sensitivity: 1).dx, 0)
    }

    func testHorizonAxesInPortraitLandscapeAndFlatGrips() {
        for gravity in [SIMD3<Double>(0, -1, 0), SIMD3(-1, 0, 0), SIMD3(0, 0, -1)] {
            var axes = MotionPointerAxes()
            let horizontal = axes.rates(rotation: -gravity, gravity: gravity)
            XCTAssertEqual(horizontal.yaw, 1, accuracy: 0.0001)
            XCTAssertEqual(horizontal.pitch, 0, accuracy: 0.0001)
        }
    }

    func testTiltedPhoneSeparatesYawFromPitchAndRoll() {
        let gravity = SIMD3<Double>(0, -0.8, -0.6)
        var axes = MotionPointerAxes()
        let yaw = axes.rates(rotation: -gravity, gravity: gravity)
        XCTAssertEqual(yaw.yaw, 1, accuracy: 0.0001)
        XCTAssertEqual(yaw.pitch, 0, accuracy: 0.0001)
        let pitch = axes.rates(rotation: SIMD3(1, 0, 0), gravity: gravity)
        XCTAssertEqual(pitch.pitch, 1, accuracy: 0.0001)
        XCTAssertEqual(pitch.yaw, 0, accuracy: 0.0001)
        let roll = axes.rates(rotation: SIMD3(0, 0, 1), gravity: gravity)
        XCTAssertEqual(roll.pitch, 0, accuracy: 0.0001)
        XCTAssertEqual(roll.yaw, 0, accuracy: 0.0001)
    }

    func testFlatGripAlsoIgnoresRoll() {
        var axes = MotionPointerAxes()
        let roll = axes.rates(rotation: SIMD3(0, 1, 0), gravity: SIMD3(0, 0, -1))
        XCTAssertEqual(roll.pitch, 0, accuracy: 0.0001)
        XCTAssertEqual(roll.yaw, 0, accuracy: 0.0001)
    }

    func testFilterSuppressesCrossAxisWobbleButKeepsDiagonals() {
        var filter = MotionPointerFilter()
        _ = filter.rates(pitch: 0, yaw: 0, time: 0)
        let wobble = filter.rates(pitch: 0.04, yaw: 1, time: 0.05)
        XCTAssertEqual(wobble.pitch, 0)
        XCTAssertGreaterThan(wobble.yaw, 0)
        filter.reset()
        _ = filter.rates(pitch: 0, yaw: 0, time: 0)
        let diagonal = filter.rates(pitch: 1, yaw: 1, time: 0.05)
        XCTAssertEqual(diagonal.pitch, diagonal.yaw)
        XCTAssertGreaterThan(diagonal.pitch, 0)
    }

    func testFilterResponseIsIndependentOfSampleRate() {
        func response(rate: Int) -> Double {
            var filter = MotionPointerFilter()
            _ = filter.rates(pitch: 0, yaw: 0, time: 0)
            var value = 0.0
            for i in 1...rate { value = filter.rates(pitch: 0, yaw: 1, time: Double(i) / Double(rate)).yaw }
            return value
        }
        XCTAssertEqual(response(rate: 30), response(rate: 60), accuracy: 0.0001)
    }

    func testFilterSoftensAlternatingTremorAndClearsOnReset() {
        var filter = MotionPointerFilter()
        _ = filter.rates(pitch: 0, yaw: 0, time: 0)
        for i in 1...60 {
            let value = filter.rates(pitch: 0, yaw: i.isMultiple(of: 2) ? 0.1 : -0.1, time: Double(i) / 60)
            XCTAssertLessThan(abs(value.yaw), 0.04)
        }
        filter.reset()
        XCTAssertEqual(filter.rates(pitch: 0, yaw: 1, time: 2).yaw, 0)
        XCTAssertEqual(filter.rates(pitch: 0, yaw: 1, time: 3).yaw, 0)
    }

    func testFilterRespondsQuicklyToDeliberateMovement() {
        var filter = MotionPointerFilter()
        _ = filter.rates(pitch: 0, yaw: 0, time: 0)
        let response = filter.rates(pitch: 0, yaw: 1, time: 1.0 / 60)
        XCTAssertGreaterThan(response.yaw, 0.8)
    }
}
