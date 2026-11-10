import AVFoundation
import PhotosUI
import SwiftUI

@MainActor
final class ShotAnalysisViewModel: ObservableObject {
    @Published private(set) var video: VideoAssetInfo?
    @Published private(set) var player: AVPlayer?
    @Published private(set) var analysisState: AnalysisState = .idle
    @Published private(set) var reports: [ShotAnalysisReport] = []
    @Published var selectedReportIndex: Int = 0
    @Published var rim: RimCalibration?

    private var activeAnalysisID: UUID?
    var rimWidthFraction: CGFloat {
        get { rim?.widthFraction ?? 0.075 }
        set {
            guard var rim else { return }
            rim.widthFraction = min(max(newValue, 0.02), 0.20)
            self.rim = rim
            reports = []
        }
    }

    func load(item: PhotosPickerItem?) async {
        guard let item else { return }
        activeAnalysisID = nil
        analysisState = .loadingVideo
        reports = []
        selectedReportIndex = 0
        rim = nil
        player?.pause()

        do {
            guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
                analysisState = .failed(message: "선택한 영상을 불러오지 못했습니다.")
                return
            }
            let video = try await VideoAssetLoader.load(url: movie.url)
            self.video = video
            player = AVPlayer(url: movie.url)
            analysisState = .ready
        } catch {
            analysisState = .failed(message: error.localizedDescription)
        }
    }

    func setRimCenter(_ center: NormalizedPoint) {
        let width = rim?.widthFraction ?? 0.075
        rim = RimCalibration(center: center, widthFraction: width)
        reports = []
    }

    func resetAnalysis() {
        activeAnalysisID = nil
        reports = []
        selectedReportIndex = 0
        analysisState = video == nil ? .idle : .ready
    }

    var selectedReport: ShotAnalysisReport? {
        guard reports.indices.contains(selectedReportIndex) else { return nil }
        return reports[selectedReportIndex]
    }

    func analyze() {
        guard let video, let rim else { return }
        player?.pause()
        reports = []
        selectedReportIndex = 0
        let analysisID = UUID()
        activeAnalysisID = analysisID
        analysisState = .processing(progress: 0)
        let input = VideoAnalysisInput(video: video, rim: rim)
        let updateProgress: @Sendable (Double) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard self?.activeAnalysisID == analysisID else { return }
                self?.analysisState = .processing(progress: progress)
            }
        }
        let finish: @Sendable ([ShotAnalysisReport]) -> Void = { [weak self] reports in
            Task { @MainActor [weak self] in
                guard self?.activeAnalysisID == analysisID else { return }
                self?.reports = reports
                self?.selectedReportIndex = 0
                self?.analysisState = .completed
            }
        }
        let fail: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor [weak self] in
                guard self?.activeAnalysisID == analysisID else { return }
                self?.analysisState = .failed(message: message)
            }
        }

        Task.detached(priority: .userInitiated) {
            do {
                let reports = try await ShotAnalysisService().analyze(input: input, progress: updateProgress)
                finish(reports)
            } catch is CancellationError {
                // A new video or analysis superseded this run.
            } catch {
                fail(error.localizedDescription)
            }
        }
    }
}
