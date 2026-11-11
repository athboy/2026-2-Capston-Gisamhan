import SwiftUI
import AVFoundation
import Charts

// MARK: - 카메라 미리보기 (UIKit 브리지)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let angle: CGFloat   // 가로 = 0 또는 180

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

// MARK: - 실시간 분석 화면 (가로 전용)

struct LiveCameraView: View {
    @StateObject private var vm = LiveShotViewModel()
    @Environment(\.dismiss) private var dismiss

    /// 가로 화면에서의 림 폭 기본값 (세로 기준 7.5% × 가로 비율 0.5625)
    @State private var manualWidth: Double = 0.075 * 1080.0 / 1920.0

    /// 메뉴(아이콘 모음)가 펼쳐져 있는지
    @State private var menuOpen = false

    /// ⭐ 추가: 왼쪽 패널이 펼쳐져 있는지 (촬영 준비가 끝나면 자동으로 접혀요)
    @State private var panelExpanded = true

    var body: some View {
        GeometryReader { screen in
            let videoSize = filledVideoSize(in: screen.size)

            ZStack {
                Color.black

                videoLayer(size: videoSize)
                    .frame(width: videoSize.width, height: videoSize.height)
                    .position(x: screen.size.width / 2, y: screen.size.height / 2)

                uiLayer(screen: screen.size, insets: screen.safeAreaInsets)
            }
            .frame(width: screen.size.width, height: screen.size.height)
            .clipped()
            .onChange(of: screen.size) { _, _ in
                vm.refreshOrientation()
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .background(Color.black.ignoresSafeArea())
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
            panelExpanded = true   // ⭐ 방향이 바뀌면 림을 다시 찾아야 하니 패널을 펼쳐요
        }
        // ⭐ 촬영 준비가 되면 패널을 왼쪽 위 작은 상자로 접어요
        .onChange(of: vm.isReady) { _, ready in
            if ready {
                withAnimation(.easeOut(duration: 0.2)) { panelExpanded = false }
            }
        }
    }

    private func clamped(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), high)
    }

    /// 화면을 꽉 채우려면 영상(16:9)을 얼마나 키워야 하는지 계산
    private func filledVideoSize(in screen: CGSize) -> CGSize {
        let aspect: CGFloat = 16.0 / 9.0   // 가로 ÷ 세로
        let width = max(screen.width, screen.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    // MARK: 영상 판 (카메라 + 림 + 궤적 + 가이드 + 라벨)

    private func videoLayer(size: CGSize) -> some View {
        ZStack {
            CameraPreviewView(session: vm.camera.session, angle: vm.orientation.captureAngle)

            if vm.showGuide {
                guideOverlay(size: size)
            }

            backboardOverlay(size: size)

            if let rim = vm.rim {
                Capsule()
                    .stroke(HUD.cyan, style: StrokeStyle(lineWidth: 3, dash: [7, 4]))
                    .frame(width: size.width * rim.widthFraction, height: 13)
                    .position(x: size.width * rim.center.x, y: size.height * (1 - rim.center.y))
                    .shadow(color: HUD.cyan.opacity(0.9), radius: 6)
            }

            Path { path in
                for (i, p) in vm.ballPoints.enumerated() {
                    let pt = CGPoint(x: size.width * p.x, y: size.height * (1 - p.y))
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
            }
            .stroke(HUD.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .shadow(color: HUD.orange.opacity(0.8), radius: 4)

            if let shot = vm.lastShot {
                Path { path in
                    for (i, p) in shot.path.points.enumerated() {
                        let pt = CGPoint(x: size.width * p.x, y: size.height * (1 - p.y))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .shadow(color: HUD.cyan.opacity(0.9), radius: 6)
            }

            shotTags(size: size)
        }
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            // 화면을 탭하면 펼쳐진 메뉴는 접어요
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

    // MARK: 화면 판 (격자, 괄호, 버튼, 패널)

    /// 림 크기 슬라이더를 보여줄 때인가요?
    private var showRimSlider: Bool {
        vm.isManualRim && vm.calibration == nil
            && (vm.calibrationStep == .off || vm.calibrationStep == .rim)
    }

    private func uiLayer(screen: CGSize, insets: EdgeInsets) -> some View {
        let sideInset = max(insets.leading, insets.trailing)

        return ZStack {
            GridOverlay()
            CornerBrackets(length: 26)
                .stroke(HUD.cyan.opacity(0.85), lineWidth: 2)
                .padding(.top, max(insets.top, 8))
                .padding(.bottom, max(insets.bottom, 8))
                .padding(.horizontal, max(sideInset, 8))
        }
        .frame(width: screen.width, height: screen.height)
        .allowsHitTesting(false)
        // 위쪽 바 (메뉴 버튼 + 상태 글자)
        .overlay(alignment: .top) {
            topBar
                .padding(.top, insets.top)
                .padding(.horizontal, sideInset)
        }
        // ⭐ 림 반대편 위쪽: 펼친 패널 또는 접힌 작은 상자
        .overlay(alignment: vm.rimOnRight ? .topLeading : .topTrailing) {
            sidePanel(screen: screen, insets: insets, sideInset: sideInset)
        }
        // 림 크기 슬라이더 (림 쪽 아래 구석)
        .overlay(alignment: vm.rimOnRight ? .bottomTrailing : .bottomLeading) {
            if showRimSlider {
                rimSizePanel
                    .padding(vm.rimOnRight ? .trailing : .leading, sideInset + 12)
                    .padding(.bottom, insets.bottom + 8)
            }
        }
    }

    // MARK: ⭐ 옆 패널 (펼침 / 접힘)

    @ViewBuilder
    private func sidePanel(screen: CGSize, insets: EdgeInsets, sideInset: CGFloat) -> some View {
        // 보정 중에는 버튼(다음, 취소 등)이 패널 안에 있어서 항상 펼쳐 둬요
        let calibrating = vm.calibrationStep != .off

        if panelExpanded || calibrating {
            ScrollView {
                VStack(spacing: 10) {
                    if !calibrating { collapseButton }
                    panelContent
                }
                .padding(8)
            }
            .frame(width: min(260, screen.width * 0.4))
            .frame(maxHeight: screen.height - insets.top - insets.bottom - 72)
            .padding(.top, insets.top + 64)
            .padding(.horizontal, sideInset + 8)
        } else {
            summaryBox
                .padding(.top, insets.top + 64)
                .padding(.horizontal, sideInset + 8)
        }
    }

    /// 펼친 패널 맨 위의 "접기" 버튼
    private var collapseButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { panelExpanded = false }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                Text("접기")
            }
            .font(HUD.font(13, .semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Color.black.opacity(0.75))
            .overlay(Rectangle().stroke(HUD.cyan.opacity(0.6), lineWidth: 1))
        }
    }

    private func miniStat(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(HUD.font(9, .semibold))
                .foregroundStyle(HUD.dim)
            Text(value)
                .font(HUD.font(20).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    /// 접힌 작은 상자: 누르면 펼쳐져요
    private var summaryBox: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { panelExpanded = true }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: vm.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(vm.isReady ? HUD.cyan : HUD.orange)
                    Text(vm.isReady ? "READY" : "CHECK")
                        .font(HUD.font(14))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HUD.dim)
                }

                HStack(spacing: 12) {
                    miniStat("SHOTS", "\(vm.shots.count)", color: Color.white)
                    miniStat("GOAL", "\(vm.madeCount)", color: ShotColor.made)
                    miniStat("AVG",
                             vm.averageAngle.map { String(format: "%.1f°", $0) } ?? "–",
                             color: HUD.orange)
                }

                Text("TARGET 45° ± 2°")
                    .font(HUD.font(10, .semibold))
                    .foregroundStyle(HUD.gold)

                // 방금 던진 슛 결과 (4초 동안만 보여요)
                if let shot = vm.lastShot {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(bannerColor(shot))
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(String(format: "%.1f°", shot.measuredEntryAngle))
                                    .font(HUD.font(22).monospacedDigit())
                                    .foregroundStyle(HUD.orange)
                                goalTag(shot)
                            }
                            Text(shot.feedback.title)
                                .font(.caption2)
                                .foregroundStyle(Color.white)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                // 준비가 안 됐으면 무엇을 해야 하는지 한 줄로 알려줘요
                if !vm.isReady, let hint = vm.firstHint {
                    Text("▶ \(hint)")
                        .font(.caption2)
                        .foregroundStyle(HUD.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Color.white)
            .hudPanel(tint: vm.isReady ? HUD.cyan : HUD.orange)
            .frame(width: 210)
        }
        .buttonStyle(.plain)
    }

    // MARK: 슛 라벨

    private func shotTags(size: CGSize) -> some View {
        ZStack {
            if let shot = vm.lastShot {
                if let peak = shot.path.points.max(by: { $0.y < $1.y }) {
                    HUDTag(text: "SHOT ARC")
                        .position(
                            x: clamped(size.width * peak.x, 60, size.width - 60),
                            y: clamped(size.height * (1 - peak.y) - 26, 90, size.height - 90)
                        )
                }
                if let rim = vm.rim {
                    HUDTag(text: "SHOT ANGLE \(String(format: "%.1f", shot.measuredEntryAngle))°")
                        .position(
                            x: clamped(size.width * rim.center.x, 100, size.width - 100),
                            y: clamped(size.height * (1 - rim.center.y) + 30, 90, size.height - 90)
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 가이드 (점선 박스 + 수평선)

    private func guideOverlay(size: CGSize) -> some View {
        let center = ShootingGuide.targetCenter(rimOnRight: vm.rimOnRight)
        let boxWidth = size.width * ShootingGuide.boxHalfWidth(vm.orientation) * 2
        let boxHeight = size.height * ShootingGuide.boxHalfHeight(vm.orientation) * 2
        let boxX = size.width * center.x
        let boxY = size.height * (1 - center.y)
        let color: Color = vm.isReady ? HUD.cyan : Color.white
        let levelColor: Color = abs(vm.tiltRoll) <= ShootingGuide.maxRoll ? HUD.cyan : HUD.orange

        return ZStack {
            Rectangle()
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .frame(width: boxWidth, height: boxHeight)
                .position(x: boxX, y: boxY)

            Text("림을 여기에")
                .font(HUD.font(12, .semibold))
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

    // MARK: 백보드 표시

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
                    .font(HUD.font(12))
                    .foregroundStyle(HUD.gold)
                    .offset(x: 26)
            )
            .position(x: size.width * p.x, y: size.height * (1 - p.y))
    }

    // MARK: 아이콘 버튼들

    private func hudIcon(_ name: String, active: Bool, size: CGFloat = 40) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: size, height: size)
            .background(Color.black.opacity(active ? 0.9 : 0.6))
            .overlay(Rectangle().stroke(active ? HUD.cyan : HUD.cyan.opacity(0.4), lineWidth: 1))
            .foregroundStyle(active ? HUD.cyan : Color.white)
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.2)) { menuOpen = false }
    }

    private func closeButton(size: CGFloat) -> some View {
        Button { dismiss() } label: {
            hudIcon("xmark", active: false, size: size)
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

    // MARK: 메뉴 (버튼 1개 → 누르면 아이콘 4개가 펼쳐져요)

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
            closeButton(size: 40)
            guideButton(size: 40)
            calibrateButton(size: 40)
            manualButton(size: 40)
        }
        .transition(.opacity.combined(with: .move(edge: vm.rimOnRight ? .leading : .trailing)))
    }

    /// leading = true 이면 버튼이 왼쪽 끝, 아이콘은 그 오른쪽으로 펼쳐져요
    private func menuGroup(leading: Bool) -> some View {
        HStack(spacing: 8) {
            if leading { menuToggleButton }
            if menuOpen { menuItems }
            if !leading { menuToggleButton }
        }
    }

    // MARK: 림 크기 슬라이더 (한 줄짜리 작은 패널)

    private var rimSizePanel: some View {
        HStack(spacing: 8) {
            Text("림 크기")
                .font(HUD.font(12, .semibold))
            Slider(value: $manualWidth, in: 0.02...max(0.05, 0.20 * Double(vm.orientation.widthScale)))
                .tint(HUD.cyan)
                .onChange(of: manualWidth) { _, new in
                    if let rim = vm.rim {
                        vm.setManualRim(x: rim.center.x, y: rim.center.y, width: new)
                    }
                }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 240)
        .background(Color.black.opacity(0.7))
        .overlay(Rectangle().stroke(HUD.cyan.opacity(0.4), lineWidth: 1))
    }

    // MARK: 위쪽 바

    /// 림 반대편 구석에는 메뉴 버튼, 림 쪽 구석에는 상태 글자
    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if vm.rimOnRight {
                    menuGroup(leading: true)
                    Spacer(minLength: 0)
                    if !menuOpen { statusTag }
                } else {
                    if !menuOpen { statusTag }
                    Spacer(minLength: 0)
                    menuGroup(leading: false)
                }
            }

            if let notice = vm.notice {
                Text(notice)
                    .font(HUD.font(13, .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(HUD.orange)
            }

            if let error = vm.errorMessage {
                Text(error).font(.caption).foregroundStyle(HUD.orange)
            }
        }
        .foregroundStyle(Color.white)
        .padding(8)
    }

    private var statusTag: some View {
        Text(rimStatus)
            .font(HUD.font(13, .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .overlay(Rectangle().stroke(HUD.cyan.opacity(0.5), lineWidth: 1))
    }

    private var rimStatus: String {
        if vm.calibration != nil { return "CALIBRATED · 보정 고정됨" }
        if vm.calibrationStep == .rim || (vm.isManualRim && vm.rim == nil) {
            return "TAP · 화면을 탭해 림 지정"
        }
        if vm.calibrationStep != .off { return "CALIBRATING · 보정 중" }
        if vm.isManualRim { return "MANUAL · 림 수동 지정" }
        if vm.rim != nil { return "RIM LOCKED · 림 자동 인식됨" }
        return vm.hasModel ? "SCANNING · 림 탐색 중…" : "모델 없음 · 메뉴에서 수동 지정"
    }

    // MARK: 펼친 패널 내용 (버튼 줄이 맨 위)

    private var panelContent: some View {
        VStack(spacing: 10) {
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

    // MARK: 버튼 줄

    private func actionButton(
        _ title: String,
        icon: String? = nil,
        prominent: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(HUD.font(15))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(prominent ? HUD.orange : Color.black.opacity(0.75))
            .overlay(Rectangle().stroke(prominent ? HUD.orange : HUD.cyan.opacity(0.6), lineWidth: 1))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            switch vm.calibrationStep {
            case .rim:
                actionButton("취소") { vm.cancelCalibration() }
                actionButton("다음", prominent: true, enabled: vm.rim != nil) { vm.goNext() }
            case .backboardTop, .backboardBottom:
                actionButton("림 다시") { vm.redoRim() }
                actionButton("취소") { vm.cancelCalibration() }
            case .review:
                actionButton("림 다시") { vm.redoRim() }
                actionButton("백보드 다시") { vm.redoBackboard() }
                actionButton("보정 고정", prominent: true, enabled: vm.canLock) { vm.goNext() }
            case .off:
                actionButton(
                    vm.calibration != nil ? "보정 해제" : "보정 시작",
                    icon: vm.calibration != nil ? "xmark.circle" : "scope"
                ) {
                    if vm.calibration != nil { vm.resetCalibration() } else { vm.startCalibration() }
                }
                if vm.showGuide {
                    actionButton(
                        vm.rimOnRight ? "림: 오른쪽" : "림: 왼쪽",
                        icon: "arrow.left.arrow.right"
                    ) { vm.rimOnRight.toggle() }
                }
            }
        }
    }

    // MARK: 체크리스트 카드

    private func checkRow(_ check: GuideCheck) -> some View {
        HStack(spacing: 6) {
            Image(systemName: check.passed ? "checkmark.square.fill" : "xmark.square.fill")
                .foregroundStyle(check.passed ? HUD.cyan : HUD.orange)
            Text(check.title)
                .font(HUD.font(13, .semibold))
        }
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.isReady ? "READY · 촬영 준비 완료" : "CHECK · 촬영 준비 체크")
                .font(HUD.font(15))
                .foregroundStyle(vm.isReady ? HUD.cyan : Color.white)

            if !vm.isReady {
                DottedLine()
                ForEach(vm.guideChecks) { check in
                    checkRow(check)
                }
                if let hint = vm.firstHint {
                    Text("▶ \(hint)")
                        .font(.caption2)
                        .foregroundStyle(HUD.gold)
                }
                Text("폰은 가로로 삼각대에 고정 · 슈터 옆(측면)에서 · 가슴 높이(약 1.2~1.5m)")
                    .font(.caption2)
                    .foregroundStyle(HUD.dim)
            }
        }
        .hudPanel(tint: HUD.cyan)
    }

    // MARK: 보정 카드

    private var stepTitle: String {
        switch vm.calibrationStep {
        case .rim: return "STEP 1 · 림 지정"
        case .backboardTop: return "STEP 2 · 백보드 위쪽 끝"
        case .backboardBottom: return "STEP 3 · 백보드 아래쪽 끝"
        case .review: return "STEP 4 · 확인하고 고정"
        case .off: return ""
        }
    }

    private var stepDescription: String {
        switch vm.calibrationStep {
        case .rim: return "림의 가운데를 탭하고, 림 크기 슬라이더로 점선 길이를 림 크기에 맞춰 주세요."
        case .backboardTop: return "백보드에서 가장 높은 가장자리를 탭해 주세요."
        case .backboardBottom: return "백보드에서 가장 낮은 가장자리를 탭해 주세요."
        case .review: return "아래 5가지가 모두 통과하면 '보정 고정'을 누를 수 있어요."
        case .off: return ""
        }
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HUDHeader(title: stepTitle)
            Text(stepDescription).font(.caption)

            if vm.calibrationStep == .review {
                ForEach(vm.calibrationChecks) { check in
                    checkRow(check)
                }
                Text("TILT  롤 \(vm.tiltRoll, specifier: "%.1f")° · 피치 \(vm.tiltPitch, specifier: "%.1f")°")
                    .font(HUD.font(12, .semibold).monospacedDigit())
                    .foregroundStyle(HUD.dim)
                if let hint = vm.firstCalibrationHint {
                    Text("▶ \(hint)")
                        .font(.caption2)
                        .foregroundStyle(HUD.gold)
                }
            }
        }
        .hudPanel(tint: HUD.gold)
    }

    private func calibrationBadge(_ cal: CameraCalibration) -> some View {
        HStack {
            Text("CALIBRATED · 롤 \(cal.rollDegrees, specifier: "%.1f")°")
                .font(HUD.font(13, .semibold))
                .foregroundStyle(HUD.cyan)
            Spacer()
        }
        .hudPanel(tint: HUD.cyan)
    }

    // MARK: 피드백 배너

    private func bannerColor(_ shot: ShotAnalysisReport) -> Color {
        switch shot.feedback {
        case .perfect: HUD.cyan
        case .flat: HUD.orange
        case .steep: HUD.gold
        }
    }

    /// ⭐ 추가: 골 / 노골 표시
    private func goalTag(_ shot: ShotAnalysisReport) -> some View {
        Text(shot.made ? "GOAL" : "MISS")
            .font(HUD.font(12))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(shot.made ? ShotColor.made : ShotColor.miss)
    }

    private func feedbackBanner(_ shot: ShotAnalysisReport) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(bannerColor(shot))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(shot.feedback.title)
                        .font(HUD.font(18))
                    goalTag(shot)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.1f°", shot.measuredEntryAngle))
                        .font(HUD.font(32).monospacedDigit())
                        .foregroundStyle(HUD.orange)
                    Text("TARGET 45° ± 2°")
                        .font(HUD.font(13, .semibold))
                        .foregroundStyle(HUD.gold)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .hudPanel(tint: bannerColor(shot))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: 통계 패널 (Nike 스타일)

    /// 목표 45° ±2° 안에 들어온 슛의 비율
    private var perfectRate: Double {
        guard !vm.shots.isEmpty else { return 0 }
        return Double(vm.shots.filter { $0.isPerfect }.count) / Double(vm.shots.count)
    }

    private func stat(_ title: String, _ value: String, color: Color = HUD.orange) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(HUD.font(10, .semibold))
                .foregroundStyle(HUD.dim)
            Text(value)
                .font(HUD.font(22).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    /// ⭐ 수정: 입사각 추이 — 골은 파랑, 노골은 빨강, 점선은 목표 45°
    private var statsChart: some View {
        Chart {
            RuleMark(y: .value("목표", ShotTarget.angle))
                .foregroundStyle(HUD.cyan.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(Array(vm.shots.enumerated()), id: \.offset) { index, shot in
                LineMark(x: .value("슛", index), y: .value("각도", shot.measuredEntryAngle))
                    .foregroundStyle(HUD.gold)
                PointMark(x: .value("슛", index), y: .value("각도", shot.measuredEntryAngle))
                    .foregroundStyle(shot.made ? ShotColor.made : ShotColor.miss)
                    .symbolSize(55)
            }
        }
        .chartYScale(domain: 25...70)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(HUD.font(10, .semibold))
                .foregroundStyle(HUD.dim)
        }
    }

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HUDHeader(title: "SHOT SUMMARY")

            HStack(alignment: .center, spacing: 12) {
                RingGauge(progress: perfectRate, label: "\(Int(perfectRate * 100))%")
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 14) {
                        stat("SHOTS", "\(vm.shots.count)", color: Color.white)
                        stat("GOAL", "\(vm.madeCount)", color: ShotColor.made)
                    }
                    HStack(spacing: 14) {
                        stat("AVG", vm.averageAngle.map { String(format: "%.1f°", $0) } ?? "–")
                        stat("SPREAD", vm.consistency.map { String(format: "±%.1f°", $0) } ?? "–", color: HUD.gold)
                    }
                }
            }

            Text("동그라미 = 목표 45° ±2° 적중률")
                .font(.caption2)
                .foregroundStyle(HUD.dim)

            DottedLine()

            HStack(spacing: 10) {
                ArcMapView(path: vm.lastShot?.path.points ?? [], rim: vm.rim)
                    .frame(width: 80, height: 56)
                statsChart
                    .frame(height: 56)
            }

            HStack(spacing: 12) {
                legendDot(ShotColor.made, "골")
                legendDot(ShotColor.miss, "노골")
                Text("점선 = 45°")
                    .font(HUD.font(10, .semibold))
                    .foregroundStyle(HUD.cyan)
            }
        }
        .hudPanel(tint: HUD.orange)
        .onLongPressGesture { vm.resetStats() }
    }
}
