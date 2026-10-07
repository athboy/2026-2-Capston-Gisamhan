import SwiftUI
import AVFoundation
import Charts

// MARK: - 카메라 미리보기 (UIKit 브리지)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

// MARK: - 실시간 분석 화면

struct LiveCameraView: View {
    @StateObject private var vm = LiveShotViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var manualWidth: Double = 0.075

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraArea
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            vm.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            vm.stop()
        }
    }

    private var cameraArea: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                CameraPreviewView(session: vm.camera.session)

                if vm.showGuide {
                    guideOverlay(size: size)
                }

                // ⭐ 추가: 백보드 기준점 (탭한 점이 있을 때만 그려져요)
                backboardOverlay(size: size)

                if let rim = vm.rim {
                    Capsule()
                        .stroke(.cyan, style: StrokeStyle(lineWidth: 3, dash: [7, 4]))
                        .frame(width: size.width * rim.widthFraction, height: 13)
                        .position(x: size.width * rim.center.x, y: size.height * (1 - rim.center.y))
                        .shadow(color: .cyan.opacity(0.8), radius: 5)
                }

                // 실시간 공 궤적
                Path { path in
                    for (i, p) in vm.ballPoints.enumerated() {
                        let pt = CGPoint(x: size.width * p.x, y: size.height * (1 - p.y))
                        i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                    }
                }
                .stroke(.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                // 확정된 슛의 포물선
                if let shot = vm.lastShot {
                    Path { path in
                        for (i, p) in shot.path.points.enumerated() {
                            let pt = CGPoint(x: size.width * p.x, y: size.height * (1 - p.y))
                            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                        }
                    }
                    .stroke(.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .shadow(color: .orange.opacity(0.8), radius: 4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                // ⭐ 수정: 탭 처리를 ViewModel이 단계에 맞게 알아서 해요
                vm.handleTap(
                    x: location.x / size.width,
                    y: 1 - location.y / size.height,
                    rimWidth: manualWidth
                )
            }
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) { bottomPanel }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
    }

    // MARK: 가이드 (점선 박스 + 수평선)

    private func guideOverlay(size: CGSize) -> some View {
        let center = ShootingGuide.targetCenter(rimOnRight: vm.rimOnRight)
        let boxWidth = size.width * ShootingGuide.toleranceX * 2
        let boxHeight = size.height * ShootingGuide.toleranceY * 2
        let boxX = size.width * center.x
        let boxY = size.height * (1 - center.y)
        let color: Color = vm.isReady ? .green : .white
        let levelColor: Color = abs(vm.tiltRoll) <= ShootingGuide.maxRoll ? .green : .red

        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                .frame(width: boxWidth, height: boxHeight)
                .position(x: boxX, y: boxY)

            Text("림을 여기에")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .position(x: boxX, y: boxY - boxHeight / 2 - 10)

            Rectangle()
                .fill(levelColor)
                .frame(width: 90, height: 2)
                .rotationEffect(.degrees(-vm.tiltRoll))
                .position(x: size.width / 2, y: size.height / 2)
        }
        .allowsHitTesting(false)
    }

    // MARK: ⭐ 추가: 백보드 표시 (분홍색 점 2개 + 선)

    private func backboardOverlay(size: CGSize) -> some View {
        ZStack {
            if let top = vm.backboardTop {
                backboardMarker(top, label: "위", size: size)
            }
            if let bottom = vm.backboardBottom {
                backboardMarker(bottom, label: "아래", size: size)
            }
            if let bb = vm.backboard {
                Path { path in
                    path.move(to: CGPoint(x: size.width * bb.top.x, y: size.height * (1 - bb.top.y)))
                    path.addLine(to: CGPoint(x: size.width * bb.bottom.x, y: size.height * (1 - bb.bottom.y)))
                }
                .stroke(.pink, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
            }
        }
        .allowsHitTesting(false)
    }

    private func backboardMarker(_ p: NormalizedPoint, label: String, size: CGSize) -> some View {
        Circle()
            .stroke(.pink, lineWidth: 2.5)
            .frame(width: 16, height: 16)
            .overlay(
                Text(label)
                    .font(.caption2.bold())
                    .foregroundStyle(.pink)
                    .offset(x: 26)
            )
            .position(x: size.width * p.x, y: size.height * (1 - p.y))
    }

    // MARK: 상단 바

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .padding(10)
                        .background(.black.opacity(0.6), in: Circle())
                }
                Spacer()
                Text(rimStatus)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
                Spacer()
                Button { vm.showGuide.toggle() } label: {
                    Image(systemName: vm.showGuide ? "viewfinder.circle.fill" : "viewfinder.circle")
                        .padding(10)
                        .background(.black.opacity(vm.showGuide ? 0.9 : 0.6), in: Circle())
                }
                // ⭐ 추가: 보정 시작 버튼
                Button { vm.startCalibration() } label: {
                    Image(systemName: vm.calibration != nil ? "checkmark.seal.fill" : "scope")
                        .padding(10)
                        .background(.black.opacity(vm.calibrationStep != .off ? 0.9 : 0.6), in: Circle())
                }
                Button { vm.toggleManualRim() } label: {
                    Image(systemName: vm.isManualRim ? "hand.tap.fill" : "hand.tap")
                        .padding(10)
                        .background(.black.opacity(vm.isManualRim ? 0.9 : 0.6), in: Circle())
                }
                .disabled(vm.calibration != nil || vm.calibrationStep != .off)
            }

            // 림 폭 슬라이더: 보정이 고정되지 않았고, 림 지정 중일 때만
            if vm.isManualRim, vm.calibration == nil,
               vm.calibrationStep == .off || vm.calibrationStep == .rim {
                VStack(spacing: 4) {
                    Text("화면을 탭해 림 중심을 지정하세요")
                        .font(.caption)
                    Slider(value: $manualWidth, in: 0.02...0.20)
                        .onChange(of: manualWidth) { _, new in
                            if let rim = vm.rim {
                                vm.setManualRim(x: rim.center.x, y: rim.center.y, width: new)
                            }
                        }
                }
                .padding(10)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = vm.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
    }

    private var rimStatus: String {
        if vm.calibration != nil { return "📐 보정 고정됨" }
        if vm.calibrationStep != .off { return "보정 중" }
        if vm.isManualRim { return "림 수동 지정" }
        if vm.rim != nil { return "림 자동 인식됨" }
        return vm.hasModel ? "림 탐색 중…" : "모델 없음 · 우측 버튼으로 수동 지정"
    }

    // MARK: 2단계 체크리스트 카드

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(vm.isReady ? "✅ 촬영 준비 완료" : "촬영 준비 체크")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button { vm.rimOnRight.toggle() } label: {
                    Label(vm.rimOnRight ? "림: 오른쪽" : "림: 왼쪽", systemImage: "arrow.left.arrow.right")
                        .font(.caption2.weight(.semibold))
                }
            }

            if !vm.isReady {
                ForEach(vm.guideChecks) { check in
                    HStack(spacing: 6) {
                        Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(check.passed ? .green : .red)
                        Text(check.title).font(.caption)
                    }
                }
                if let hint = vm.firstHint {
                    Text("👉 \(hint)")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text("폰은 세로로 삼각대에 고정 · 슈터 옆(측면)에서 · 가슴 높이(약 1.2~1.5m)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: ⭐ 추가: 3단계 보정 카드

    private var stepTitle: String {
        switch vm.calibrationStep {
        case .rim: return "① 림 지정"
        case .backboardTop: return "② 백보드 위쪽 끝"
        case .backboardBottom: return "③ 백보드 아래쪽 끝"
        case .review: return "④ 확인하고 고정"
        case .off: return ""
        }
    }

    private var stepDescription: String {
        switch vm.calibrationStep {
        case .rim: return "림의 가운데를 탭하고, 위 슬라이더로 하늘색 점선 길이를 림 크기에 맞춰 주세요."
        case .backboardTop: return "백보드에서 가장 높은 가장자리를 탭해 주세요."
        case .backboardBottom: return "백보드에서 가장 낮은 가장자리를 탭해 주세요."
        case .review: return "아래 5가지가 모두 ✅가 되면 '보정 고정'을 누를 수 있어요."
        case .off: return ""
        }
    }

    private func pill(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(prominent ? Color.orange : Color.white.opacity(0.2), in: Capsule())
        }
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stepTitle).font(.subheadline.weight(.bold))
            Text(stepDescription).font(.caption)

            if vm.calibrationStep == .review {
                ForEach(vm.calibrationChecks) { check in
                    HStack(spacing: 6) {
                        Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(check.passed ? .green : .red)
                        Text(check.title).font(.caption)
                    }
                }
                Text("현재 기울기: 롤 \(vm.tiltRoll, specifier: "%.1f")° · 피치 \(vm.tiltPitch, specifier: "%.1f")°")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                if let hint = vm.firstCalibrationHint {
                    Text("👉 \(hint)")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }

            HStack(spacing: 8) {
                switch vm.calibrationStep {
                case .rim:
                    pill("취소") { vm.cancelCalibration() }
                    pill("다음", prominent: true) { vm.goNext() }
                        .disabled(vm.rim == nil)
                        .opacity(vm.rim == nil ? 0.4 : 1)
                case .backboardTop, .backboardBottom:
                    pill("림 다시") { vm.redoRim() }
                    pill("취소") { vm.cancelCalibration() }
                case .review:
                    pill("림 다시") { vm.redoRim() }
                    pill("백보드 다시") { vm.redoBackboard() }
                    pill("보정 고정", prominent: true) { vm.goNext() }
                        .disabled(!vm.canLock)
                        .opacity(vm.canLock ? 1 : 0.4)
                case .off:
                    EmptyView()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
    }

    private func calibrationBadge(_ cal: CameraCalibration) -> some View {
        HStack {
            Text("📐 보정 적용 중 · 롤 \(cal.rollDegrees, specifier: "%.1f")°")
                .font(.caption.weight(.semibold))
            Spacer()
            Button("해제") { vm.resetCalibration() }
                .font(.caption.weight(.bold))
        }
        .padding(10)
        .background(.green.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 하단 (보정/가이드 + 피드백 + 통계)

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if vm.calibrationStep != .off {
                calibrationCard
            } else {
                if let cal = vm.calibration {
                    calibrationBadge(cal)
                }
                if vm.showGuide {
                    guideCard
                }
            }

            if let shot = vm.lastShot {
                VStack(spacing: 4) {
                    Text(shot.feedback.title).font(.title3.bold())
                    Text("입사각 \(shot.measuredEntryAngle, specifier: "%.1f")° · 목표 \(shot.targetEntryAngle, specifier: "%.1f")°")
                        .font(.subheadline.monospacedDigit())
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(bannerColor(shot).opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 14) {
                stat("슛", "\(vm.shots.count)")
                stat("평균 입사각", vm.averageAngle.map { String(format: "%.1f°", $0) } ?? "–")
                stat("편차", vm.consistency.map { String(format: "±%.1f°", $0) } ?? "–")
                Chart(Array(vm.shots.enumerated()), id: \.offset) { index, shot in
                    LineMark(x: .value("슛", index), y: .value("각도", shot.measuredEntryAngle))
                        .foregroundStyle(.orange)
                    PointMark(x: .value("슛", index), y: .value("각도", shot.measuredEntryAngle))
                        .foregroundStyle(.orange)
                }
                .chartYScale(domain: 25...70)
                .chartXAxis(.hidden)
                .frame(height: 50)
            }
            .padding(12)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
            .onLongPressGesture { vm.resetStats() }
        }
        .foregroundStyle(.white)
        .padding(12)
        .animation(.easeOut(duration: 0.25), value: vm.lastShot)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.headline.monospacedDigit())
        }
    }

    private func bannerColor(_ shot: ShotAnalysisReport) -> Color {
        switch shot.feedback {
        case .perfect: .green
        case .flat: .orange
        case .steep: .purple
        }
    }
}
