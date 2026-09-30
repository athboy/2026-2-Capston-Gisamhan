import AVFoundation
import CoreVideo

final class VideoFrameReader {
    typealias FrameHandler = (_ pixelBuffer: CVPixelBuffer, _ presentationTime: CMTime, _ progress: Double) throws -> Void

    func readFrames(from video: VideoAssetInfo, onFrame: FrameHandler) async throws {
        let asset = AVURLAsset(url: video.url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw ShotAnalysisError.noVideoTrack
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw ShotAnalysisError.cannotReadVideo
        }

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw ShotAnalysisError.cannotReadVideo
        }
        reader.add(output)

        guard reader.startReading() else {
            throw ShotAnalysisError.cannotReadVideo
        }

        var lastAcceptedTime = CMTime.invalid
        let maximumAnalysisFPS = 30.0
        let minimumSpacing = 1.0 / maximumAnalysisFPS

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let seconds = presentationTime.seconds
            guard seconds.isFinite else { continue }

            if lastAcceptedTime.isValid,
               seconds - lastAcceptedTime.seconds < minimumSpacing {
                continue
            }
            lastAcceptedTime = presentationTime

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let progress = video.durationSeconds > 0 ? min(max(seconds / video.durationSeconds, 0), 1) : 0
            try onFrame(pixelBuffer, presentationTime, progress)
        }

        guard reader.status == .completed || reader.status == .reading else {
            throw reader.error ?? ShotAnalysisError.cannotReadVideo
        }
    }
}
