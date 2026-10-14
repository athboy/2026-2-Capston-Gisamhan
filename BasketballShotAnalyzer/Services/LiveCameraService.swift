@preconcurrency import AVFoundation

enum LiveCameraError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: return "카메라 권한이 없습니다. 설정 앱에서 허용해 주세요."
        case .unavailable: return "카메라를 사용할 수 없습니다."
        }
    }
}

final class LiveCameraService: NSObject, @unchecked Sendable {
    /// 분석 프레임 크기 (가로 1920x1080)
    static let frameSize = CGSize(width: 1920, height: 1080)
    /// 가로 거치(Landscape Right) 기준 회전 각도. (거꾸로 보이면 180으로 변경)
    static let landscapeRotationAngle: CGFloat = 0

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
        queue.async { [self] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            throw LiveCameraError.unavailable
        }

        try configureFormat(device)

        session.beginConfiguration()
        session.sessionPreset = .inputPriority

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw LiveCameraError.unavailable
        }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw LiveCameraError.unavailable
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(Self.landscapeRotationAngle) {
                connection.videoRotationAngle = Self.landscapeRotationAngle
            }
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
