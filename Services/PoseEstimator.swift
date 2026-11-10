import Vision

struct WristObservation: Sendable {
    let point: NormalizedPoint
    let confidence: Float
    let side: Side

    enum Side: Sendable {
        case left
        case right
    }
}

enum PoseEstimator {
    static func bestWrist(from observation: VNHumanBodyPoseObservation?) -> WristObservation? {
        guard let observation else { return nil }

        let candidates: [WristObservation] = [
            wrist(.rightWrist, side: .right, from: observation),
            wrist(.leftWrist, side: .left, from: observation)
        ].compactMap { $0 }

        return candidates.max { $0.confidence < $1.confidence }
    }

    private static func wrist(
        _ joint: VNHumanBodyPoseObservation.JointName,
        side: WristObservation.Side,
        from observation: VNHumanBodyPoseObservation
    ) -> WristObservation? {
        guard let point = try? observation.recognizedPoint(joint), point.confidence >= 0.35 else {
            return nil
        }
        return WristObservation(
            point: NormalizedPoint(point.location),
            confidence: point.confidence,
            side: side
        )
    }
}
