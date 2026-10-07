@preconcurrency import AVFoundation   // ⭐ 수정 ①: 앞에 @preconcurrency 추가

enum LiveCameraError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: "카메라 권한이 없습니다. 설정 앱에서 허용해 주세요."
        case .unavailable: "카메라를 사용할 수 없습니다."
        }
    }
}

final class LiveCameraService: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    var onFrame: (@Sendable (CMSampleBuffer) -> Void)?

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "live.camera.queue", qos: .userInitiated)
    private var configured = false

    func start() async throws {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw LiveCameraError.denied }
        if !configured {
            try configure()
            configured = true
        }
        // ⭐ 수정 ②: [session] 대신 [self] 사용 (self는 @unchecked Sendable이라 경고가 안 나요)
        queue.async { [self] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        // ⭐ 수정 ③: 여기도 [session] 대신 [self]
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            throw LiveCameraError.unavailable
        }

        // 1080p + 가능하면 60fps 포맷 선택 (림 근처에서 궤적 점을 더 많이 얻기 위함)
        try configureFormat(device)

        session.beginConfiguration()
        session.sessionPreset = .inputPriority   // 위에서 고른 activeFormat을 유지

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw LiveCameraError.unavailable
        }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true   // 분석이 느리면 오래된 프레임은 버림 (실시간성 유지)
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw LiveCameraError.unavailable
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            // 세로 화면 기준으로 "똑바로 선" 프레임을 받는다 → Vision orientation은 .up
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            // 손떨림 보정은 화면을 크롭/워핑해서 궤적 좌표를 왜곡할 수 있어 끈다
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off
            }
        }
        session.commitConfiguration()
    }

    private func configureFormat(_ device: AVCaptureDevice) throws {
        let hd = device.formats.filter {
            let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return d.width == 1920 && d.height == 1080
        }
        let format60 = hd.first { $0.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 } }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        var fps: Int32 = 30
        if let format60 {
            device.activeFormat = format60
            fps = 60
        } else if let format = hd.first {
            device.activeFormat = format
        }
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: fps)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: fps)
    }
}

extension LiveCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onFrame?(sampleBuffer)
    }
}
