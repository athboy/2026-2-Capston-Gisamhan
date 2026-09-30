import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ShotAnalysisViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var isSelectingRim = false

    var body: some View {
        Group {
            if let player = viewModel.player, let video = viewModel.video {
                analysisScreen(player: player, video: video)
            } else {
                importScreen
            }
        }
        .tint(.orange)
    }

    private var importScreen: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "basketball.fill")
                .font(.system(size: 58))
                .foregroundStyle(.orange)
            Text("슛 아크 분석")
                .font(.largeTitle.bold())
            Text("촬영한 슈팅 영상을 분석해 입사각과\n개인화된 목표 아크를 확인하세요.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            PhotosPicker(selection: $selectedItem, matching: .videos) {
                Label("앨범에서 영상 선택", systemImage: "video.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(.orange, in: Capsule())
                    .foregroundStyle(.white)
            }
            if case .loadingVideo = viewModel.analysisState {
                ProgressView("영상 준비 중")
            }
            if case let .failed(message) = viewModel.analysisState {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
            Text("iOS 18 이상 · 모든 분석은 기기에서 처리됩니다")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom)
        }
        .padding()
        .onChange(of: selectedItem) { _, newItem in
            Task { await viewModel.load(item: newItem) }
        }
    }

    private func analysisScreen(player: AVPlayer, video: VideoAssetInfo) -> some View {
        VStack(spacing: 0) {
            VideoPreview(
                player: player,
                videoSize: video.displaySize,
                rim: $viewModel.rim,
                path: viewModel.selectedReport?.path,
                isSelectingRim: $isSelectingRim
            )
            .aspectRatio(video.displaySize, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if let stateLabel = stateLabel {
                    Text(stateLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.65), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(12)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !viewModel.reports.isEmpty {
                        if viewModel.reports.count > 1 {
                            Picker("슛 선택", selection: $viewModel.selectedReportIndex) {
                                ForEach(0..<viewModel.reports.count, id: \.self) { index in
                                    Text("\(index + 1)번째 슛").tag(index)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.bottom, 4)
                        }
                        
                        if let report = viewModel.selectedReport {
                            AnalysisResultCard(report: report)
                        }
                    } else {
                        calibrationCard
                    }

                    if case let .processing(progress) = viewModel.analysisState {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("영상 분석 중")
                                    .font(.headline)
                                Spacer()
                                Text("\(Int(progress * 100))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: progress)
                        }
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }

                    if case let .failed(message) = viewModel.analysisState {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(14)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }

                    Text("동적 목표각은 선택한 림 폭(정식 45cm)을 영상의 기준 척도로 사용하고, 포즈 추정 손목 좌표로 릴리즈 높이를 보정한 2D 근사치입니다. 촬영 각도와 원근이 클수록 수치 오차가 커질 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            controlBar(player: player)
        }
        .onChange(of: selectedItem) { _, newItem in
            Task { await viewModel.load(item: newItem) }
        }
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: viewModel.rim == nil ? "1.circle.fill" : "2.circle.fill")
                    .foregroundStyle(.orange)
                Text(viewModel.rim == nil ? "림 위치를 지정하세요" : "림 폭을 영상에 맞추세요")
                    .font(.headline)
            }
            Text(viewModel.rim == nil
                 ? "영상 위의 ‘림 지정’을 누른 뒤 림의 중앙을 탭하세요."
                 : "청록색 표시가 림의 실제 지름과 같도록 조절하면 거리·릴리즈 높이 추정이 더 정확해집니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.rim != nil {
                HStack {
                    Text("림 폭")
                        .font(.subheadline.weight(.medium))
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.rimWidthFraction) },
                            set: { viewModel.rimWidthFraction = CGFloat($0) }
                        ),
                        in: 0.02...0.20
                    )
                    Text("\(Int(viewModel.rimWidthFraction * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func controlBar(player: AVPlayer) -> some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $selectedItem, matching: .videos) {
                Image(systemName: "photo.on.rectangle")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)

            Button {
                isSelectingRim.toggle()
                viewModel.resetAnalysis()
                if isSelectingRim {
                    if viewModel.rim == nil {
                        viewModel.setRimCenter(.init(x: 0.5, y: 0.5))
                    }
                    player.pause()
                } else {
                    player.play()
                }
            } label: {
                Label(isSelectingRim ? "완료" : "림 지정", systemImage: isSelectingRim ? "checkmark" : "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.analyze()
            } label: {
                Label("분석", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.rim == nil || viewModel.analysisState.isProcessing)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var stateLabel: String? {
        if isSelectingRim { return nil }
        switch viewModel.analysisState {
        case .ready: return viewModel.rim == nil ? "림 위치 지정 대기" : "분석 준비 완료"
        case .completed: return "분석 완료"
        case .processing: return "프레임 분석 중"
        default: return nil
        }
    }
}
