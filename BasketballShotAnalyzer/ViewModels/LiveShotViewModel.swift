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

    // 3단계: 보정 관련 상태
    @Published private(set) var calibrationStep: CalibrationStep = .off
    @Published private(set) var backboardTop: NormalizedPoint?
    @Published private(set) var backboardBottom: NormalizedPoint?
    @Published private(set) var calibration: CameraCalibration?

    // 가로 전용 화면 방향 + 안내 메시지
    @Published private(set) var orientation: ScreenOrientation = .landscapeRight
    @Published private(set) var notice: String?

    // 5단계: 저장용 기억 공간
    private var records: [ShotRecord] = []
    private var sessionID = UUID()
    private var sessionStart = Date()

    // 화면을 연 시각 (처음 몇 초 동안 방향이 자리 잡는 건 조용히 처리하려고요)
    private var startedAt = Date()

    let camera = LiveCameraService()
    private let analyzer = LiveShotAnalyzer()
    private let motion = MotionService()

    var hasModel: Bool { analyzer.hasModel }

    // 2단계 검사 결과
    var guideChecks: [GuideCheck] {
        ShootingGuide.evaluate(
            rim: rim, pitch: tiltPitch, roll: tiltRoll,
            rimOnRight: rimOnRight, orientation: orientation
        )
    }
    var isReady: Bool { guideChecks.allSatisfy(\.passed) }
    var firstHint: String? { guideChecks.first { !$0.passed }?.hint }

    var backboard: BackboardReference? {
        guard let t = backboardTop, let b = backboardBottom else { return nil }
        return t.y >= b.y
            ? BackboardReference(top: t, bottom: b)
            : BackboardReference(top: b, bottom: t)
    }

    // 3단계 검사 결과
    var calibrationChecks: [GuideCheck] {
        CameraCalibration.evaluate(
            rim: rim, backboard: backboard, pitch: tiltPitch, roll: tiltRoll,
            heightToWidthRatio: orientation.frameRatio
        )
    }
    var canLock: Bool { calibrationChecks.allSatisfy(\.passed) }
    var firstCalibrationHint: String? { calibrationChecks.first { !$0.passed }?.hint }

    var averageAngle: Double? {
        guard !shots.isEmpty else { return nil }
        return shots.map(\.measuredEntryAngle).reduce(0, +) / Double(shots.count)
    }

    var consistency: Double? {
        guard shots.count >= 2, let mean = averageAngle else { return nil }
        let variance = shots.map { pow($0.measuredEntryAngle - mean, 2) }.reduce(0, +) / Double(shots.count)
        return sqrt(variance)
    }

    /// ⭐ 추가: 골 개수
    var madeCount: Int { shots.filter { $0.made }.count }

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

    // MARK: - 시작 / 끝

    func start() {
        // 항상 가로로 시작
        OrientationController.request(landscape: true)
        let current = OrientationController.current()
        orientation = current.isLandscape ? current : .landscapeRight
        startedAt = Date()

        camera.setRotation(angle: orientation.captureAngle)
        motion.setOrientation(orientation)

        motion.start()
        Task {
            do { try await camera.start() }
            catch { errorMessage = error.localizedDescription }
        }

        // 화면이 다 돌아간 뒤 왼쪽 가로인지 오른쪽 가로인지 다시 확인
        settleOrientation()
    }

    func stop() {
        saveSession()   // 화면을 나갈 때 기록 저장
        camera.stop()
        motion.stop()
        // 첫 화면은 세로용이라서 나갈 때 세로로 되돌려요
        OrientationController.request(landscape: true)
    }

    // MARK: - 화면 방향 (가로 전용)

    private func settleOrientation() {
        Task {
            for delay in [0.3, 0.5, 0.7, 1.0] {
                try? await Task.sleep(for: .seconds(delay))
                applyOrientation(OrientationController.current())
            }
        }
    }

    /// 폰을 돌렸을 때 호출돼요
    func refreshOrientation() {
        applyOrientation(OrientationController.current())
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            applyOrientation(OrientationController.current())
        }
    }

    private func applyOrientation(_ new: ScreenOrientation) {
        // 세로는 무시하고, 가로(왼쪽↔오른쪽)가 바뀔 때만 처리해요
        guard new.isLandscape, new != orientation else { return }
        let justStarted = Date().timeIntervalSince(startedAt) < 2.5
        orientation = new

        // 카메라, 센서, 계산식을 새 방향에 맞추기
        camera.setRotation(angle: new.captureAngle)
        motion.setOrientation(new)

        // 방향이 바뀌면 림/백보드 좌표(화면 위치)가 맞지 않게 되니 지우기
        rim = nil
        isManualRim = false
        backboardTop = nil
        backboardBottom = nil
        calibration = nil
        calibrationStep = .off
        ballPoints = []
        lastShot = nil
        analyzer.resetForNewOrientation()

        // 처음 몇 초 안에 자리 잡는 건 안내를 띄우지 않아요
        if !justStarted {
            showNotice("폰 방향이 바뀌었어요. 림과 보정을 다시 지정해 주세요.")
        }
    }

    private func showNotice(_ message: String) {
        notice = message
        Task {
            try? await Task.sleep(for: .seconds(5))
            if notice == message { notice = nil }
        }
    }

    // MARK: - 림 수동 지정

    func toggleManualRim() {
        guard calibration == nil, calibrationStep == .off else { return }
        isManualRim.toggle()
        if !isManualRim { analyzer.setManualRim(nil) }
    }

    func setManualRim(x: CGFloat, y: CGFloat, width: CGFloat) {
        let rim = RimCalibration(center: .clamped(x: x, y: y), widthFraction: width)
        self.rim = rim
        analyzer.setManualRim(rim)
    }

    func handleTap(x: CGFloat, y: CGFloat, rimWidth: CGFloat) {
        guard calibration == nil else { return }
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

    // MARK: - 보정 흐름

    func startCalibration() {
        calibration = nil
        analyzer.setCalibration(nil)
        backboardTop = nil
        backboardBottom = nil
        isManualRim = true
        if let rim { analyzer.setManualRim(rim) }
        calibrationStep = .rim
    }

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

    func resetCalibration() {
        calibration = nil
        analyzer.setCalibration(nil)
        backboardTop = nil
        backboardBottom = nil
    }

    private func lockCalibration() {
        guard let rim, let backboard, canLock,
              let result = CameraCalibration.make(
                rim: rim, backboard: backboard, pitch: tiltPitch, roll: tiltRoll,
                heightToWidthRatio: orientation.frameRatio
              ) else { return }
        analyzer.setManualRim(rim)
        analyzer.setCalibration(result)
        calibration = result
        calibrationStep = .off
    }

    // MARK: - 통계 + 저장

    func resetStats() {
        saveSession()   // 지우기 전에 저장
        showNotice("기록을 저장하고 새로 시작했어요.")
        shots = []
        records = []
        lastShot = nil
        sessionID = UUID()      // 새 세션으로 시작
        sessionStart = Date()
    }

    /// 지금까지의 슛을 파일로 저장 (슛이 없으면 저장 안 함)
    func saveSession() {
        guard !records.isEmpty else { return }
        SessionStore.save(
            ShotSession(
                id: sessionID,
                startedAt: sessionStart,
                endedAt: Date(),
                calibrated: calibration != nil,
                landscape: true,
                shots: records
            )
        )
    }

    private func receive(_ report: ShotAnalysisReport) {
        shots.append(report)
        // 슛 1개 기록하고 바로 저장 (앱이 꺼져도 기록이 남아요)
        records.append(
            ShotRecord(
                id: UUID(),
                time: Date(),
                measuredAngle: report.measuredEntryAngle,
                targetAngle: report.targetEntryAngle,
                difference: report.difference,
                feedback: report.feedback.rawValue,
                confidence: report.confidence,
                made: report.made   // ⭐ 골 여부 저장
            )
        )
        saveSession()
        lastShot = report
        Task {
            try? await Task.sleep(for: .seconds(4))
            if lastShot == report { lastShot = nil }
        }
    }
}
