import CoreGraphics

/// 앱 화면이 지금 어느 방향인지
enum ScreenOrientation: Equatable, Sendable {
    case portrait         // 세로
    case landscapeLeft    // 가로 (홈 표시줄이 왼쪽)
    case landscapeRight   // 가로 (홈 표시줄이 오른쪽)

    var isLandscape: Bool { self != .portrait }

    /// 카메라 영상을 똑바로 세우려면 돌려야 하는 각도
    /// (세로 = 90도, 가로 = 0도 또는 180도)
    var captureAngle: CGFloat {
        switch self {
        case .portrait: 90
        case .landscapeRight: 0
        case .landscapeLeft: 180
        }
    }

    /// 영상 한 장의 (세로 길이 ÷ 가로 길이)
    /// 세로 영상 1080x1920 → 1.78, 가로 영상 1920x1080 → 0.5625
    var frameRatio: CGFloat {
        isLandscape ? 1080.0 / 1920.0 : 1920.0 / 1080.0
    }

    /// "림 폭"은 화면 가로폭 대비 비율이에요.
    /// 가로로 찍으면 화면 가로폭이 더 길어서 같은 림이 더 작은 비율로 보여요.
    /// 세로 기준 숫자에 이 값을 곱하면 가로 기준 숫자가 돼요.
    var widthScale: CGFloat {
        isLandscape ? 1080.0 / 1920.0 : 1.0
    }
}
