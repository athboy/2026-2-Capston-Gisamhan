import CoreMedia
import CoreVideo
import CoreGraphics
import ImageIO
import Vision
import AVFoundation
import CoreImage

struct TrajectoryDetectionConfiguration: Sendable {
    /// Excludes a small top/bottom margin while retaining the full shooting lane.
    let regionOfInterest = CGRect(x: 0, y: 0.06, width: 1, height: 0.90)
    let minimumBallRadius: Float = 0.006
    let maximumBallRadius: Float = 0.055
    let trajectoryLength = 7
}

struct TrajectorySnapshot: Sendable {
    let detectedPoints: [NormalizedPoint]
    let projectedPoints: [NormalizedPoint]
    let a: CGFloat
    let b: CGFloat
    let c: CGFloat
    let confidence: Float
    let timestamp: CMTime
    let wrist: NormalizedPoint?
}

struct FrameObservation: Sendable {
    let trajectory: TrajectorySnapshot?
    let wrist: WristObservation?
}

final class TrajectoryEstimator {
    private let sequenceHandler = VNSequenceRequestHandler()
    private let trajectoryRequest: VNDetectTrajectoriesRequest
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    init(configuration: TrajectoryDetectionConfiguration = .init()) {
        trajectoryRequest = VNDetectTrajectoriesRequest(
            frameAnalysisSpacing: .zero,
            trajectoryLength: configuration.trajectoryLength
        )
        trajectoryRequest.regionOfInterest = configuration.regionOfInterest
        trajectoryRequest.objectMinimumNormalizedRadius = configuration.minimumBallRadius
        trajectoryRequest.objectMaximumNormalizedRadius = configuration.maximumBallRadius
    }

    func analyze(
        pixelBuffer: CVPixelBuffer,
        timestamp: CMTime,
        orientation: CGImagePropertyOrientation
    ) throws -> FrameObservation {
        try sequenceHandler.perform([trajectoryRequest, poseRequest], on: pixelBuffer, orientation: orientation)

        let wrist = PoseEstimator.bestWrist(from: poseRequest.results?.first)
        let trajectory = trajectoryRequest.results?
            .max { lhs, rhs in
                let lhsScore = lhs.confidence * Float(max(lhs.projectedPoints.count, lhs.detectedPoints.count))
                let rhsScore = rhs.confidence * Float(max(rhs.projectedPoints.count, rhs.detectedPoints.count))
                return lhsScore < rhsScore
            }
            .map { observation in
                let coefficients = observation.equationCoefficients
                return TrajectorySnapshot(
                    detectedPoints: observation.detectedPoints.map { NormalizedPoint($0.location) },
                    projectedPoints: observation.projectedPoints.map { NormalizedPoint($0.location) },
                    a: CGFloat(coefficients.x),
                    b: CGFloat(coefficients.y),
                    c: CGFloat(coefficients.z),
                    confidence: observation.confidence,
                    timestamp: timestamp,
                    wrist: wrist?.point
                )
            }

        return FrameObservation(trajectory: trajectory, wrist: wrist)
    }
}
import Vision
import CoreMedia
import AVFoundation
import CoreImage

// 1. 분석 진단용 데이터 구조체 (실패 원인 파악)
struct ShotDiagnostic {
    var frameIndex: Int
    var appliedROI: CGRect
    var detectedCount: Int
    var error: Error?
}

class ShotTrajectoryAnalyzer {
    // 2. 최소 궤적 기준 하향 (7 -> 5)
    private let minTrajectoryLength = 5
    
    // 3. 노이즈 방지를 위해 화면 위/아래 약간을 자른 동적 ROI (기존 TrajectoryDetectionConfiguration과 동일)
    var trackingROI: CGRect = CGRect(x: 0, y: 0.06, width: 1, height: 0.90)

    // 4. 멀티 패스 공 크기 정의 (아주 작은 공의 노이즈를 줄이기 위해 최소값을 0.005로 상향)
    private let ballSizePasses: [(min: Float, max: Float)] = [
        (0.005, 0.015), 
        (0.015, 0.055), 
        (0.055, 0.150)  
    ]

    func analyzeVideo(asset: AVAsset) async throws -> [TrajectorySnapshot] {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
        
        let transform = try await track.load(.preferredTransform)
        let videoOrientation = orientationFromTransform(transform)
        
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        // VNSequenceRequestHandler는 이전 프레임과 현재 프레임을 비교(Optical Flow)하므로, 이전 프레임의 메모리가 보존되어야 합니다.
        // 항상 새로운 메모리를 할당하도록 true로 설정합니다. (프레임을 배열에 저장하지 않으므로 RAM 폭발은 일어나지 않습니다)
        output.alwaysCopiesSampleData = true 
        
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        reader.startReading()
        
        struct PassConfig {
            let request: VNDetectTrajectoriesRequest
            let handler: VNSequenceRequestHandler
        }
        
        var passes: [PassConfig] = []
        for pass in ballSizePasses {
            let request = VNDetectTrajectoriesRequest(frameAnalysisSpacing: .zero, trajectoryLength: minTrajectoryLength)
            request.objectMinimumNormalizedRadius = pass.min
            request.objectMaximumNormalizedRadius = pass.max
            request.regionOfInterest = trackingROI
            
            passes.append(PassConfig(request: request, handler: VNSequenceRequestHandler()))
        }
        
        var allSnapshots: [TrajectorySnapshot] = []
        let poseRequest = VNDetectHumanBodyPoseRequest()
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            // 손목 위치 추적
            var currentWrist: NormalizedPoint? = nil
            do {
                let poseHandler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: videoOrientation)
                try poseHandler.perform([poseRequest])
                if let wristObs = PoseEstimator.bestWrist(from: poseRequest.results?.first) {
                    currentWrist = wristObs.point
                }
            } catch { }
            
            for pass in passes {
                do {
                    try pass.handler.perform([pass.request], on: sampleBuffer, orientation: videoOrientation)
                    
                    if let results = pass.request.results {
                        for observation in results {
                            let coef = observation.equationCoefficients
                            let snapshot = TrajectorySnapshot(
                                detectedPoints: observation.detectedPoints.map { NormalizedPoint($0.location) },
                                projectedPoints: observation.projectedPoints.map { NormalizedPoint($0.location) },
                                a: CGFloat(coef.x),
                                b: CGFloat(coef.y),
                                c: CGFloat(coef.z),
                                confidence: observation.confidence,
                                timestamp: timestamp,
                                wrist: currentWrist
                            )
                            allSnapshots.append(snapshot)
                        }
                    }
                } catch {
                }
            }
        }
        
        return allSnapshots
    }
    
    private func orientationFromTransform(_ transform: CGAffineTransform) -> CGImagePropertyOrientation {
        var assetOrientation = CGImagePropertyOrientation.up
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            assetOrientation = .right
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            assetOrientation = .left
        } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
            assetOrientation = .up
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            assetOrientation = .down
        }
        return assetOrientation
    }
}
