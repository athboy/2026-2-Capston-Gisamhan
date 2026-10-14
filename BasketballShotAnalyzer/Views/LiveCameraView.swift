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
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
        }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

// MARK: - 테크니컬 디자인 요소
struct TechBoundingBox: Shape {
    let cornerLength: CGFloat = 15
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
        
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
        
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
        
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
        
        return path
    }
}

// MARK: - 실시간 분석 화면
struct LiveCameraView: View {
    @StateObject private var vm = LiveShotViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var manualWidth: Double = 0.042

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            cameraArea
                .ignoresSafeArea() // ⭐ 노치 영역까지 화면 꽉 채우기
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            vm.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            vm.stop()
        }
    }

    private func filledRect(for size: CGSize) -> CGRect {
        let videoRatio: CGFloat = 16.0 / 9.0
        let viewRatio = size.width / size.height
        if viewRatio > videoRatio {
            let height = size.width / videoRatio
            return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        } else {
            let width = size.height * videoRatio
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }
    }
    
    private func convertToView(_ p: NormalizedPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * p.x, y: rect.minY + rect.height * (1 - p.y))
    }

    private var cameraArea: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let videoRect = filledRect(for: size)
            
            ZStack {
                CameraPreviewView(session: vm.camera.session)
                    .frame(width: size.width, height: size.height)

                if vm.showGuide { guideOverlay(size: size, rect: videoRect) }
                backboardOverlay(size: size, rect: videoRect)

                if let rim = vm.rim {
                    let boxWidth = videoRect.width * rim.widthFraction
                    let boxHeight = boxWidth * 0.7
                    
                    TechBoundingBox()
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: boxWidth, height: boxHeight)
                        .position(convertToView(rim.center, in: videoRect))
                        .shadow(color: .orange, radius: 5)
                }

                Path { path in
                    for (i, p) in vm.ballPoints.enumerated() {
                        let pt = convertToView(p, in: videoRect)
                        i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                    }
                }
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [8, 6]))
                .shadow(color: .cyan.opacity(0.8), radius: 5)

                if let shot = vm.lastShot {
                    Path { path in
                        for (i, p) in shot.path.points.enumerated() {
                            let pt = convertToView(p, in: videoRect)
                            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                        }
                    }
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .shadow(color: .orange.opacity(0.8), radius: 6)
                }
            }
            .clipped() // ⭐ 화면 바깥으로 나가는 UI를 깔끔하게 잘라내어 어지러움 해결
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                let nx = (location.x - videoRect.minX) / videoRect.width
                let ny = 1.0 - (location.y - videoRect.minY) / videoRect.height
                
                if nx >= 0 && nx <= 1 && ny >= 0 && ny <= 1 {
                    vm.handleTap(x: nx, y: ny, rimWidth: manualWidth)
                }
            }
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) {
                // ⭐ 스크롤 인디케이터 및 하단 패널 구성
                VStack(spacing: 8) {
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.compact.up")
                            .font(.headline)
                        Text("아래로 스크롤")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    
                    ScrollView(showsIndicators: true) {
                        bottomPanel
                    }
                }
                .frame(maxHeight: size.height * 0.6)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                )
            }
        }
        // ⭐ 불필요한 .aspectRatio 코드 삭제 완료 (화면 꽉 채우기 유지)
    }

    // MARK: - 기존 UI 컴포넌트 유지부

    private func guideOverlay(size: CGSize, rect: CGRect) -> some View {
        let center = ShootingGuide.targetCenter(rimOnRight: vm.rimOnRight)
        let boxWidth = rect.width * ShootingGuide.toleranceX * 2
        let boxHeight = rect.height * ShootingGuide.toleranceY * 2
        let pt = convertToView(center, in: rect)
        
        let color: Color = vm.isReady ? .green : .white
        let levelColor: Color = abs(vm.tiltRoll) <= ShootingGuide.maxRoll ? .green : .red

        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                .frame(width: boxWidth, height: boxHeight)
                .position(x: pt.x, y: pt.y)

            Text("림을 여기에")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .position(x: pt.x, y: pt.y - boxHeight / 2 - 10)

            Rectangle()
                .fill(levelColor)
                .frame(width: 90, height: 2)
                .rotationEffect(.degrees(-vm.tiltRoll))
                .position(x: size.width / 2, y: size.height / 2)
        }
        .allowsHitTesting(false)
    }

    private func backboardOverlay(size: CGSize, rect: CGRect) -> some View {
        ZStack {
            if let top = vm.backboardTop { backboardMarker(top, label: "위", rect: rect) }
            if let bottom = vm.backboardBottom { backboardMarker(bottom, label: "아래", rect: rect) }
            if let bb = vm.backboard {
                Path { path in
                    path.move(to: convertToView(bb.top, in: rect))
                    path.addLine(to: convertToView(bb.bottom, in: rect))
                }
                .stroke(.pink, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
            }
        }
        .allowsHitTesting(false)
    }

    private func backboardMarker(_ p: NormalizedPoint, label: String, rect: CGRect) -> some View {
        let pt = convertToView(p, in: rect)
        return Circle()
            .stroke(.pink, lineWidth: 2.5)
            .frame(width: 16, height: 16)
            .overlay(Text(label).font(.caption2.bold()).foregroundStyle(.pink).offset(x: 26))
            .position(x: pt.x, y: pt.y)
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").padding(10).background(.black.opacity(0.6), in: Circle())
            }
            Spacer()
            
            Text(rimStatus)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
            
            Spacer()
            
            if vm.calibrationStep == .off {
                HStack(spacing: 8) {
                    Button { vm.showGuide.toggle() } label: {
                        Image(systemName: vm.showGuide ? "viewfinder.circle.fill" : "viewfinder.circle")
                            .padding(10).background(.ultraThinMaterial, in: Circle())
                    }
                    Button { vm.startCalibration() } label: {
                        Image(systemName: vm.calibration != nil ? "checkmark.seal.fill" : "scope")
                            .padding(10).background(.ultraThinMaterial, in: Circle())
                    }
                    Button { vm.toggleManualRim() } label: {
                        Image(systemName: vm.isManualRim ? "hand.tap.fill" : "hand.tap")
                            .padding(10).background(.ultraThinMaterial, in: Circle())
                    }
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.white).padding(12)
    }
    
    private var rimStatus: String {
        if vm.calibration != nil { return "📐 보정 고정됨" }
        if vm.calibrationStep != .off { return "보정 중" }
        if vm.isManualRim { return "림 수동 지정" }
        if vm.rim != nil { return "림 자동 인식됨" }
        return vm.hasModel ? "림 탐색 중…" : "모델 없음 · 우측 버튼으로 수동 지정"
    }

    private var manualRimPanel: some View {
        VStack(spacing: 4) {
            Text("화면 탭으로 림 중심 지정").font(.caption2)
            Slider(value: $manualWidth, in: 0.02...0.20)
                .onChange(of: manualWidth) { _, new in
                    if let rim = vm.rim {
                        vm.setManualRim(x: rim.center.x, y: rim.center.y, width: new)
                    }
                }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(width: 200)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1))
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(vm.isReady ? "✅ 촬영 준비 완료" : "촬영 준비 체크").font(.subheadline.weight(.bold))
                Spacer()
                Button { vm.rimOnRight.toggle() } label: {
                    Label(vm.rimOnRight ? "림: 오른쪽" : "림: 왼쪽", systemImage: "arrow.left.arrow.right")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.2), in: Capsule())
                }
            }

            if !vm.isReady {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                    ForEach(vm.guideChecks) { check in
                        HStack(spacing: 6) {
                            Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(check.passed ? .green : .red)
                            Text(check.title).font(.caption)
                        }
                    }
                }
                if let hint = vm.firstHint {
                    Text("👉 \(hint)").font(.caption2).foregroundStyle(.yellow)
                }
                Text("폰은 가로로 삼각대에 고정 · 슈터 옆(측면)에서 · 가슴 높이(약 1.2~1.5m)")
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(14).frame(width: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1))
    }

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
        case .rim: return "가운데를 탭하고 슬라이더로 림 크기를 맞추세요."
        case .backboardTop: return "백보드 가장 높은 가장자리를 탭하세요."
        case .backboardBottom: return "백보드 가장 낮은 가장자리를 탭하세요."
        case .review: return "아래 5가지가 모두 ✅가 되면 누를 수 있어요."
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
                    .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                if let hint = vm.firstCalibrationHint {
                    Text("👉 \(hint)").font(.caption2).foregroundStyle(.yellow)
                }
            }

            HStack(spacing: 8) {
                switch vm.calibrationStep {
                case .rim:
                    pill("취소") { vm.cancelCalibration() }
                    pill("다음", prominent: true) { vm.goNext() }
                        .disabled(vm.rim == nil).opacity(vm.rim == nil ? 0.4 : 1)
                case .backboardTop, .backboardBottom:
                    pill("림 다시") { vm.redoRim() }
                    pill("취소") { vm.cancelCalibration() }
                case .review:
                    pill("림 다시") { vm.redoRim() }
                    pill("백보드 다시") { vm.redoBackboard() }
                    pill("보정 고정", prominent: true) { vm.goNext() }
                        .disabled(!vm.canLock).opacity(vm.canLock ? 1 : 0.4)
                case .off:
                    EmptyView()
                }
            }
        }
        .padding(12).frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1))
    }

    private func calibrationBadge(_ cal: CameraCalibration) -> some View {
        HStack {
            Text("📐 보정 적용 중 · 롤 \(cal.rollDegrees, specifier: "%.1f")°")
                .font(.caption.weight(.semibold))
            Spacer()
            Button("해제") { vm.resetCalibration() }.font(.caption.weight(.bold))
        }
        .padding(10).background(.green.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if vm.isManualRim, vm.calibration == nil, vm.calibrationStep == .off || vm.calibrationStep == .rim {
                manualRimPanel
            }

            if vm.calibrationStep != .off {
                calibrationCard
            } else {
                if let cal = vm.calibration { calibrationBadge(cal) }
                if vm.showGuide && !vm.isManualRim { guideCard }
            }

            if !vm.isManualRim && vm.calibrationStep == .off {
                if let shot = vm.lastShot {
                    VStack(spacing: 4) {
                        Text(shot.feedback.title).font(.title3.bold())
                        Text("입사각 \(shot.measuredEntryAngle, specifier: "%.1f")° · 목표 \(shot.targetEntryAngle, specifier: "%.1f")°")
                            .font(.subheadline.monospacedDigit())
                    }
                    .padding(14).frame(maxWidth: .infinity)
                    .background(bannerColor(shot).opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                HStack(alignment: .bottom, spacing: 14) {
                    stat("슛", "\(vm.shots.count)")
                    stat("평균 입사각", vm.averageAngle.map { String(format: "%.1f°", $0) } ?? "–")
                    stat("편차", vm.consistency.map { String(format: "±%.1f°", $0) } ?? "–")
                    Chart(Array(vm.shots.enumerated()), id: \.offset) { index, shot in
                        LineMark(x: .value("슛", index), y: .value("각도", shot.measuredEntryAngle)).foregroundStyle(.orange)
                        PointMark(x: .value("슛", index), y: .value("각도", shot.measuredEntryAngle)).foregroundStyle(.orange)
                    }
                    .chartYScale(domain: 25...70).chartXAxis(.hidden).frame(height: 50)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .onLongPressGesture { vm.resetStats() }
            }
        }
        .foregroundStyle(.white).padding(12)
        .animation(.easeOut(duration: 0.25), value: vm.isManualRim)
        .animation(.easeOut(duration: 0.25), value: vm.calibrationStep)
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
        case .perfect: return .green
        case .flat: return .orange
        case .steep: return .cyan
        }
    }
}
