import CoreGraphics

struct RimCalibration: Equatable, Sendable {
    static let regulationDiameterMeters: CGFloat = 0.45

    var center: NormalizedPoint
    /// Rim diameter as a fraction of the upright video width.
    var widthFraction: CGFloat

    init(center: NormalizedPoint, widthFraction: CGFloat = 0.075) {
        self.center = center
        self.widthFraction = min(max(widthFraction, 0.02), 0.20)
    }

    var metersPerNormalizedX: CGFloat {
        Self.regulationDiameterMeters / widthFraction
    }

    func metersPerNormalizedY(heightToWidthRatio: CGFloat) -> CGFloat {
        metersPerNormalizedX * heightToWidthRatio
    }
}
