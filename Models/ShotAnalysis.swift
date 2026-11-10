import CoreGraphics
import Foundation

enum AnalysisState: Equatable {
    case idle
    case loadingVideo
    case ready
    case processing(progress: Double)
    case completed
    case failed(message: String)

    var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }
}

enum FeedbackTone: String, Sendable {
    case perfect
    case flat
    case steep

    var title: String {
        switch self {
        case .perfect: "안정적인 아크"
        case .flat: "아크를 높여보세요"
        case .steep: "아크를 조금 낮춰보세요"
        }
    }

    var detail: String {
        switch self {
        case .perfect:
            "동적 목표각의 ±2° 안에 들어왔습니다. 현재 릴리즈 감각을 유지해보세요."
        case .flat:
            "입사각이 목표보다 낮습니다. 릴리즈를 더 위로 밀어 올려 림 위의 여유 공간을 확보해보세요."
        case .steep:
            "입사각이 목표보다 높습니다. 점프 정점에서의 전방 추진을 조금 더 확보해보세요."
        }
    }
}

struct TrajectoryPath: Equatable, Sendable {
    let points: [NormalizedPoint]
}

struct PhysicalEstimate: Equatable, Sendable {
    let releaseHeightMeters: Double
    let shotDistanceMeters: Double
    let horizontalSpeedMetersPerSecond: Double
    let targetEntryAngle: Double
    let usedWristCorrection: Bool
}

struct ShotAnalysisReport: Equatable, Sendable {
    let measuredEntryAngle: Double
    let targetEntryAngle: Double
    let difference: Double
    let feedback: FeedbackTone
    let path: TrajectoryPath
    let confidence: Double
    let physicalEstimate: PhysicalEstimate?
    let dynamicTargetAvailable: Bool

    var isPerfect: Bool {
        feedback == .perfect
    }
}

enum ShotAnalysisError: LocalizedError {
    case noVideoTrack
    case cannotReadVideo
    case noTrajectory
    case rimNotReached

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            "선택한 파일에서 영상 트랙을 찾지 못했습니다."
        case .cannotReadVideo:
            "영상을 읽을 수 없습니다. 다른 파일을 선택해 주세요."
        case .noTrajectory:
            "공의 포물선 궤적을 찾지 못했습니다. 공과 림이 잘 보이는 영상을 사용해 보세요."
        case .rimNotReached:
            "검출된 궤적이 지정한 림 위치까지 이어지지 않았습니다. 림 위치를 다시 맞춰 보세요."
        }
    }
}
