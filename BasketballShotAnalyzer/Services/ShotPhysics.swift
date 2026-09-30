import CoreGraphics
import Foundation

enum ShotPhysics {
    static let gravity = 9.80665
    static let standardTargetAngle = 45.0

    static func entryAngle(a: CGFloat, b: CGFloat, rimX: CGFloat, heightToWidthRatio: CGFloat) -> Double? {
        let slope = heightToWidthRatio * (2 * a * rimX + b)
        guard slope.isFinite else { return nil }
        return atan(abs(Double(slope))) * 180 / .pi
    }

    static func dynamicEstimate(
        a: CGFloat,
        b: CGFloat,
        releasePoint: NormalizedPoint,
        wrist: WristObservation?,
        rim: RimCalibration,
        heightToWidthRatio: CGFloat
    ) -> PhysicalEstimate? {
        let correctedRelease = correctedReleasePoint(
            trajectoryRelease: releasePoint,
            wrist: wrist
        )
        let scaleX = rim.metersPerNormalizedX
        let scaleY = rim.metersPerNormalizedY(heightToWidthRatio: heightToWidthRatio)
        let coefficientInMeters = Double(a * scaleY / (scaleX * scaleX))

        // A downward-opening parabola in Vision's bottom-left coordinate system has a < 0.
        guard coefficientInMeters < -0.000_001 else { return nil }
        let horizontalSpeed = sqrt(gravity / (-2 * coefficientInMeters))
        let shotDistance = Double(abs(rim.center.x - correctedRelease.point.x) * scaleX)
        guard shotDistance > 0.5, horizontalSpeed.isFinite, horizontalSpeed > 0.1 else { return nil }

        let releaseHeight = Double(
            3.05 + (correctedRelease.point.y - rim.center.y) * scaleY
        )
        let verticalDifference = 3.05 - releaseHeight
        let ballisticTerm = gravity * shotDistance * shotDistance / (2 * horizontalSpeed * horizontalSpeed)
        let discriminant = shotDistance * shotDistance - 4 * ballisticTerm * (ballisticTerm + verticalDifference)
        guard discriminant >= 0, ballisticTerm > 0 else { return nil }

        let roots = [
            (shotDistance + sqrt(discriminant)) / (2 * ballisticTerm),
            (shotDistance - sqrt(discriminant)) / (2 * ballisticTerm)
        ].filter { $0 > 0 && $0.isFinite }
        guard let launchTangent = roots.max() else { return nil }

        let entrySlope = launchTangent - gravity * shotDistance / (horizontalSpeed * horizontalSpeed) * (1 + launchTangent * launchTangent)
        let entryAngle = atan(abs(entrySlope)) * 180 / .pi
        guard entryAngle.isFinite else { return nil }

        return PhysicalEstimate(
            releaseHeightMeters: releaseHeight,
            shotDistanceMeters: shotDistance,
            horizontalSpeedMetersPerSecond: horizontalSpeed,
            targetEntryAngle: min(max(entryAngle, 35), 60),
            usedWristCorrection: correctedRelease.usedWristCorrection
        )
    }

    private static func correctedReleasePoint(
        trajectoryRelease: NormalizedPoint,
        wrist: WristObservation?
    ) -> (point: NormalizedPoint, usedWristCorrection: Bool) {
        guard let wrist, wrist.confidence >= 0.5,
              trajectoryRelease.distance(to: wrist.point) < 0.18 else {
            return (trajectoryRelease, false)
        }

        // The ball's detected start is more reliable for the horizontal component;
        // the wrist stabilizes the release-height estimate when the ball overlaps the hand.
        return (
            NormalizedPoint(
                x: trajectoryRelease.x * 0.65 + wrist.point.x * 0.35,
                y: trajectoryRelease.y * 0.55 + wrist.point.y * 0.45
            ),
            true
        )
    }
}
