import Vision
import CoreMedia
import CoreVideo
import CoreGraphics

final class LiveShotAnalyzer: @unchecked Sendable {
    var onRim: (@Sendable (RimCalibration) -> Void)?
    var onBall: (@Sendable ([NormalizedPoint]) -> Void)?
    var onShot: (@Sendable (ShotAnalysisReport) -> Void)?
    
    // ⭐ 추가: 방향 프로퍼티 (가로/세로 모드 대응)
    var orientation: CGImagePropertyOrientation = .up

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
    private var _calibration: CameraCalibration?

    private var frameCount = 0
    private var pending: Candidate?
    private var lastValidTime = 0.0
    private var lastShotTime = -10.0
    private var lastRatio: CGFloat = 16.0 / 9.0 // flush() 사용을 위한 마지막 프레임 비율 저장

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
            manualRim = false   // 자동 모드로 복귀
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

    private func updateRimIfNeeded(from pixelBuffer: CVPixelBuffer) {
        // 12프레임마다 검사
        guard let detector = rimDetector, frameCount % 12 == 1 else { return }

        lock.lock()
        let manual = manualRim
        let old = _rim
        lock.unlock()
        
        // ⭐ 수정: 오버로드된 detect(pixelBuffer:orientation:) 호출
        guard !manual, let found = detector.detect(in: pixelBuffer, orientation: orientation) else { return }

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

    // MARK: - 프레임 처리 (코어 로직 분리)
    
    /// 기존 실시간 카메라 큐 인터페이스 유지
    func process(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let ratio = CGFloat(CVPixelBufferGetHeight(pixelBuffer)) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        process(pixelBuffer: pixelBuffer, time: time, ratio: ratio)
    }

    /// ⭐ 추가: 녹화 영상에서도 재활용할 수 있도록 코어 로직 분리
    func process(pixelBuffer: CVPixelBuffer, time: Double, ratio: CGFloat) {
        frameCount += 1
        lastRatio = ratio
        updateRimIfNeeded(from: pixelBuffer)

        do {
            // ⭐ 수정: 프로퍼티로 들고 있는 orientation 적용
            try handler.perform([trajectoryRequest], on: pixelBuffer, orientation: orientation)
        } catch {
            return
        }
        let observations = trajectoryRequest.results ?? []

        if let visible = observations.max(by: {
            $0.confidence * Float($0.detectedPoints.count) < $1.confidence * Float($1.detectedPoints.count)
        }) {
            onBall?(visible.detectedPoints.map { NormalizedPoint($0.location) })
        } else {
            onBall?([])
        }

        guard let rim = currentRim else { return }

        let candidates = observations.compactMap { candidate(from: $0, rim: rim) }
        if let best = candidates.min(by: { $0.score < $1.score }),
           best.score < 0.8,
           time - lastShotTime > 1.5 {
            if pending == nil || best.score < pending!.score { pending = best }
            lastValidTime = time
        }

        if let pending, time - lastValidTime > 0.8 {
            finalize(pending, rim: rim, heightToWidthRatio: ratio)
            self.pending = nil
            lastShotTime = time
        }
    }
    
    // ⭐ 추가: 영상이 끝났을 때 분석 대기 중인 잔여 후보 슛을 확정
    func flush() {
        if let p = pending, let rim = currentRim {
            finalize(p, rim: rim, heightToWidthRatio: lastRatio)
            pending = nil
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

        guard a < -0.001 else { return nil }

        let xs = all.map(\.x)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        guard maxX - minX > 0.08 else { return nil }

        guard rimX > minX - 0.2, rimX < maxX + 0.2 else { return nil }

        let direction = last.x - first.x
        guard abs(direction) > 0.01 else { return nil }
        let apexX = -b / (2 * a)
        guard (rimX - apexX) * direction > 0 else { return nil }

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
