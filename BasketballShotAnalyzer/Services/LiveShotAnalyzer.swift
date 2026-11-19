import Vision
import CoreMedia
import CoreVideo
import CoreGraphics

/// "이게 진짜 공이다 / 진짜 슛이다"라고 인정하는 기준.
/// 숫자 일부는 앱의 "튜닝 설정" 화면에서 바꾼 값으로 읽어요.
private enum BallRule {
    /// Vision의 확신도 (0~1). 높을수록 엄격
    static var minConfidence: Float { Tuning.ballConfidence }
    /// 최소 점 개수
    static let minPoints = 5
    /// 첫 점~마지막 점 사이 최소 거리 (화면 비율). 제자리 흔들림 제거
    static var minSpan: CGFloat { Tuning.ballMinSpan }
    /// 포물선이 아래로 굽은 정도의 최소값 (a의 크기)
    static let minCurvature: CGFloat = 0.02
    /// 점들이 포물선에서 벗어나도 되는 평균 거리 (화면 비율)
    static var maxFitError: CGFloat { Tuning.ballFitError }
    /// 이 횟수만큼 연속 프레임에서 통과해야 화면에 선을 그려요
    static let minStreak = 2
    /// 공이 사라진 뒤 선을 남겨두는 시간 (초)
    static let holdSeconds = 0.5

    /// ⭐ 슛이 확정된 뒤 새 슛을 세지 않는 시간 (초) — 기본 5초 (튜닝 설정에서 변경)
    static var shotCooldown: Double { Tuning.shotCooldown }
    /// ⭐ 림에서 이만큼 떨어진 곳에서 시작한 공만 슛으로 인정 (림 근처 튕김 제거)
    static var minStartDistance: CGFloat { Tuning.shotMinStart }
    /// ⭐ 골 판정 범위 (림 반지름의 몇 배 안이면 골)
    static var makeRange: CGFloat { Tuning.makeRange }
}

final class LiveShotAnalyzer: @unchecked Sendable {
    var onRim: (@Sendable (RimCalibration) -> Void)?
    var onBall: (@Sendable ([NormalizedPoint]) -> Void)?
    var onShot: (@Sendable (ShotAnalysisReport) -> Void)?

    private struct Candidate {
        let a: CGFloat, b: CGFloat, c: CGFloat
        let confidence: Float
        let start: NormalizedPoint
        let score: CGFloat
        // ⭐ 추가: 골 판정에 쓰는 정보
        let points: [NormalizedPoint]
        let direction: CGFloat
    }

    private var handler = VNSequenceRequestHandler()
    private let trajectoryRequest: VNDetectTrajectoriesRequest
    private let rimDetector = RimAutoDetector()

    private let lock = NSLock()
    private var _rim: RimCalibration?
    private var manualRim = false
    private var _calibration: CameraCalibration?

    private var frameCount = 0
    private var pending: Candidate?
    private var lastValidTime = 0.0
    private var lastShotTime = -10.0

    private var validStreak = 0
    private var lastBallTime = 0.0
    private var trailVisible = false

    private var lastWidth = 0
    private var lastHeight = 0

    var hasModel: Bool { rimDetector != nil }

    init(configuration: TrajectoryDetectionConfiguration = .init()) {
        let request = VNDetectTrajectoriesRequest(frameAnalysisSpacing: .zero, trajectoryLength: 6)
        request.regionOfInterest = configuration.regionOfInterest
        request.objectMinimumNormalizedRadius = configuration.minimumBallRadius
        request.objectMaximumNormalizedRadius = configuration.maximumBallRadius
        trajectoryRequest = request
    }

    // MARK: - 림 (수동/자동)

    func setManualRim(_ rim: RimCalibration?) {
        lock.lock(); defer { lock.unlock() }
        if let rim {
            _rim = rim
            manualRim = true
        } else {
            manualRim = false
        }
    }

    private var currentRim: RimCalibration? {
        lock.lock(); defer { lock.unlock() }
        return _rim
    }

    func setCalibration(_ calibration: CameraCalibration?) {
        lock.lock(); defer { lock.unlock() }
        _calibration = calibration
    }

    private var currentCalibration: CameraCalibration? {
        lock.lock(); defer { lock.unlock() }
        return _calibration
    }

    /// 화면 방향이 바뀌면 림/보정 좌표가 의미가 없어지므로 지우기
    func resetForNewOrientation() {
        lock.lock()
        _rim = nil
        manualRim = false
        _calibration = nil
        lock.unlock()
    }

    private func updateRimIfNeeded(from sampleBuffer: CMSampleBuffer) {
        guard let detector = rimDetector, frameCount % 12 == 1 else { return }

        lock.lock()
        let manual = manualRim
        let old = _rim
        lock.unlock()
        guard !manual, let found = detector.detect(in: sampleBuffer) else { return }

        let smoothed: RimCalibration
        if let old {
            let k: CGFloat = 0.3
            smoothed = RimCalibration(
                center: NormalizedPoint(
                    x: old.center.x * (1 - k) + found.center.x * k,
                    y: old.center.y * (1 - k) + found.center.y * k
                ),
                widthFraction: old.widthFraction * (1 - k) + found.widthFraction * k
            )
        } else {
            smoothed = found
        }
        lock.lock(); _rim = smoothed; lock.unlock()
        onRim?(smoothed)
    }

    // MARK: - 진짜 공인지 검사

    private func isBallLike(_ o: VNTrajectoryObservation) -> Bool {
        // 1) Vision이 충분히 확신하는가
        guard o.confidence >= BallRule.minConfidence else { return false }

        // 2) 점이 충분히 많은가
        let points = o.detectedPoints
        guard points.count >= BallRule.minPoints,
              let first = points.first?.location,
              let last = points.last?.location else { return false }

        // 3) 아래로 굽은 포물선인가 (Vision 좌표는 y가 위로 증가 → a < 0)
        let coef = o.equationCoefficients
        let a = CGFloat(coef.x), b = CGFloat(coef.y), c = CGFloat(coef.z)
        guard a < -BallRule.minCurvature else { return false }

        // 4) 충분히 멀리 움직였는가 (제자리 노이즈 제거)
        guard hypot(first.x - last.x, first.y - last.y) >= BallRule.minSpan else { return false }

        // 5) 점들이 포물선 위에 잘 놓여 있는가 (들쭉날쭉한 움직임 제거)
        var sumSquares: CGFloat = 0
        for p in points {
            let x = p.location.x
            let predicted = a * x * x + b * x + c
            let diff = p.location.y - predicted
            sumSquares += diff * diff
        }
        let rms = (sumSquares / CGFloat(points.count)).squareRoot()
        return rms <= BallRule.maxFitError
    }

    // 방향이 바뀌었을 때 추적 상태를 처음부터 다시 시작
    private func resetTracking() {
        handler = VNSequenceRequestHandler()
        pending = nil
        validStreak = 0
        if trailVisible {
            trailVisible = false
            onBall?([])
        }
    }

    // MARK: - 프레임 처리 (카메라 큐에서 호출됨)

    func process(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameCount += 1
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let ratio = CGFloat(height) / CGFloat(width)

        // 영상 크기가 바뀌었다면 추적을 새로 시작
        if width != lastWidth || height != lastHeight {
            lastWidth = width
            lastHeight = height
            resetTracking()
            return
        }

        updateRimIfNeeded(from: sampleBuffer)

        do {
            try handler.perform([trajectoryRequest], on: sampleBuffer, orientation: .up)
        } catch {
            return
        }
        let observations = trajectoryRequest.results ?? []

        // "진짜 공"처럼 보이는 궤적만 화면에 보여줘요
        let ballLike = observations.filter { isBallLike($0) }
        if let visible = ballLike.max(by: {
            $0.confidence * Float($0.detectedPoints.count) < $1.confidence * Float($1.detectedPoints.count)
        }) {
            validStreak += 1
            lastBallTime = time
            if validStreak >= BallRule.minStreak {
                trailVisible = true
                onBall?(visible.detectedPoints.map { NormalizedPoint($0.location) })
            }
        } else {
            validStreak = 0
            // 공이 사라지고 0.5초가 지나면 선을 지워요 (한 번만)
            if trailVisible, time - lastBallTime > BallRule.holdSeconds {
                trailVisible = false
                onBall?([])
            }
        }

        guard let rim = currentRim else { return }

        // 슛 후보 선별
        // ⭐ 수정: 슛 확정 후 shotCooldown(기본 5초) 동안은 새 후보를 받지 않아요
        let candidates = observations.compactMap { candidate(from: $0, rim: rim) }
        if let best = candidates.min(by: { $0.score < $1.score }),
           best.score < 0.8,
           time - lastShotTime > BallRule.shotCooldown {
            if pending == nil || best.score < pending!.score { pending = best }
            lastValidTime = time
        }

        // 유효 궤적이 0.8초간 더 안 들어오면 슛이 끝난 것으로 보고 확정
        if let pending, time - lastValidTime > 0.8 {
            finalize(pending, rim: rim, heightToWidthRatio: ratio)
            self.pending = nil
            lastShotTime = time
        }
    }

    // MARK: - 후보 판정

    private func candidate(from o: VNTrajectoryObservation, rim: RimCalibration) -> Candidate? {
        // 슛 후보도 "진짜 공" 검사를 먼저 통과해야 해요
        guard isBallLike(o) else { return nil }

        let detected = o.detectedPoints.map { NormalizedPoint($0.location) }
        let all = (o.projectedPoints.isEmpty ? o.detectedPoints : o.projectedPoints)
            .map { NormalizedPoint($0.location) }
        guard detected.count >= 2, all.count >= 3,
              let first = detected.first, let last = detected.last else { return nil }

        let coef = o.equationCoefficients
        let a = CGFloat(coef.x), b = CGFloat(coef.y), c = CGFloat(coef.z)
        let rimX = rim.center.x

        guard a < -0.001 else { return nil }

        let xs = all.map(\.x)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        guard maxX - minX > 0.08 else { return nil }

        guard rimX > minX - 0.2, rimX < maxX + 0.2 else { return nil }

        let direction = last.x - first.x
        guard abs(direction) > 0.01 else { return nil }
        let apexX = -b / (2 * a)
        guard (rimX - apexX) * direction > 0 else { return nil }

        // ⭐ 추가 1: 출발점이 림에서 충분히 멀어야 해요 (림 근처에서 튕기는 공 제거)
        guard abs(first.x - rimX) >= BallRule.minStartDistance else { return nil }

        // ⭐ 추가 2: 포물선 꼭대기가 림보다 높아야 해요 (바닥에서 튀는 공 제거)
        let apexY = c - b * b / (4 * a)
        guard apexY >= rim.center.y else { return nil }

        let predictedY = a * rimX * rimX + b * rimX + c
        let verticalError = abs(predictedY - rim.center.y)
        guard verticalError < 0.2 else { return nil }

        let horizontalError = all.map { abs($0.x - rimX) }.min() ?? 1
        let score = horizontalError
            + verticalError * 2
            + (1 - CGFloat(o.confidence)) * 0.15
            + max(0, 0.5 - (maxX - minX))
        return Candidate(
            a: a, b: b, c: c,
            confidence: o.confidence,
            start: first,
            score: score,
            points: detected,
            direction: direction
        )
    }

    // MARK: - ⭐ 골 판정 (5가지 조건 반영)

        private func isMade(_ p: Candidate, rim: RimCalibration) -> Bool {
            let rimX = rim.center.x
            let rimY = rim.center.y
            let halfRim = rim.widthFraction / 2
            guard halfRim > 0 else { return false }

            // [조건 2] 공 지름(24cm) vs 림 지름(45cm) 고려해 림 안쪽 여유 범위 적용
            let innerTolerance = halfRim * min(BallRule.makeRange, 0.72)

            // [조건 5] 포물선 방정식으로 림 높이(rimY)에서의 하강 예측 x 계산
            let predictedX = predictedCrossingX(p, rimY: rimY)

            // [조건 1] 실제 관측 점들 중 림 높이를 위→아래로 가로지른 지점 찾기
            var crossX: CGFloat?
            var crossIndex: Int?
            if p.points.count >= 2 {
                for i in 1..<p.points.count {
                    let p0 = p.points[i - 1]
                    let p1 = p.points[i]
                    if p0.y >= rimY, p1.y < rimY {
                        let t = (p0.y - rimY) / (p0.y - p1.y)
                        crossX = p0.x + (p1.x - p0.x) * t
                        crossIndex = i
                        break
                    }
                }
            }

            // [조건 4] 림 근처에서 급격한 방향 전환(림 접촉) 감지
            let hitRim = detectRimContact(points: p.points, rim: rim)

            // Case A: 실제 통과 프레임이 관측된 경우
            if let x = crossX, let idx = crossIndex {
                // 1) 실제 통과 x가 림 안쪽 범위인지 확인
                guard abs(x - rimX) <= innerTolerance else { return false }

                // 2) [조건 5] 포물선 예측 위치와 크게 어긋나지 않는지 확인 (노이즈 제거)
                if let predX = predictedX {
                    guard abs(predX - rimX) <= halfRim * 0.9,
                          abs(x - predX) <= rim.widthFraction * 0.35 else { return false }
                }

                // 3) [조건 3] 통과 후 림 아래에서 계속 하강하는지 확인
                let afterPoints = Array(p.points[idx...])
                for i in 1..<afterPoints.count {
                    let prev = afterPoints[i - 1]
                    let curr = afterPoints[i]
                    // 다시 위로 튀어 오르거나 림 폭 밖으로 벗어나면 튕김(노골)
                    if curr.y > prev.y + 0.015 { return false }
                    if abs(curr.x - rimX) > rim.widthFraction * 0.75 { return false }
                }

                // 4) [조건 4] 림 접촉이 있었다면, 림 아래로 확실히 내려간 점이 있을 때만 인정
                if hitRim {
                    let confirmedBelow = afterPoints.contains {
                        $0.y < rimY - 0.02 && abs($0.x - rimX) <= halfRim
                    }
                    return confirmedBelow
                }

                return true
            }

            // Case B: 그물/프레임 누락으로 통과 순간이 안 찍힌 경우 (보수적 포물선 판정)
            // 림 접촉 의심 시 즉시 제외, 예측 위치가 림 중앙부에 정확히 들어올 때만 인정
            guard !hitRim, let predX = predictedX else { return false }
            return abs(predX - rimX) <= innerTolerance * 0.75
        }

        /// 포물선(ax² + bx + c = rimY)에서 하강 방향의 x 해 계산
        private func predictedCrossingX(_ p: Candidate, rimY: CGFloat) -> CGFloat? {
            let d = p.b * p.b - 4 * p.a * (p.c - rimY)
            guard d >= 0, p.a != 0 else { return nil }
            let root = d.squareRoot()
            let roots = [(-p.b + root) / (2 * p.a), (-p.b - root) / (2 * p.a)]
            let dir: CGFloat = p.direction >= 0 ? 1 : -1
            return roots.first { (2 * p.a * $0 + p.b) * dir < 0 }
        }

        /// 림 근처에서 공의 속도 방향이 갑자기 꺾이면(튀어 오름/반전) 림 접촉으로 판단
        private func detectRimContact(points: [NormalizedPoint], rim: RimCalibration) -> Bool {
            guard points.count >= 3 else { return false }
            let nearRange = rim.widthFraction * 0.8

            for i in 1..<(points.count - 1) {
                let p = points[i]
                let isNearRim = abs(p.x - rim.center.x) <= nearRange
                             && abs(p.y - rim.center.y) <= nearRange
                guard isNearRim else { continue }

                let v1x = p.x - points[i - 1].x, v1y = p.y - points[i - 1].y
                let v2x = points[i + 1].x - p.x, v2y = points[i + 1].y - p.y

                // 내려가다가 갑자기 위로 튕기거나(y 반전), 진행 방향이 90도 이상 꺾임(내적 < 0)
                if (v1y < 0 && v2y > 0.01) || (v1x * v2x + v1y * v2y < 0) {
                    return true
                }
            }
            return false
        }

    // MARK: - 슛 확정 → 리포트

    private func finalize(_ p: Candidate, rim: RimCalibration, heightToWidthRatio: CGFloat) {
        let calibration = currentCalibration

        let measured: Double
        if let calibration {
            guard let value = calibration.entryAngle(a: p.a, b: p.b, atX: rim.center.x) else { return }
            measured = value
        } else {
            guard let value = ShotPhysics.entryAngle(
                a: p.a, b: p.b, rimX: rim.center.x, heightToWidthRatio: heightToWidthRatio
            ) else { return }
            measured = value
        }

        // ⭐ 수정: 목표는 항상 45° 고정, 45° ±2° 안이면 "안정적"
        let target = ShotTarget.angle
        let difference = measured - target

        let feedback: FeedbackTone
        if abs(difference) <= ShotTarget.tolerance { feedback = .perfect }
        else if difference < 0 { feedback = .flat }
        else { feedback = .steep }

        let made = isMade(p, rim: rim)

        let steps = 40
        let startX = p.start.x, endX = rim.center.x
        let path = (0...steps).map { i -> NormalizedPoint in
            let x = startX + (endX - startX) * CGFloat(i) / CGFloat(steps)
            return NormalizedPoint(x: x, y: p.a * x * x + p.b * x + p.c)
        }

        onShot?(ShotAnalysisReport(
            measuredEntryAngle: measured,
            targetEntryAngle: target,
            difference: difference,
            feedback: feedback,
            path: TrajectoryPath(points: path),
            confidence: min(max(Double(p.confidence), 0), 1),
            physicalEstimate: nil,
            dynamicTargetAvailable: false,
            made: made
        ))
    }
}
