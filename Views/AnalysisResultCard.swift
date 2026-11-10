import SwiftUI

struct AnalysisResultCard: View {
    let report: ShotAnalysisReport

    /// 목표에 가까울수록 1에 가까워요 (차이 15°면 0)
    private var closeness: Double {
        max(0, 1 - abs(report.difference) / 15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HUDHeader(title: "SHOT RESULT")

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.feedback.title)
                        .font(HUD.font(24))
                        .foregroundStyle(Color.white)
                    Text(report.feedback.detail)
                        .font(.footnote)
                        .foregroundStyle(HUD.dim)
                }
                Spacer(minLength: 0)
                RingGauge(
                    progress: closeness,
                    label: String(format: "%.0f°", abs(report.difference)),
                    color: toneColor
                )
                .frame(width: 64, height: 64)
            }

            DottedLine()

            HStack(alignment: .bottom, spacing: 18) {
                BigMetric(title: "YOU", value: report.measuredEntryAngle, color: HUD.orange, big: true)
                BigMetric(
                    title: report.dynamicTargetAvailable ? "TARGET" : "DEFAULT",
                    value: report.targetEntryAngle,
                    color: HUD.gold,
                    big: false
                )
                BigMetric(title: "DIFF", value: abs(report.difference), color: Color.white.opacity(0.7), big: false)
            }

            DottedLine()

            if let estimate = report.physicalEstimate {
                Text("ESTIMATES · 영상 보정 추정치")
                    .font(HUD.font(11, .semibold))
                    .foregroundStyle(HUD.gold)
                HStack {
                    PhysicsMetric(title: "DISTANCE", value: estimate.shotDistanceMeters, unit: "m")
                    Spacer()
                    PhysicsMetric(title: "RELEASE", value: estimate.releaseHeightMeters, unit: "m")
                    Spacer()
                    PhysicsMetric(title: "SPEED", value: estimate.horizontalSpeedMetersPerSecond, unit: "m/s")
                }
                if estimate.usedWristCorrection {
                    Label("손목 포즈로 릴리즈 높이를 보정했습니다", systemImage: "figure.basketball")
                        .font(.caption)
                        .foregroundStyle(HUD.dim)
                }
            } else {
                Label("영상 원근 또는 림 폭 보정이 부족해 45° 기본 목표각을 사용했습니다.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(HUD.dim)
            }
        }
        .hudPanel(tint: HUD.orange)
    }

    private var toneColor: Color {
        switch report.feedback {
        case .perfect: HUD.cyan
        case .flat: HUD.orange
        case .steep: HUD.gold
        }
    }
}

private struct BigMetric: View {
    let title: String
    let value: Double
    let color: Color
    let big: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(HUD.font(11, .semibold))
                .foregroundStyle(color == HUD.orange ? HUD.orange : HUD.dim)
            Text("\(value, specifier: "%.1f")°")
                .font(HUD.font(big ? 44 : 28).monospacedDigit())
                .foregroundStyle(color)
        }
    }
}

private struct PhysicsMetric: View {
    let title: String
    let value: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(HUD.font(10, .semibold))
                .foregroundStyle(HUD.dim)
            Text("\(value, specifier: "%.2f") \(unit)")
                .font(HUD.font(16).monospacedDigit())
                .foregroundStyle(Color.white)
        }
    }
}
