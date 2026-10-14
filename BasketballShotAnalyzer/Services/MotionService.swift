@preconcurrency import CoreMotion
import Foundation

final class MotionService: @unchecked Sendable {
    var onUpdate: (@Sendable (_ pitch: Double, _ roll: Double) -> Void)?

    private let manager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private var smoothPitch: Double?
    private var smoothRoll: Double?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 15.0

        manager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }

            let horizontal = sqrt(gravity.x * gravity.x + gravity.y * gravity.y)
            let pitch = atan2(gravity.z, horizontal) * 180 / .pi

            let s: Double = gravity.x <= 0 ? 1 : -1
            let roll = atan2(s * gravity.y, s * -gravity.x) * 180 / .pi

            let p = (self.smoothPitch.map { $0 * 0.7 + pitch * 0.3 }) ?? pitch
            let r = (self.smoothRoll.map { $0 * 0.7 + roll * 0.3 }) ?? roll
            self.smoothPitch = p
            self.smoothRoll = r

            self.onUpdate?(p, r)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        smoothPitch = nil
        smoothRoll = nil
    }
}
