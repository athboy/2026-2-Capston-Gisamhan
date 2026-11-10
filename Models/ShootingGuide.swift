import CoreGraphics

/// 검사 항목 하나 (예: "림 위치 ✅")
struct GuideCheck: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let passed: Bool
    let hint: String
}

enum ShootingGuide {
    // MARK: - 기준값 (세로 기준. 필요하면 여기 숫자를 바꾸세요)

    static let targetY: CGFloat = 0.70
    static let targetXRight: CGFloat = 0.80
    static let targetXLeft: CGFloat = 0.20

    static let toleranceX: CGFloat = 0.10
    static let toleranceY: CGFloat = 0.06

    static let widthRange: ClosedRange<CGFloat> = 0.05...0.11

    static let maxRoll: Double = 3
    static let pitchRange: ClosedRange<Double> = -5...10

    // MARK: - ⭐ 추가: 방향(세로/가로)에 맞춘 값

    /// 점선 박스의 가로 반폭 (화면 가로폭 비율)
    /// 가로 화면은 폭이 더 넓으니 비율을 줄여서 실제 크기를 비슷하게 맞춰요
    static func boxHalfWidth(_ o: ScreenOrientation) -> CGFloat {
        toleranceX * o.widthScale
    }

    /// 점선 박스의 세로 반높이 (화면 세로 길이 비율)
    static func boxHalfHeight(_ o: ScreenOrientation) -> CGFloat {
        o.isLandscape ? toleranceY / o.widthScale : toleranceY
    }

    /// 림 폭 허용 범위
    static func allowedWidthRange(_ o: ScreenOrientation) -> ClosedRange<CGFloat> {
        (widthRange.lowerBound * o.widthScale)...(widthRange.upperBound * o.widthScale)
    }

    static func targetCenter(rimOnRight: Bool) -> NormalizedPoint {
        NormalizedPoint(x: rimOnRight ? targetXRight : targetXLeft, y: targetY)
    }

    // MARK: - 5가지 검사

    static func evaluate(
        rim: RimCalibration?,
        pitch: Double,
        roll: Double,
        rimOnRight: Bool,
        orientation: ScreenOrientation   // ⭐ 추가
    ) -> [GuideCheck] {
        let target = targetCenter(rimOnRight: rimOnRight)
        let halfW = boxHalfWidth(orientation)
        let halfH = boxHalfHeight(orientation)
        let sizeRange = allowedWidthRange(orientation)

        var positionPassed = false
        var positionHint = "먼저 림을 인식시켜 주세요."
        var sizePassed = false
        var sizeHint = "먼저 림을 인식시켜 주세요."

        if let rim {
            let dx = rim.center.x - target.x
            let dy = rim.center.y - target.y
            positionPassed = abs(dx) <= halfW && abs(dy) <= halfH
            if positionPassed {
                positionHint = ""
            } else if abs(dx) / halfW >= abs(dy) / halfH {
                positionHint = dx < 0
                    ? "림이 박스보다 왼쪽에 있어요. 폰을 왼쪽으로 살짝 돌려 주세요."
                    : "림이 박스보다 오른쪽에 있어요. 폰을 오른쪽으로 살짝 돌려 주세요."
            } else {
                positionHint = dy > 0
                    ? "림이 박스보다 위에 있어요. 폰을 위로 살짝 들어 올려 주세요."
                    : "림이 박스보다 아래에 있어요. 폰을 아래로 살짝 내려 주세요."
            }

            sizePassed = sizeRange.contains(rim.widthFraction)
            if sizePassed {
                sizeHint = ""
            } else if rim.widthFraction < sizeRange.lowerBound {
                sizeHint = "림이 너무 작아요. 골대 쪽으로 조금 가까이 가 주세요."
            } else {
                sizeHint = "림이 너무 커요. 골대에서 조금 뒤로 물러나 주세요."
            }
        }

        let rollPassed = abs(roll) <= maxRoll
        let pitchPassed = pitchRange.contains(pitch)

        return [
            GuideCheck(
                id: "rim", title: "림 인식", passed: rim != nil,
                hint: "림이 없어요. 오른쪽 위 손가락 버튼을 누르고 림을 탭해 주세요."
            ),
            GuideCheck(id: "position", title: "림 위치 (점선 박스)", passed: positionPassed, hint: positionHint),
            GuideCheck(id: "size", title: "림 크기 (거리)", passed: sizePassed, hint: sizeHint),
            GuideCheck(
                id: "roll", title: "좌우 기울기", passed: rollPassed,
                hint: "폰이 옆으로 기울었어요. 화면 가운데 선이 수평이 되게 맞춰 주세요."
            ),
            GuideCheck(
                id: "pitch", title: "위아래 기울기", passed: pitchPassed,
                hint: pitch > pitchRange.upperBound
                    ? "폰이 너무 위를 보고 있어요. 윗부분을 조금 내려 주세요."
                    : "폰이 너무 아래를 보고 있어요. 윗부분을 조금 들어 주세요."
            )
        ]
    }
}
