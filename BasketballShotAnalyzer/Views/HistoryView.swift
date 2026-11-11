import SwiftUI
import Charts

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [ShotSession] = SessionStore.load()

    private func summary(_ session: ShotSession) -> String {
        var text = "슛 \(session.shots.count)개"
        if session.hasMadeData { text += " · 골 \(session.madeCount)" }
        text += " · 평균 \(session.averageAngle.map { String(format: "%.1f°", $0) } ?? "–")"
        text += " · 적중 \(Int(session.perfectRate * 100))%"
        return text
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundStyle(HUD.dim)
                        Text("저장된 기록이 없어요")
                            .font(HUD.font(18))
                        Text("실시간 카메라로 슛을 쏘면 자동으로 저장돼요.")
                            .font(.footnote)
                            .foregroundStyle(HUD.dim)
                    }
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(HUD.font(16))
                                    Text(summary(session))
                                        .font(.caption)
                                        .foregroundStyle(HUD.dim)
                                }
                            }
                        }
                        .onDelete { offsets in
                            SessionStore.delete(ids: offsets.map { sessions[$0].id })
                            sessions.remove(atOffsets: offsets)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HUD.background.ignoresSafeArea())
            .navigationTitle("슛 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .onAppear { sessions = SessionStore.load() }
        }
        .preferredColorScheme(.dark)
        .tint(HUD.orange)
    }
}

struct SessionDetailView: View {
    let session: ShotSession

    // ⭐ 입사각 추이: 골 = 파랑, 노골 = 빨강, 판정 없음 = 회색, 점선 = 목표 45°
    private var trendChart: some View {
        Chart {
            RuleMark(y: .value("목표", ShotTarget.angle))
                .foregroundStyle(HUD.cyan.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(Array(session.shots.enumerated()), id: \.element.id) { index, shot in
                LineMark(x: .value("슛", index + 1), y: .value("각도", shot.measuredAngle))
                    .foregroundStyle(HUD.gold)
                PointMark(x: .value("슛", index + 1), y: .value("각도", shot.measuredAngle))
                    .foregroundStyle(ShotColor.color(for: shot.made))
                    .symbolSize(90)
            }
        }
        .chartYScale(domain: 25...70)
        .frame(height: 180)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.caption)
        }
    }

    private func resultText(_ shot: ShotRecord) -> String {
        switch shot.made {
        case .some(true): return "골"
        case .some(false): return "노골"
        case .none: return "–"
        }
    }

    var body: some View {
        List {
            Section("요약") {
                row("촬영 시작", session.startedAt.formatted(date: .abbreviated, time: .shortened))
                row("슛 개수", "\(session.shots.count)개")
                row("골", session.hasMadeData
                    ? "\(session.madeCount)개 (\(Int(session.madeRate * 100))%)"
                    : "판정 없음")
                row("평균 입사각", session.averageAngle.map { String(format: "%.1f°", $0) } ?? "–")
                row("편차", session.spread.map { String(format: "±%.1f°", $0) } ?? "–")
                row("목표", "45° ± 2°")
                row("목표 적중 (±2°)", "\(Int(session.perfectRate * 100))%")
                row("보정", session.calibrated ? "적용됨" : "없음")
                row("촬영 방향", session.landscape ? "가로" : "세로")
            }

            Section("입사각 추이") {
                VStack(alignment: .leading, spacing: 8) {
                    trendChart
                    HStack(spacing: 14) {
                        legendDot(ShotColor.made, "골")
                        legendDot(ShotColor.miss, "노골")
                        legendDot(ShotColor.unknown, "판정 없음")
                        Spacer()
                        Text("점선 = 목표 45°")
                            .font(.caption)
                            .foregroundStyle(HUD.cyan)
                    }
                }
            }

            Section("슛 목록") {
                ForEach(Array(session.shots.enumerated()), id: \.element.id) { index, shot in
                    HStack {
                        Text("\(index + 1)번")
                            .font(HUD.font(15))
                            .frame(width: 44, alignment: .leading)
                        Text(String(format: "%.1f°", shot.measuredAngle))
                            .font(HUD.font(18).monospacedDigit())
                            .foregroundStyle(HUD.orange)
                        Spacer()
                        Text(resultText(shot))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ShotColor.color(for: shot.made))
                            .frame(width: 40)
                        Text(String(format: "%+.1f°", shot.diffFromTarget))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(HUD.gold)
                        Text(shot.feedbackTitle)
                            .font(.caption.weight(.semibold))
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HUD.background.ignoresSafeArea())
        .navigationTitle("기록 상세")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: SessionStore.csv(for: session),
                    subject: Text("슛 기록 CSV")
                ) {
                    Label("내보내기", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(HUD.dim)
            Spacer()
            Text(value).font(HUD.font(16).monospacedDigit())
        }
    }
}
