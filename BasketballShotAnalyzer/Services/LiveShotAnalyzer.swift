import Vision
import CoreMedia
import CoreVideo
import CoreGraphics

final class LiveShotAnalyzer: @unchecked Sendable {
    var onRim: (@Sendable (RimCalibration) -> Void)?
    var onBall: (@Sendable ([NormalizedPoint]) -> Void)?
    var onShot: (@Sendable (ShotAnalysisReport) -> Void)?

    private struct Candidate {
        let a: CGFloat, b: CGFloat, c: CGFloat
        let confidence: Float
        let start: NormalizedPoint
        let score: CGFloat
    }

    private let handler = VNSequenceRequestHandler()
    private let trajectoryRequest: VNDetectTrajectoriesRequest
    private let rimDetector = RimDetector()

    private let lock = NSLock()
    private var _rim: RimCalibration?
    private var manualRim = false
    private var _calibration: CameraCalibration?   // ⭐ 추가: 고정된 보정 결과

    private var frameCount = 0
    private var pending: Candidate?
    private var lastValidTime = 0.0
    private var lastShotTime = -10.0

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
            manualRim = false   // 자동 모드로 복귀 (기존 림 값은 다음 검출 때 갱신)
        }
    }

    private var currentRim: RimCalibration? {
        lock.lock(); defer { lock.unlock() }
        return _rim
    }

    // ⭐ 추가: 보정 결과 넣기/꺼내기
    func setCalibration(_ calibration: CameraCalibration?) {
        lock.lock(); defer { lock.unlock() }
        _calibration = calibration
    }

    private var currentCalibration: CameraCalibration? {
        lock.lock(); defer { lock.unlock() }
        return _calibration
    }

    private func updateRimIfNeeded(from sampleBuffer: CMSampleBuffer) {
        // 림은 고정 물체라 매 프레임 돌릴 필요 없음 → 12프레임마다 (60fps 기준 초당 5회)
        guard let detector = rimDetector, frameCount % 12 == 1 else { return }

        lock.lock()
        let manual = manualRim
        let old = _rim
        lock.unlock()
        guard !manual, let found = detector.detect(in: sampleBuffer) else { return }

        // 지수이동평균으로 흔들림 줄이기
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

    // MARK: - 프레임 처리 (카메라 큐에서 호출됨)

    func process(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameCount += 1
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let ratio = CGFloat(CVPixelBufferGetHeight(pixelBuffer)) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))

        updateRimIfNeeded(from: sampleBuffer)

        // 이전 프레임과 비교(Optical Flow)하는 요청이라 같은 handler를 계속 재사용해야 함
        do {
            try handler.perform([trajectoryRequest], on: sampleBuffer, orientation: .up)
        } catch {
            return
        }
        let observations = trajectoryRequest.results ?? []

        // 화면에 보여줄 공 궤적 (가장 그럴듯한 것 하나)
        if let visible = observations.max(by: {
            $0.confidence * Float($0.detectedPoints.count) < $1.confidence * Float($1.detectedPoints.count)
        }) {
            onBall?(visible.detectedPoints.map { NormalizedPoint($0.location) })
        } else {
            onBall?([])
        }

        guard let rim = currentRim else { return }

        // 슛 후보 선별
        let candidates = observations.compactMap { candidate(from: $0, rim: rim) }
        if let best = candidates.min(by: { $0.score < $1.score }),
           best.score < 0.8,
           time - lastShotTime > 1.5 {
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
        let detected = o.detectedPoints.map { NormalizedPoint($0.location) }
        let all = (o.projectedPoints.isEmpty ? o.detectedPoints : o.projectedPoints)
            .map { NormalizedPoint($0.location) }
        guard detected.count >= 2, all.count >= 3,
              let first = detected.first, let last = detected.last else { return nil }

        let coef = o.equationCoefficients
        let a = CGFloat(coef.x), b = CGFloat(coef.y), c = CGFloat(coef.z)
        let rimX = rim.center.x

        // 1) 아래로 굽은 포물선 (Vision 좌표: y가 위로 증가 → a < 0)
        guard a < -0.001 else { return nil }

        // 2) 제자리 노이즈 제거
        let xs = all.map(\.x)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        guard maxX - minX > 0.08 else { return nil }

        // 3) 림 근처까지 이어지는 궤적
        guard rimX > minX - 0.2, rimX < maxX + 0.2 else { return nil }

        // 4) 림이 포물선 정점 "뒤쪽"(하강 구간)에 있어야 함 → 올라가는 중인 궤적 배제
        let direction = last.x - first.x
        guard abs(direction) > 0.01 else { return nil }
        let apexX = -b / (2 * a)
        guard (rimX - apexX) * direction > 0 else { return nil }

        // 5) 림 높이와 크게 어긋나면 배제
        let predictedY = a * rimX * rimX + b * rimX + c
        let verticalError = abs(predictedY - rim.center.y)
        guard verticalError < 0.2 else { return nil }

        let horizontalError = all.map { abs($0.x - rimX) }.min() ?? 1
        let score = horizontalError
            + verticalError * 2
            + (1 - CGFloat(o.confidence)) * 0.15
            + max(0, 0.5 - (maxX - minX))
        return Candidate(a: a, b: b, c: c, confidence: o.confidence, start: first, score: score)
    }

    // MARK: - 슛 확정 → 리포트

    private func finalize(_ p: Candidate, rim: RimCalibration, heightToWidthRatio: CGFloat) {
        // ⭐ 수정: 보정이 고정되어 있으면 보정된 값을 사용
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

        let usedRim = calibration?.calibratedRim ?? rim
        let usedRatio = calibration?.effectiveHeightToWidthRatio ?? heightToWidthRatio

        let estimate = ShotPhysics.dynamicEstimate(
            a: p.a, b: p.b,
            releasePoint: p.start,
            wrist: nil,
            rim: usedRim,
            heightToWidthRatio: usedRatio
        )
        let target = estimate?.targetEntryAngle ?? ShotPhysics.standardTargetAngle
        let difference = measured - target

        let feedback: FeedbackTone
        if abs(difference) <= 2 { feedback = .perfect }
        else if difference < 0 { feedback = .flat }
        else { feedback = .steep }

        // 화면에 그릴 포물선: 공이 처음 잡힌 x → 림 x
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
            physicalEstimate: estimate,
            dynamicTargetAvailable: estimate != nil
        ))
    }
}
