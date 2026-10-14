import SwiftUI

@main
struct BasketballShotAnalyzerApp: App {
    var body: some Scene {
        WindowGroup {
            LiveCameraView()
                .statusBarHidden(true) // 앱 전체 상태 표시줄 숨김
        }
    }
}
