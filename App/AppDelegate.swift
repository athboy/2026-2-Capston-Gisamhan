import UIKit

/// 화면 방향을 정하고 바꾸는 담당
@MainActor
enum OrientationController {
    /// 지금 허용할 방향 (AppDelegate가 이 값을 읽어요)
    static var mask: UIInterfaceOrientationMask = .portrait

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    }

    /// 지금 화면이 실제로 어느 방향인지 읽기
    static func current() -> ScreenOrientation {
        guard let orientation = scene?.interfaceOrientation else { return .portrait }
        switch orientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }

    /// 가로(true) 또는 세로(false)로 돌려 달라고 요청하기
    static func request(landscape: Bool) {
        mask = landscape ? .landscape : .portrait
        guard let scene else { return }

        // 지금 맨 위에 떠 있는 화면(실시간 카메라 화면)에게 "허용 방향이 바뀌었어요"라고 알림
        var top = scene.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.setNeedsUpdateOfSupportedInterfaceOrientations()

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationController.mask
    }
}
