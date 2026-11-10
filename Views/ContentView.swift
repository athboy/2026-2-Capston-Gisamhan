import SwiftUI

struct ContentView: View {
    @State private var showLive = false
    @State private var showHistory = false
    @State private var showSettings = false

    var body: some View {
        homeScreen
            .background(HUD.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .tint(HUD.orange)
            .fullScreenCover(isPresented: $showLive) {
                LiveCameraView()
            }
            .sheet(isPresented: $showHistory) { HistoryView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var homeScreen: some View {
        VStack(spacing: 18) {
            Spacer()

            Text("SHOT ARC")
                .font(HUD.font(64))
                .foregroundStyle(Color.white)
            Text("BASKETBALL ENTRY ANGLE ANALYZER")
                .font(HUD.font(12, .semibold))
                .foregroundStyle(HUD.gold)

            DottedLine()
                .padding(.vertical, 6)

            Text("슛 아크 분석")
                .font(HUD.font(22))
                .foregroundStyle(HUD.orange)
            Text("카메라로 슈팅을 실시간 분석해 입사각과\n개인화된 목표 아크를 확인하세요.")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundStyle(HUD.dim)

            // ⭐ 수정: 누르면 먼저 화면을 가로로 돌리고, 그다음 카메라 화면을 열어요
            Button {
                OrientationController.request(landscape: true)
                showLive = true
            } label: {
                Label("실시간 카메라 분석", systemImage: "camera.viewfinder")
                    .font(HUD.font(18))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: 320, minHeight: 56)
                    .background(HUD.orange)
            }

            HStack(spacing: 12) {
                Button {
                    showHistory = true
                } label: {
                    Label("슛 기록", systemImage: "chart.line.uptrend.xyaxis")
                        .font(HUD.font(16))
                        .foregroundStyle(HUD.gold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(Rectangle().stroke(HUD.gold, lineWidth: 1.5))
                }
                Button {
                    showSettings = true
                } label: {
                    Label("튜닝 설정", systemImage: "slider.horizontal.3")
                        .font(HUD.font(16))
                        .foregroundStyle(HUD.gold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(Rectangle().stroke(HUD.gold, lineWidth: 1.5))
                }
            }
            .frame(maxWidth: 320)

            Spacer()
            Text("iOS 18 이상 · 모든 분석은 기기에서 처리됩니다")
                .font(HUD.font(12, .semibold))
                .foregroundStyle(HUD.dim)
                .padding(.bottom)
        }
        .padding(24)
        .overlay(
            CornerBrackets(length: 28)
                .stroke(HUD.gold.opacity(0.7), lineWidth: 1.5)
                .padding(14)
                .allowsHitTesting(false)
        )
    }
}
