@preconcurrency import CoreMotion
import Foundation

final class MotionService: @unchecked Sendable {
    /// pitch: 카메라가 위를 보면 +, 아래를 보면 - (도)
    /// roll: 폰이 시계 방향으로 기울면 + (도)
    var onUpdate: (@Sendable (_ pitch: Double, _ roll: Double) -> Void)?

    private let manager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1   // 센서 값을 한 줄로 순서대로 처리
        return q
    }()

    // 센서 값이 부들부들 떨리지 않게 부드럽게 만들기 위한 이전 값
    private var smoothPitch: Double?
    private var smoothRoll: Double?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 15.0   // 1초에 15번 측정

        manager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }

            // 중력이 폰의 어느 방향으로 당기는지로 기울기를 계산해요
            let pitch = atan2(gravity.z, -gravity.y) * 180 / .pi
            let roll = atan2(gravity.x, -gravity.y) * 180 / .pi

            // 새 값 30% + 이전 값 70%를 섞어서 부드럽게
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
