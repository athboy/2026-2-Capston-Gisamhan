import AVFoundation
import CoreGraphics
import ImageIO

struct VideoAssetInfo: Sendable {
    let url: URL
    let displaySize: CGSize
    let durationSeconds: Double
    let imageOrientation: CGImagePropertyOrientation

    var heightToWidthRatio: CGFloat {
        guard displaySize.width > 0 else { return 1 }
        return displaySize.height / displaySize.width
    }
}

enum VideoAssetLoader {
    static func load(url: URL) async throws -> VideoAssetInfo {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw ShotAnalysisError.noVideoTrack
        }

        let rawSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let transformedSize = rawSize.applying(preferredTransform)
        let displaySize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        return VideoAssetInfo(
            url: url,
            displaySize: displaySize,
            durationSeconds: max(duration.seconds, 0),
            imageOrientation: orientation(for: preferredTransform)
        )
    }

    private static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let a = Int(transform.a.rounded())
        let b = Int(transform.b.rounded())
        let c = Int(transform.c.rounded())
        let d = Int(transform.d.rounded())

        switch (a, b, c, d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}
