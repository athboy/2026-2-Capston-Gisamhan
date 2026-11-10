@preconcurrency import CoreMotion
import Foundation

final class MotionService: @unchecked Sendable {
    /// pitch: 카메라가 위를 보면 +, 아래를 보면 - (도)
    /// roll: 폰이 시계 방향으로 기울면 + (도)
    var onUpdate: (@Sendable (_ pitch: Double, _ roll: Double) -> Void)?

    private let manager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()

    // ⭐ 추가: 지금 화면 방향 (세로/가로에 따라 계산식이 달라요)
    private let orientationLock = NSLock()
    private var orientation: ScreenOrientation = .portrait

    // 센서 값을 부드럽게 만들기 위한 이전 값
    private var smoothPitch: Double?
    private var smoothRoll: Double?
    private var lastOrientation: ScreenOrientation = .portrait

    func setOrientation(_ newValue: ScreenOrientation) {
        orientationLock.lock()
        orientation = newValue
        orientationLock.unlock()
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 15.0

        manager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }

            self.orientationLock.lock()
            let orientation = self.orientation
            self.orientationLock.unlock()

            // 방향이 바뀌면 이전 값은 버리고 새로 시작
            if orientation != self.lastOrientation {
                self.lastOrientation = orientation
                self.smoothPitch = nil
                self.smoothRoll = nil
            }

            // 화면 기준으로 "똑바로 세웠을 때 1이 되는 값(vertical)"과 "옆으로 기운 정도(side)"
            let vertical: Double
            let side: Double
            switch orientation {
            case .portrait:
                vertical = -g.y
                side = g.x
            case .landscapeRight:   // 홈 표시줄이 오른쪽
                vertical = -g.x
                side = -g.y
            case .landscapeLeft:    // 홈 표시줄이 왼쪽
                vertical = g.x
                side = g.y
            }

            let pitch = atan2(g.z, vertical) * 180 / .pi
            let roll = atan2(side, vertical) * 180 / .pi

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
