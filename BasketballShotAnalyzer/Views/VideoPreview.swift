import AVKit
import SwiftUI

struct VideoPreview: View {
    let player: AVPlayer
    let videoSize: CGSize
    @Binding var rim: RimCalibration?
    let path: TrajectoryPath?
    @Binding var isSelectingRim: Bool

    @State private var startRimCenter: NormalizedPoint?
    @State private var startRimWidth: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let fittedRect = VideoLayout.fittedRect(in: proxy.size, videoSize: videoSize)
            ZStack {
                Color.black

                VideoPlayer(player: player)
                    .frame(width: fittedRect.width, height: fittedRect.height)
                    .position(x: fittedRect.midX, y: fittedRect.midY)
                    .allowsHitTesting(!isSelectingRim)

                if let path {
                    TrajectoryOverlay(path: path, videoRect: fittedRect)
                }

                if let rim {
                    RimOverlay(rim: rim, videoRect: fittedRect)
                }

                if isSelectingRim {
                    Color.black.opacity(0.2)
                        .allowsHitTesting(false)
                        
                    Color.white.opacity(0.001)
                        .gesture(
                            SimultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if startRimCenter == nil { startRimCenter = rim?.center }
                                        guard let startCenter = startRimCenter else { return }
                                        let dx = value.translation.width / fittedRect.width
                                        let dy = -value.translation.height / fittedRect.height
                                        if var currentRim = rim {
                                            currentRim.center = .clamped(x: startCenter.x + dx, y: startCenter.y + dy)
                                            rim = currentRim
                                        }
                                    }
                                    .onEnded { _ in startRimCenter = nil },
                                MagnificationGesture()
                                    .onChanged { value in
                                        if startRimWidth == nil { startRimWidth = rim?.widthFraction }
                                        guard let startWidth = startRimWidth else { return }
                                        if var currentRim = rim {
                                            currentRim.widthFraction = min(max(startWidth * value, 0.02), 0.3)
                                            rim = currentRim
                                        }
                                    }
                                    .onEnded { _ in startRimWidth = nil }
                            )
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard isSelectingRim, fittedRect.contains(location) else { return }
                let x = (location.x - fittedRect.minX) / fittedRect.width
                let y = 1 - (location.y - fittedRect.minY) / fittedRect.height
                if var currentRim = rim {
                    currentRim.center = .clamped(x: x, y: y)
                    rim = currentRim
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isSelectingRim {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "hand.draw")
                            Text("림 위치 지정")
                                .font(.headline)
                        }
                        Text("화면을 탭하여 림을 즉시 이동하거나\n한 손가락 드래그, 두 손가락 확대로 미세조정하세요.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(12)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .padding(16)
                    .allowsHitTesting(false)
                }
            }
        }
        .background(Color.black)
    }
}

private struct RimOverlay: View {
    let rim: RimCalibration
    let videoRect: CGRect

    var body: some View {
        Capsule()
            .stroke(.cyan, style: StrokeStyle(lineWidth: 3, dash: [7, 4]))
            .frame(width: videoRect.width * rim.widthFraction, height: 13)
            .position(
                x: videoRect.minX + videoRect.width * rim.center.x,
                y: videoRect.minY + videoRect.height * (1 - rim.center.y)
            )
            .shadow(color: .cyan.opacity(0.8), radius: 5)
    }
}

private struct TrajectoryOverlay: View {
    let path: TrajectoryPath
    let videoRect: CGRect

    var body: some View {
        Path { drawing in
            guard let first = path.points.first else { return }
            drawing.move(to: displayPoint(for: first))
            for point in path.points.dropFirst() {
                drawing.addLine(to: displayPoint(for: point))
            }
        }
        .stroke(.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .shadow(color: .orange.opacity(0.8), radius: 4)
    }

    private func displayPoint(for point: NormalizedPoint) -> CGPoint {
        CGPoint(
            x: videoRect.minX + point.x * videoRect.width,
            y: videoRect.minY + (1 - point.y) * videoRect.height
        )
    }
}
