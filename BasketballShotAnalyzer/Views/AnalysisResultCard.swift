import SwiftUI

struct AnalysisResultCard: View {
    let report: ShotAnalysisReport

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(report.feedback.title)
                        .font(.title3.bold())
                    Text(report.feedback.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: report.isPerfect ? "checkmark.seal.fill" : "basketball.fill")
                    .font(.title2)
                    .foregroundStyle(toneColor)
            }

            HStack(spacing: 10) {
                AngleMetric(title: "측정 입사각", value: report.measuredEntryAngle, emphasized: true)
                AngleMetric(title: report.dynamicTargetAvailable ? "동적 목표각" : "기본 목표각", value: report.targetEntryAngle, emphasized: false)
                AngleMetric(title: "차이", value: abs(report.difference), suffix: "°", emphasized: false)
            }

            if let estimate = report.physicalEstimate {
                Divider()
                Text("영상 보정 추정치")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    PhysicsMetric(title: "슛 거리", value: estimate.shotDistanceMeters, unit: "m")
                    Spacer()
                    PhysicsMetric(title: "릴리즈 높이", value: estimate.releaseHeightMeters, unit: "m")
                    Spacer()
                    PhysicsMetric(title: "수평 속도", value: estimate.horizontalSpeedMetersPerSecond, unit: "m/s")
                }
                if estimate.usedWristCorrection {
                    Label("손목 포즈로 릴리즈 높이를 보정했습니다", systemImage: "figure.basketball")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Divider()
                Label("영상 원근 또는 림 폭 보정이 부족해 45° 기본 목표각을 사용했습니다.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var toneColor: Color {
        switch report.feedback {
        case .perfect: .green
        case .flat: .orange
        case .steep: .purple
        }
    }
}

private struct AngleMetric: View {
    let title: String
    let value: Double
    var suffix = "°"
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value, specifier: "%.1f")\(suffix)")
                .font(emphasized ? .title2.bold() : .headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PhysicsMetric: View {
    let title: String
    let value: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value, specifier: "%.2f") \(unit)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }
}
