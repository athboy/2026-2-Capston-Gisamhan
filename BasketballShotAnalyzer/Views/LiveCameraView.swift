import SwiftUI
import AVFoundation
import Charts

// MARK: - 카메라 미리보기 (UIKit 브리지)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let angle: CGFloat

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        var angle: CGFloat = 0 {
            didSet { applyAngle() }
        }

        func applyAngle() {
            if let connection = previewLayer.connection,
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyAngle()
        }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.angle = angle
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.angle = angle
    }
}

// MARK: - 실시간 분석 화면

struct LiveCameraView: View {
    @StateObject private var vm = LiveShotViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var manualWidth: Double = 0.075 * 1080.0 / 1920.0
    @State private var menuOpen = false
    @State private var panelExpanded = true

    var body: some View {
        ZStack {
            // 1. 카메라 영상 레이어 (전체화면 100% 채움)
            GeometryReader { fullScreen in
                let videoSize = filledVideoSize(in: fullScreen.size)

                ZStack {
                    Color.black

                    videoLayer(size: videoSize, screenSize: fullScreen.size)
                        .frame(width: videoSize.width, height: videoSize.height)
                        .position(x: fullScreen.size.width / 2, y: fullScreen.size.height / 2)
                }
                .frame(width: fullScreen.size.width, height: fullScreen.size.height)
                .clipped()
                .onChange(of: fullScreen.size) { _, _ in
                    vm.refreshOrientation()
                }
            }
            .ignoresSafeArea()

            // 2. UI 컨트롤 레이어 (다이나믹 아일랜드 안전 영역 내부 배치)
            GeometryReader { safeScreen in
                uiLayer(screen: safeScreen.size)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            UIApplication.shared.isIdleTimerDisabled = true
            vm.start()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            UIApplication.shared.isIdleTimerDisabled = false
            vm.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            vm.refreshOrientation()
        }
        .onChange(of: vm.orientation) { _, new in
            manualWidth = 0.075 * Double(new.widthScale)
            panelExpanded = true
        }
        .onChange(of: vm.isReady) { _, ready in
            if ready {
                withAnimation(.easeOut(duration: 0.2)) { panelExpanded = false }
            }
        }
    }

    private func clamped(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), min(max(low, high), high))
    }

    private func filledVideoSize(in screen: CGSize) -> CGSize {
        let aspect: CGFloat = 16.0 / 9.0
        let width = max(screen.width, screen.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    // MARK: - 영상 레이어 (카메라 + 림 + 궤적 + 가이드 + 팝업 태그)

    private func videoLayer(size: CGSize, screenSize: CGSize) -> some View {
        ZStack {
            CameraPreviewView(session: vm.camera.session, angle: vm.orientation.captureAngle)

            if vm.showGuide {
                guideOverlay(size: size)
            }

            backboardOverlay(size: size)

            if let rim = vm.rim {
                Capsule()
                    .stroke(HUD.cyan, style: StrokeStyle(lineWidth: 3, dash: [7, 4]))
                    .frame(width: size.width * rim.widthFraction, height: 14)
                    .position(x: size.width * rim.center.x, y: size.height * (1 - rim.center.y))
                    .shadow(color: HUD.cyan.opacity(0.8), radius: 6)
            }

            Path { path in
                for (i, p) in vm.ballPoints.enumerated() {
                    let pt = CGPoint(x: size.width * p.x, y: size.height * (1 - p.y))
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
            }
            .stroke(HUD.orange, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            .shadow(color: HUD.orange.opacity(0.8), radius: 4)

            if let shot = vm.lastShot {
                Path { path in
                    for (i, p) in shot.path.points.enumerated() {
                        let pt = CGPoint(x: size.width * p.x, y: size.height * (1 - p.y))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                .stroke(HUD.gold, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .shadow(color: HUD.gold.opacity(0.6), radius: 6)
            }

            shotTags(size: size, screenSize: screenSize)
        }
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            if menuOpen {
                withAnimation(.easeOut(duration: 0.2)) { menuOpen = false }
            }
            vm.handleTap(
                x: location.x / size.width,
                y: 1 - location.y / size.height,
                rimWidth: manualWidth
            )
        }
    }

    // MARK: - HUD 컨트롤 레이어

    private var showRimSlider: Bool {
        vm.isManualRim && vm.calibration == nil
            && (vm.calibrationStep == .off || vm.calibrationStep == .rim)
    }

    private func uiLayer(screen: CGSize) -> some View {
        ZStack {
            GridOverlay()
        }
        .frame(width: screen.width, height: screen.height)
        .allowsHitTesting(false)
        // 1. 골대 반대편: 사이드 대시보드 패널
        .overlay(alignment: vm.rimOnRight ? .topLeading : .topTrailing) {
            sidePanel(screen: screen)
        }
        // 2. 골대 쪽 아래 구석: 상태 알림('SCANNING · 림 탐색 중...') 및 수동 림 크기 슬라이더
        .overlay(alignment: vm.rimOnRight ? .bottomTrailing : .bottomLeading) {
            bottomRimOverlay
                .padding(vm.rimOnRight ? .trailing : .leading, 12)
                .padding(.bottom, 10)
        }
        // 3. 상단 바 및 형광 노랑 알림 배너 (최상단 레이어)
        .overlay(alignment: .top) {
            topBar
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .zIndex(10)
        }
    }

    private var bottomRimOverlay: some View {
        VStack(alignment: vm.rimOnRight ? .trailing : .leading, spacing: 8) {
            if showRimSlider {
                rimSizePanel
            }
            statusTag
        }
    }

    // MARK: - 사이드 대시보드 패널 (스크롤 상·하단 그라데이션 페이드 적용)

    @ViewBuilder
    private func sidePanel(screen: CGSize) -> some View {
        let calibrating = vm.calibrationStep != .off
        let panelWidth = min(245, screen.width * 0.34)

        if panelExpanded || calibrating {
            VStack(spacing: 6) {
                if !calibrating { collapseButton }

                ScrollView(.vertical, showsIndicators: false) {
                    panelContent
                        .padding(.top, 6)
                        .padding(.bottom, 26)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.04),
                            .init(color: .black, location: 0.85),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .frame(width: panelWidth)
            .frame(maxHeight: screen.height - 60)
            .padding(.top, 54)
            .padding(vm.rimOnRight ? .leading : .trailing, 12)
        } else {
            summaryBox
                .frame(width: 210)
                .padding(.top, 54)
                .padding(vm.rimOnRight ? .leading : .trailing, 12)
        }
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { panelExpanded = false }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                Text("패널 접기")
            }
            .font(HUD.font(12, .bold))
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
    }

    private func miniStat(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(HUD.font(10, .bold))
                .foregroundStyle(HUD.dim)
            Text(value)
                .font(HUD.font(20, .heavy).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private var summaryBox: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { panelExpanded = true }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.isReady ? HUD.gold : HUD.orange)
                        .frame(width: 8, height: 8)
                    Text(vm.isReady ? "READY" : "CHECK")
                        .font(HUD.font(13, .heavy))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HUD.dim)
                }

                HStack(spacing: 14) {
                    miniStat("SHOTS", "\(vm.shots.count)", color: .white)
                    miniStat("GOAL", "\(vm.madeCount)", color: ShotColor.made)
                    miniStat("AVG", vm.averageAngle.map { String(format: "%.1f°", $0) } ?? "–", color: HUD.gold)
                }

                if let shot = vm.lastShot {
                    DottedLine()
                    HStack(spacing: 8) {
                        Text(String(format: "%.1f°", shot.measuredEntryAngle))
                            .font(HUD.font(22, .black).monospacedDigit())
                            .foregroundStyle(HUD.orange)
                        goalTag(shot)
                        Spacer()
                        Text(shot.feedback.title)
                            .font(HUD.font(12, .bold))
                            .foregroundStyle(.white)
                    }
                } else if !vm.isReady, let hint = vm.firstHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(HUD.gold)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Color.white)
            .hudPanel(tint: vm.isReady ? HUD.gold : HUD.orange)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 슛 궤적 라벨 (다이나믹 아일랜드 침범 방지 안전 범위 적용)

    private func shotTags(size: CGSize, screenSize: CGSize) -> some View {
        let xCrop = max(0, (size.width - screenSize.width) / 2)
        let yCrop = max(0, (size.height - screenSize.height) / 2)
        let safeMinX = xCrop + 115
        let safeMaxX = size.width - xCrop - 115
        let safeMinY = yCrop + 75
        let safeMaxY = size.height - yCrop - 75

        return ZStack {
            if let shot = vm.lastShot {
                if let peak = shot.path.points.max(by: { $0.y < $1.y }) {
                    HUDTag(text: "SHOT ARC")
                        .position(
                            x: clamped(size.width * peak.x, safeMinX, safeMaxX),
                            y: clamped(size.height * (1 - peak.y) - 24, safeMinY, safeMaxY)
                        )
                }
                if let rim = vm.rim {
                    HUDTag(text: "SHOT ANGLE \(String(format: "%.1f", shot.measuredEntryAngle))°")
                        .position(
                            x: clamped(size.width * rim.center.x, safeMinX, safeMaxX),
                            y: clamped(size.height * (1 - rim.center.y) + 30, safeMinY, safeMaxY)
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 촬영 가이드 오버레이

    private func guideOverlay(size: CGSize) -> some View {
        let center = ShootingGuide.targetCenter(rimOnRight: vm.rimOnRight)
        let boxWidth = size.width * ShootingGuide.boxHalfWidth(vm.orientation) * 2
        let boxHeight = size.height * ShootingGuide.boxHalfHeight(vm.orientation) * 2
        let boxX = size.width * center.x
        let boxY = size.height * (1 - center.y)
        let color: Color = vm.isReady ? HUD.gold : Color.white.opacity(0.85)
        let levelColor: Color = abs(vm.tiltRoll) <= ShootingGuide.maxRoll ? HUD.gold : HUD.orange

        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .frame(width: boxWidth, height: boxHeight)
                .position(x: boxX, y: boxY)

            Text("림을 여기에 맞추세요")
                .font(HUD.font(12, .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                .position(x: boxX, y: boxY - boxHeight / 2 - 16)

            Capsule()
                .fill(levelColor)
                .frame(width: 80, height: 3)
                .rotationEffect(.degrees(-vm.tiltRoll))
                .position(x: size.width / 2, y: size.height / 2)
        }
        .allowsHitTesting(false)
    }

    // MARK: - 백보드 보정 마커

    private func backboardOverlay(size: CGSize) -> some View {
        ZStack {
            if let top = vm.backboardTop {
                backboardMarker(top, label: "TOP", size: size)
            }
            if let bottom = vm.backboardBottom {
                backboardMarker(bottom, label: "BOT", size: size)
            }
            if let bb = vm.backboard {
                Path { path in
                    path.move(to: CGPoint(x: size.width * bb.top.x, y: size.height * (1 - bb.top.y)))
                    path.addLine(to: CGPoint(x: size.width * bb.bottom.x, y: size.height * (1 - bb.bottom.y)))
                }
                .stroke(HUD.gold, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
            }
        }
        .allowsHitTesting(false)
    }

    private func backboardMarker(_ p: NormalizedPoint, label: String, size: CGSize) -> some View {
        Circle()
            .stroke(HUD.gold, lineWidth: 2.5)
            .frame(width: 16, height: 16)
            .overlay(
                Text(label)
                    .font(HUD.font(11, .bold))
                    .foregroundStyle(HUD.gold)
                    .offset(x: vm.rimOnRight ? -26 : 26)
            )
            .position(x: size.width * p.x, y: size.height * (1 - p.y))
    }

    // MARK: - 상단 컨트롤 아이콘 (뒤로가기 버튼 상시 노출 + 메뉴 버튼 우측 배치)

    private func hudIcon(_ name: String, active: Bool, size: CGFloat = 38) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .bold))
            .frame(width: size, height: size)
            .background(.ultraThinMaterial)
            .background(active ? HUD.orange : Color.black.opacity(0.55))
            .clipShape(Circle())
            .overlay(Circle().stroke(active ? HUD.orange : Color.white.opacity(0.25), lineWidth: 1))
            .foregroundStyle(Color.white)
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.2)) { menuOpen = false }
    }

    /// 메인 화면으로 나가는 되돌리기 버튼 (항상 표시)
    private func backButton(size: CGFloat = 38) -> some View {
        Button { dismiss() } label: {
            hudIcon("arrow.uturn.backward", active: false, size: size)
        }
    }

    private func guideButton(size: CGFloat) -> some View {
        Button {
            vm.showGuide.toggle()
            closeMenu()
        } label: {
            hudIcon(vm.showGuide ? "viewfinder.circle.fill" : "viewfinder.circle",
                    active: vm.showGuide, size: size)
        }
    }

    private func calibrateButton(size: CGFloat) -> some View {
        Button {
            vm.startCalibration()
            closeMenu()
        } label: {
            hudIcon(vm.calibration != nil ? "checkmark.seal.fill" : "scope",
                    active: vm.calibrationStep != .off || vm.calibration != nil, size: size)
        }
    }

    private func manualButton(size: CGFloat) -> some View {
        Button {
            vm.toggleManualRim()
            closeMenu()
        } label: {
            hudIcon(vm.isManualRim ? "hand.tap.fill" : "hand.tap",
                    active: vm.isManualRim, size: size)
        }
        .disabled(vm.calibration != nil || vm.calibrationStep != .off)
    }

    private var menuToggleButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { menuOpen.toggle() }
        } label: {
            hudIcon(
                menuOpen ? (vm.rimOnRight ? "chevron.left" : "chevron.right") : "square.grid.2x2",
                active: menuOpen
            )
        }
    }

    private var menuItems: some View {
        HStack(spacing: 8) {
            guideButton(size: 38)
            calibrateButton(size: 38)
            manualButton(size: 38)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    /// 왼쪽에 뒤로가기 버튼, 그 오른쪽에 메뉴 박스 버튼 배치
    private func menuGroup(leading: Bool) -> some View {
        HStack(spacing: 8) {
            if leading {
                backButton(size: 38)
                menuToggleButton
                if menuOpen { menuItems }
            } else {
                if menuOpen { menuItems }
                backButton(size: 38)
                menuToggleButton
            }
        }
    }

    // MARK: - 림 크기 조절 슬라이더

    private var rimSizePanel: some View {
        HStack(spacing: 10) {
            Text("림 크기")
                .font(HUD.font(12, .bold))
            Slider(value: $manualWidth, in: 0.02...max(0.05, 0.20 * Double(vm.orientation.widthScale)))
                .tint(HUD.gold)
                .onChange(of: manualWidth) { _, new in
                    if let rim = vm.rim {
                        vm.setManualRim(x: rim.center.x, y: rim.center.y, width: new)
                    }
                }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: 230)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }

    // MARK: - 상단 바 (메뉴 버튼 및 최상단 알림 배너)

    private var topBar: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .center, spacing: 8) {
                if vm.rimOnRight {
                    menuGroup(leading: true)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    menuGroup(leading: false)
                }
            }

            VStack(spacing: 6) {
                if let notice = vm.notice {
                    Text(notice)
                        .font(HUD.font(13, .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(HUD.gold)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.45), radius: 8, y: 4)
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(HUD.orange)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.45), radius: 8, y: 4)
                }
            }
            .padding(.top, 4)
            .allowsHitTesting(false)
        }
    }

    private var statusTag: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(vm.rim != nil ? HUD.gold : HUD.orange)
                .frame(width: 7, height: 7)
            Text(rimStatus)
                .font(HUD.font(12, .bold))
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.65))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }

    private var rimStatus: String {
        if vm.calibration != nil { return "CALIBRATED · 보정 완료" }
        if vm.calibrationStep == .rim || (vm.isManualRim && vm.rim == nil) {
            return "TAP · 화면을 탭해 림 지정"
        }
        if vm.calibrationStep != .off { return "CALIBRATING · 보정 중" }
        if vm.isManualRim { return "MANUAL · 림 수동 지정" }
        if vm.rim != nil { return "RIM LOCKED · 림 인식됨" }
        return vm.hasModel ? "SCANNING · 림 탐색 중…" : "모델 없음 · 수동 지정 필요"
    }

    // MARK: - 사이드 패널 내부 컨텐츠

    private var panelContent: some View {
        VStack(spacing: 8) {
            actionBar

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
                feedbackBanner(shot)
            }

            statsPanel
        }
        .foregroundStyle(Color.white)
        .animation(.easeOut(duration: 0.25), value: vm.lastShot)
    }

    // MARK: - 액션 버튼 바

    private func actionButton(
        _ title: String,
        icon: String? = nil,
        prominent: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(HUD.font(13, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(prominent ? Color.white : Color.white.opacity(0.95))
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(prominent ? HUD.orange : Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(prominent ? HUD.orange : Color.white.opacity(0.22), lineWidth: 1)
            )
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            switch vm.calibrationStep {
            case .rim:
                actionButton("취소") { vm.cancelCalibration() }
                actionButton("다음", prominent: true, enabled: vm.rim != nil) { vm.goNext() }
            case .backboardTop, .backboardBottom:
                actionButton("림 다시") { vm.redoRim() }
                actionButton("취소") { vm.cancelCalibration() }
            case .review:
                actionButton("림 다시") { vm.redoRim() }
                actionButton("백보드") { vm.redoBackboard() }
                actionButton("고정", prominent: true, enabled: vm.canLock) { vm.goNext() }
            case .off:
                actionButton(
                    vm.calibration != nil ? "보정 해제" : "보정 시작",
                    icon: vm.calibration != nil ? "xmark.circle" : "scope",
                    prominent: vm.calibration == nil
                ) {
                    if vm.calibration != nil { vm.resetCalibration() } else { vm.startCalibration() }
                }
                if vm.showGuide {
                    actionButton(
                        vm.rimOnRight ? "림: 우측" : "림: 좌측",
                        icon: "arrow.left.arrow.right"
                    ) { vm.rimOnRight.toggle() }
                }
            }
        }
    }

    // MARK: - 체크리스트 & 보정 카드

    private func checkRow(_ check: GuideCheck) -> some View {
        HStack(spacing: 8) {
            Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(check.passed ? HUD.gold : HUD.orange)
            Text(check.title)
                .font(HUD.font(12, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HUDHeader(title: vm.isReady ? "READY · 준비 완료" : "SETUP CHECKLIST")

            if !vm.isReady {
                ForEach(vm.guideChecks) { check in
                    checkRow(check)
                }
                if let hint = vm.firstHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(HUD.gold)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
        .hudPanel(tint: vm.isReady ? HUD.gold : Color.white)
    }

    private var stepTitle: String {
        switch vm.calibrationStep {
        case .rim: return "STEP 1 · 림 지정"
        case .backboardTop: return "STEP 2 · 백보드 상단"
        case .backboardBottom: return "STEP 3 · 백보드 하단"
        case .review: return "STEP 4 · 보정 확인"
        case .off: return ""
        }
    }

    private var stepDescription: String {
        switch vm.calibrationStep {
        case .rim: return "림 중앙을 탭하고 슬라이더로 크기를 맞추세요."
        case .backboardTop: return "백보드 가장 위쪽 끝을 탭하세요."
        case .backboardBottom: return "백보드 가장 아래쪽 끝을 탭하세요."
        case .review: return "항목이 모두 통과되면 고정을 누르세요."
        case .off: return ""
        }
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HUDHeader(title: stepTitle)
            Text(stepDescription)
                .font(.caption2)
                .foregroundStyle(HUD.dim)
                .fixedSize(horizontal: false, vertical: true)

            if vm.calibrationStep == .review {
                ForEach(vm.calibrationChecks) { check in
                    checkRow(check)
                }
                Text("롤 \(vm.tiltRoll, specifier: "%.1f")° · 피치 \(vm.tiltPitch, specifier: "%.1f")°")
                    .font(HUD.font(11, .semibold).monospacedDigit())
                    .foregroundStyle(HUD.dim)
                if let hint = vm.firstCalibrationHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(HUD.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .hudPanel(tint: HUD.gold)
    }

    private func calibrationBadge(_ cal: CameraCalibration) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(HUD.gold)
            Text("보정됨 · 롤 \(cal.rollDegrees, specifier: "%.1f")°")
                .font(HUD.font(12, .bold))
                .foregroundStyle(Color.white)
            Spacer()
        }
        .hudPanel(tint: HUD.gold)
    }

    // MARK: - 피드백 배너

    private func bannerColor(_ shot: ShotAnalysisReport) -> Color {
        switch shot.feedback {
        case .perfect: HUD.gold
        case .flat: HUD.orange
        case .steep: HUD.cyan
        }
    }

    private func goalTag(_ shot: ShotAnalysisReport) -> some View {
        Text(shot.made ? "GOAL" : "MISS")
            .font(HUD.font(11, .heavy))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(shot.made ? ShotColor.made : ShotColor.miss)
            .clipShape(Capsule())
    }

    private func feedbackBanner(_ shot: ShotAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(shot.feedback.title)
                    .font(HUD.font(15, .heavy))
                goalTag(shot)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.1f°", shot.measuredEntryAngle))
                    .font(HUD.font(28, .black).monospacedDigit())
                    .foregroundStyle(HUD.orange)
                Text("목표 45° ±2°")
                    .font(HUD.font(11, .semibold))
                    .foregroundStyle(HUD.dim)
            }
        }
        .hudPanel(tint: bannerColor(shot))
    }

    // MARK: - 누적 통계 패널 (Nike Run Club 스타일)

    private var perfectRate: Double {
        guard !vm.shots.isEmpty else { return 0 }
        return Double(vm.shots.filter { $0.isPerfect }.count) / Double(vm.shots.count)
    }

    private func stat(_ title: String, _ value: String, color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(HUD.font(10, .bold))
                .foregroundStyle(HUD.dim)
            Text(value)
                .font(HUD.font(19, .heavy).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsChart: some View {
        Chart {
            RuleMark(y: .value("목표", ShotTarget.angle))
                .foregroundStyle(HUD.gold.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(Array(vm.shots.enumerated()), id: \.offset) { index, shot in
                LineMark(x: .value("슛", index), y: .value("각도", shot.measuredEntryAngle))
                    .foregroundStyle(Color.white.opacity(0.5))
                PointMark(x: .value("슛", index), y: .value("각도", shot.measuredEntryAngle))
                    .foregroundStyle(shot.made ? ShotColor.made : ShotColor.miss)
                    .symbolSize(45)
            }
        }
        .chartYScale(domain: 25...70)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(HUD.font(10, .semibold))
                .foregroundStyle(HUD.dim)
        }
    }

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HUDHeader(title: "SHOT SUMMARY")

            HStack(alignment: .center, spacing: 12) {
                RingGauge(progress: perfectRate, label: "\(Int(perfectRate * 100))%", color: HUD.gold)
                    .frame(width: 48, height: 48)

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        stat("SHOTS", "\(vm.shots.count)", color: .white)
                        stat("GOAL", "\(vm.madeCount)", color: ShotColor.made)
                    }
                    HStack(spacing: 8) {
                        stat("AVG", vm.averageAngle.map { String(format: "%.1f°", $0) } ?? "–", color: HUD.orange)
                        stat("SPREAD", vm.consistency.map { String(format: "±%.1f°", $0) } ?? "–", color: HUD.gold)
                    }
                }
            }

            DottedLine()

            HStack(spacing: 8) {
                ArcMapView(path: vm.lastShot?.path.points ?? [], rim: vm.rim)
                    .frame(width: 72, height: 50)
                statsChart
                    .frame(height: 50)
            }

            HStack(spacing: 10) {
                legendDot(ShotColor.made, "성공")
                legendDot(ShotColor.miss, "실패")
                Spacer()
                Text("길게 눌러 초기화")
                    .font(HUD.font(10, .semibold))
                    .foregroundStyle(HUD.dim)
            }
        }
        .hudPanel(tint: Color.white.opacity(0.5))
        .onLongPressGesture { vm.resetStats() }
    }
}
