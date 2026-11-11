import SwiftUI
import Charts

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [ShotSession] = SessionStore.load()

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
                                    Text("슛 \(session.shots.count)개 · 평균 \(session.averageAngle.map { String(format: "%.1f°", $0) } ?? "–") · 안정적 \(Int(session.perfectRate * 100))%")
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

    var body: some View {
        List {
            Section("요약") {
                row("촬영 시작", session.startedAt.formatted(date: .abbreviated, time: .shortened))
                row("슛 개수", "\(session.shots.count)개")
                row("평균 입사각", session.averageAngle.map { String(format: "%.1f°", $0) } ?? "–")
                row("편차", session.spread.map { String(format: "±%.1f°", $0) } ?? "–")
                row("안정적인 슛", "\(Int(session.perfectRate * 100))%")
                row("보정", session.calibrated ? "적용됨" : "없음")
                row("촬영 방향", session.landscape ? "가로" : "세로")
            }

            Section("입사각 추이") {
                Chart(Array(session.shots.enumerated()), id: \.element.id) { index, shot in
                    LineMark(x: .value("슛", index + 1), y: .value("각도", shot.measuredAngle))
                        .foregroundStyle(HUD.gold)
                    PointMark(x: .value("슛", index + 1), y: .value("각도", shot.measuredAngle))
                        .foregroundStyle(HUD.orange)
                }
                .chartYScale(domain: 25...70)
                .frame(height: 160)
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
                        Text("목표 " + String(format: "%.1f°", shot.targetAngle))
                            .font(.caption)
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
