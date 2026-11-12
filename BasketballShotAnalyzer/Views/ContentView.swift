import SwiftUI

struct ContentView: View {
    @State private var showLive = false
    @State private var showHistory = false
    @State private var showSettings = false

    var body: some View {
        homeScreen
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HUD.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .tint(HUD.orange)
            .onAppear {
                OrientationController.request(landscape: true)
            }
            .onChange(of: showLive) { _, isPresented in
                if !isPresented {
                    // 카메라 분석 화면을 닫고 나왔을 때도 가로 모드 재차 고정
                    OrientationController.request(landscape: true)
                }
            }
            .fullScreenCover(isPresented: $showLive) {
                LiveCameraView()
            }
            .sheet(isPresented: $showHistory) { HistoryView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var homeScreen: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 40) {
                brandingSection
                    .frame(maxWidth: .infinity, alignment: .leading)
                actionButtonsSection
                    .frame(width: min(320, geo.size.width * 0.42))
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 24)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var brandingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ON-DEVICE AI ANALYZER")
                .font(HUD.font(12, .heavy))
                .tracking(1.5)
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(HUD.gold)
                .clipShape(Capsule())

            Text("SHOT ARC")
                .font(HUD.font(60, .black))
                .tracking(-1)
                .foregroundStyle(Color.white)

            Text("카메라로 슈팅 궤적을 실시간 추적하여\n입사각과 목표 아크 일관성을 분석합니다.")
                .font(.subheadline)
                .foregroundStyle(HUD.dim)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Image(systemName: "cpu")
                Text("iOS 18+ · 모든 분석은 기기 내부에서 실시간 처리됩니다")
            }
            .font(HUD.font(12, .semibold))
            .foregroundStyle(HUD.dim.opacity(0.8))
        }
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button {
                OrientationController.request(landscape: true)
                showLive = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 20, weight: .bold))
                    Text("실시간 카메라 분석")
                        .font(HUD.font(19, .heavy))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(HUD.orange)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: HUD.orange.opacity(0.35), radius: 12, y: 4)
            }

            HStack(spacing: 10) {
                Button {
                    showHistory = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                        Text("슛 기록")
                    }
                    .font(HUD.font(16, .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                }

                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                        Text("튜닝 설정")
                    }
                    .font(HUD.font(16, .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                }
            }
        }
    }
}
