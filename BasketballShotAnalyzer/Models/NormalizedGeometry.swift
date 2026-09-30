import CoreGraphics

struct NormalizedPoint: Hashable, Sendable {
    let x: CGFloat
    let y: CGFloat

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    static func clamped(x: CGFloat, y: CGFloat) -> NormalizedPoint {
        NormalizedPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    func distance(to other: NormalizedPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

enum VideoLayout {
    static func fittedRect(in container: CGSize, videoSize: CGSize) -> CGRect {
        guard container.width > 0, container.height > 0,
              videoSize.width > 0, videoSize.height > 0 else {
            return .zero
        }

        let scale = min(container.width / videoSize.width, container.height / videoSize.height)
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
