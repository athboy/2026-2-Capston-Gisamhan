import SwiftUI

@main
struct BasketballShotAnalyzerApp: App {
    // ⭐ 추가: 화면 방향을 조절하는 AppDelegate 연결
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
