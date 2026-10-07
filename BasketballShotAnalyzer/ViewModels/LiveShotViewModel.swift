import SwiftUI

@MainActor
final class LiveShotViewModel: ObservableObject {
    @Published private(set) var rim: RimCalibration?
    @Published private(set) var ballPoints: [NormalizedPoint] = []
    @Published private(set) var shots: [ShotAnalysisReport] = []
    @Published private(set) var lastShot: ShotAnalysisReport?
    @Published private(set) var errorMessage: String?
    @Published var isManualRim = false

    // 2단계: 가이드 관련 상태
    @Published private(set) var tiltPitch: Double = 0
    @Published private(set) var tiltRoll: Double = 0
    @Published var rimOnRight = true
    @Published var showGuide = true

    // ⭐ 추가 (3단계): 보정 관련 상태
    @Published private(set) var calibrationStep: CalibrationStep = .off
    @Published private(set) var backboardTop: NormalizedPoint?
    @Published private(set) var backboardBottom: NormalizedPoint?
    @Published private(set) var calibration: CameraCalibration?   // 고정된 보정 결과

    let camera = LiveCameraService()
    private let analyzer = LiveShotAnalyzer()
    private let motion = MotionService()

    var hasModel: Bool { analyzer.hasModel }

    // 2단계 검사 결과
    var guideChecks: [GuideCheck] {
        ShootingGuide.evaluate(rim: rim, pitch: tiltPitch, roll: tiltRoll, rimOnRight: rimOnRight)
    }
    var isReady: Bool { guideChecks.allSatisfy(\.passed) }
    var firstHint: String? { guideChecks.first { !$0.passed }?.hint }

    // ⭐ 추가: 백보드 (위/아래 순서를 탭 순서와 상관없이 자동 정리)
    var backboard: BackboardReference? {
        guard let t = backboardTop, let b = backboardBottom else { return nil }
        return t.y >= b.y
            ? BackboardReference(top: t, bottom: b)
            : BackboardReference(top: b, bottom: t)
    }

    // ⭐ 추가: 3단계 검사 결과
    var calibrationChecks: [GuideCheck] {
        CameraCalibration.evaluate(rim: rim, backboard: backboard, pitch: tiltPitch, roll: tiltRoll)
    }
    var canLock: Bool { calibrationChecks.allSatisfy(\.passed) }
    var firstCalibrationHint: String? { calibrationChecks.first { !$0.passed }?.hint }

    // 통계 패널용
    var averageAngle: Double? {
        guard !shots.isEmpty else { return nil }
        return shots.map(\.measuredEntryAngle).reduce(0, +) / Double(shots.count)
    }

    var consistency: Double? {
        guard shots.count >= 2, let mean = averageAngle else { return nil }
        let variance = shots.map { pow($0.measuredEntryAngle - mean, 2) }.reduce(0, +) / Double(shots.count)
        return sqrt(variance)
    }

    init() {
        camera.onFrame = { [analyzer] buffer in analyzer.process(buffer) }
        analyzer.onRim = { [weak self] rim in
            Task { @MainActor in self?.rim = rim }
        }
        analyzer.onBall = { [weak self] points in
            Task { @MainActor in self?.ballPoints = points }
        }
        analyzer.onShot = { [weak self] report in
            Task { @MainActor in self?.receive(report) }
        }
        motion.onUpdate = { [weak self] pitch, roll in
            Task { @MainActor in
                self?.tiltPitch = pitch
                self?.tiltRoll = roll
            }
        }
    }

    func start() {
        motion.start()
        Task {
            do { try await camera.start() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func stop() {
        camera.stop()
        motion.stop()
    }

    // MARK: - 림 수동 지정

    func toggleManualRim() {
        // ⭐ 수정: 보정 중이거나 보정이 고정된 상태에서는 림을 바꿀 수 없어요
        guard calibration == nil, calibrationStep == .off else { return }
        isManualRim.toggle()
        if !isManualRim { analyzer.setManualRim(nil) }
    }

    func setManualRim(x: CGFloat, y: CGFloat, width: CGFloat) {
        let rim = RimCalibration(center: .clamped(x: x, y: y), widthFraction: width)
        self.rim = rim
        analyzer.setManualRim(rim)
    }

    // ⭐ 추가: 화면 탭 처리 (지금 단계에 따라 하는 일이 달라요)
    func handleTap(x: CGFloat, y: CGFloat, rimWidth: CGFloat) {
        guard calibration == nil else { return }   // 보정이 고정되면 탭 무시
        let point = NormalizedPoint.clamped(x: x, y: y)
        switch calibrationStep {
        case .rim:
            setManualRim(x: x, y: y, width: rimWidth)
        case .backboardTop:
            backboardTop = point
            calibrationStep = .backboardBottom
        case .backboardBottom:
            backboardBottom = point
            calibrationStep = .review
        case .review:
            break
        case .off:
            if isManualRim { setManualRim(x: x, y: y, width: rimWidth) }
        }
    }

    // MARK: - ⭐ 추가: 보정 흐름

    /// 보정 시작
    func startCalibration() {
        calibration = nil
        analyzer.setCalibration(nil)
        backboardTop = nil
        backboardBottom = nil
        isManualRim = true
        if let rim { analyzer.setManualRim(rim) }   // 이미 있는 림은 움직이지 않게 고정
        calibrationStep = .rim
    }

    /// "다음" 버튼 (림 단계 → 백보드 단계, 확인 단계 → 고정)
    func goNext() {
        switch calibrationStep {
        case .rim:
            guard let rim else { return }
            analyzer.setManualRim(rim)
            calibrationStep = .backboardTop
        case .review:
            lockCalibration()
        default:
            break
        }
    }

    func redoRim() { calibrationStep = .rim }

    func redoBackboard() {
        backboardTop = nil
        backboardBottom = nil
        calibrationStep = .backboardTop
    }

    func cancelCalibration() {
        backboardTop = nil
        backboardBottom = nil
        calibrationStep = .off
    }

    /// 보정 해제 (고정된 눈금자를 지워요)
    func resetCalibration() {
        calibration = nil
        analyzer.setCalibration(nil)
        backboardTop = nil
        backboardBottom = nil
    }

    private func lockCalibration() {
        guard let rim, let backboard, canLock,
              let result = CameraCalibration.make(
                rim: rim, backboard: backboard, pitch: tiltPitch, roll: tiltRoll
              ) else { return }
        analyzer.setManualRim(rim)
        analyzer.setCalibration(result)
        calibration = result
        calibrationStep = .off
    }

    // MARK: - 통계

    func resetStats() {
        shots = []
        lastShot = nil
    }

    private func receive(_ report: ShotAnalysisReport) {
        shots.append(report)
        lastShot = report
        Task {
            try? await Task.sleep(for: .seconds(4))
            if lastShot == report { lastShot = nil }
        }
    }
}
