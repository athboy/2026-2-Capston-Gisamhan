import CoreGraphics
import Foundation
import AVFoundation

struct VideoAnalysisInput: Sendable {
    let video: VideoAssetInfo
    let rim: RimCalibration
}

final class ShotAnalysisService {
    typealias ProgressHandler = @Sendable (Double) -> Void

    func analyze(input: VideoAnalysisInput, progress: @escaping ProgressHandler) async throws -> [ShotAnalysisReport] {
        progress(0.1)
        
        let analyzer = ShotTrajectoryAnalyzer()
        let asset = AVURLAsset(url: input.video.url)
        
        let trajectories = try await analyzer.analyzeVideo(asset: asset)
        if trajectories.isEmpty {
            throw ShotAnalysisError.noTrajectory
        }
        progress(0.9)
        
        // 1. 유효한(점수가 낮은) 궤적 후보들만 먼저 걸러냅니다. (노이즈 제거)
        var validCandidates: [EntryCandidate] = []
        for trajectory in trajectories {
            if let candidate = entryCandidate(from: trajectory, rim: input.rim, heightToWidthRatio: input.video.heightToWidthRatio) {
                // 패널티를 너무 많이 받은 노이즈는 제외
                if candidate.score < 15 {
                    validCandidates.append(candidate)
                }
            }
        }
        
        // 2. 유효한 후보들을 시간순 정렬
        validCandidates.sort { $0.snapshot.timestamp.seconds < $1.snapshot.timestamp.seconds }
        
        // 3. 시간 간격을 기준으로 슛(Attempt) 그룹 분리
        var clusters: [[EntryCandidate]] = []
        var currentCluster: [EntryCandidate] = []
        
        for candidate in validCandidates {
            if let last = currentCluster.last {
                // 유효한 궤적들 사이에 2.0초 이상의 공백이 있다면 서로 다른 슛으로 간주
                if candidate.snapshot.timestamp.seconds - last.snapshot.timestamp.seconds > 2.0 {
                    clusters.append(currentCluster)
                    currentCluster = []
                }
            }
            currentCluster.append(candidate)
        }
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }
        
        var reports: [ShotAnalysisReport] = []
        
        // 4. 각 슛 그룹에서 가장 완벽한(점수가 가장 낮은) 궤적 하나씩만 뽑아서 리포트 생성
        for cluster in clusters {
            guard let bestCandidate = cluster.min(by: { $0.score < $1.score }) else { continue }
            
            guard let measuredEntryAngle = ShotPhysics.entryAngle(
                a: bestCandidate.snapshot.a,
                b: bestCandidate.snapshot.b,
                rimX: input.rim.center.x,
                heightToWidthRatio: input.video.heightToWidthRatio
            ) else { continue }

            let releasePoint = bestCandidate.snapshot.wrist
                ?? bestCandidate.snapshot.detectedPoints.first
                ?? bestCandidate.snapshot.projectedPoints.first
                ?? input.rim.center
                
            let a = bestCandidate.snapshot.a
            let b = bestCandidate.snapshot.b
            let c = bestCandidate.snapshot.c
            
            var releaseX = releasePoint.x
            let rimX = input.rim.center.x
            
            if releasePoint.y > 0.4 {
                let targetY: CGFloat = 0.35
                let c2 = c - targetY
                let discriminant = b * b - 4 * a * c2
                if discriminant >= 0 {
                    let x1 = (-b + sqrt(discriminant)) / (2 * a)
                    let x2 = (-b - sqrt(discriminant)) / (2 * a)
                    releaseX = abs(x1 - rimX) > abs(x2 - rimX) ? x1 : x2
                }
            }
            
            let startX = min(releaseX, rimX)
            let endX = max(releaseX, rimX)
            let steps = 40
            let stepSize = (endX - startX) / CGFloat(steps)
            
            var fullParabola: [NormalizedPoint] = []
            if releaseX < rimX {
                for i in 0...steps {
                    let x = startX + stepSize * CGFloat(i)
                    fullParabola.append(NormalizedPoint(x: x, y: a * x * x + b * x + c))
                }
            } else {
                for i in 0...steps {
                    let x = endX - stepSize * CGFloat(i)
                    fullParabola.append(NormalizedPoint(x: x, y: a * x * x + b * x + c))
                }
            }
            
            let physicalEstimate = ShotPhysics.dynamicEstimate(
                a: a,
                b: b,
                releasePoint: NormalizedPoint(x: releaseX, y: a * releaseX * releaseX + b * releaseX + c),
                wrist: nil,
                rim: input.rim,
                heightToWidthRatio: input.video.heightToWidthRatio
            )
            
            let targetAngle = physicalEstimate?.targetEntryAngle ?? ShotPhysics.standardTargetAngle
            let difference = measuredEntryAngle - targetAngle
            
            let feedback: FeedbackTone
            if abs(difference) <= 2 {
                feedback = .perfect
            } else if difference < 0 {
                feedback = .flat
            } else {
                feedback = .steep
            }
            
            reports.append(ShotAnalysisReport(
                measuredEntryAngle: measuredEntryAngle,
                targetEntryAngle: targetAngle,
                difference: difference,
                feedback: feedback,
                path: TrajectoryPath(points: fullParabola),
                confidence: min(max(Double(bestCandidate.snapshot.confidence), 0), 1),
                physicalEstimate: physicalEstimate,
                dynamicTargetAvailable: physicalEstimate != nil
            ))
        }
        
        progress(1.0)
        
        if reports.isEmpty {
            throw ShotAnalysisError.rimNotReached
        }
        
        return reports
    }

    private func entryCandidate(
        from trajectory: TrajectorySnapshot,
        rim: RimCalibration,
        heightToWidthRatio: CGFloat
    ) -> EntryCandidate? {
        let points = trajectory.projectedPoints.isEmpty ? trajectory.detectedPoints : trajectory.projectedPoints
        guard points.count >= 3 else { return nil }

        let rimX = rim.center.x
        let derivative = 2 * trajectory.a * rimX + trajectory.b
        
        let xRange = points.map(\.x)
        let minX = xRange.min() ?? 0
        let maxX = xRange.max() ?? 1
        let xSpan = maxX - minX
        
        let predictedY = trajectory.a * rimX * rimX + trajectory.b * rimX + trajectory.c
        let verticalError = abs(predictedY - rim.center.y)
        let horizontalError = points.map { abs($0.x - rimX) }.min() ?? 1

        // 기존의 엄격한 guard 문들을 모두 Penalty 점수제로 변환하여, 가장 나은 궤적을 무조건 화면에 그리도록 함 (시각적 디버깅 목적 포함)
        var penalty: CGFloat = 0
        
        // 1. 포물선은 아래로 굽어야 함 (a < 0)
        if trajectory.a >= -0.001 { penalty += 10.0 }
        
        // 2. 림 통과 시 떨어지는 각도가 있어야 함
        if abs(derivative) <= 0.01 { penalty += 5.0 }
        
        // 3. 제자리 노이즈(짧은 선) 배제
        if xSpan <= 0.10 { penalty += 10.0 }
        
        // 4. 림 근처까지 와야 함
        let tolerance: CGFloat = 0.20
        if rimX < minX - tolerance || rimX > maxX + tolerance { penalty += 5.0 }
        
        // 5. 림 높이와 너무 차이나면 안 됨
        if verticalError > 0.20 { penalty += 5.0 }

        let lengthPenalty = max(0, 0.5 - xSpan)
        let confidencePenalty = 1 - CGFloat(trajectory.confidence)
        let slopePenalty = max(0, 0.05 - abs(derivative))
        
        let score = horizontalError + verticalError * 2.0 + confidencePenalty * 0.15 + slopePenalty + lengthPenalty + penalty
        return EntryCandidate(snapshot: trajectory, score: score)
    }
}

private struct EntryCandidate {
    let snapshot: TrajectorySnapshot
    let score: CGFloat
}
