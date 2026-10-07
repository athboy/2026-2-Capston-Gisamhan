import CoreGraphics

/// 검사 항목 하나 (예: "림 위치 ✅")
struct GuideCheck: Identifiable, Equatable, Sendable {
    let id: String
    let title: String    // 화면에 보일 이름
    let passed: Bool     // 통과했나요?
    let hint: String     // 통과 못 했을 때 알려줄 말
}

enum ShootingGuide {
    // MARK: - 기준값 (필요하면 여기 숫자를 바꾸세요)

    /// 림이 와야 할 자리 (화면 비율, 왼쪽 아래가 (0,0))
    static let targetY: CGFloat = 0.70
    static let targetXRight: CGFloat = 0.80   // 림이 오른쪽에 있을 때
    static let targetXLeft: CGFloat = 0.20    // 림이 왼쪽에 있을 때

    /// 림이 점선 박스에서 벗어나도 되는 허용 범위
    static let toleranceX: CGFloat = 0.10
    static let toleranceY: CGFloat = 0.06

    /// 림 폭 허용 범위 (대략 카메라에서 림까지 4~9m)
    static let widthRange: ClosedRange<CGFloat> = 0.05...0.11

    /// 좌우 기울기 허용 (도)
    static let maxRoll: Double = 3
    /// 위아래 기울기 허용 (도): 카메라가 위를 보면 +, 아래를 보면 -
    static let pitchRange: ClosedRange<Double> = -5...10

    static func targetCenter(rimOnRight: Bool) -> NormalizedPoint {
        NormalizedPoint(x: rimOnRight ? targetXRight : targetXLeft, y: targetY)
    }

    // MARK: - 5가지 검사

    static func evaluate(
        rim: RimCalibration?,
        pitch: Double,
        roll: Double,
        rimOnRight: Bool
    ) -> [GuideCheck] {
        let target = targetCenter(rimOnRight: rimOnRight)

        var positionPassed = false
        var positionHint = "먼저 림을 인식시켜 주세요."
        var sizePassed = false
        var sizeHint = "먼저 림을 인식시켜 주세요."

        if let rim {
            // 위치 검사: 림 중심이 박스 안에 있는지
            let dx = rim.center.x - target.x
            let dy = rim.center.y - target.y
            positionPassed = abs(dx) <= toleranceX && abs(dy) <= toleranceY
            if positionPassed {
                positionHint = ""
            } else if abs(dx) / toleranceX >= abs(dy) / toleranceY {
                // 림이 박스보다 왼쪽이면 폰을 왼쪽으로 돌려야 림이 오른쪽(박스 쪽)으로 와요
                positionHint = dx < 0
                    ? "림이 박스보다 왼쪽에 있어요. 폰을 왼쪽으로 살짝 돌려 주세요."
                    : "림이 박스보다 오른쪽에 있어요. 폰을 오른쪽으로 살짝 돌려 주세요."
            } else {
                positionHint = dy > 0
                    ? "림이 박스보다 위에 있어요. 폰을 위로 살짝 들어 올려 주세요."
                    : "림이 박스보다 아래에 있어요. 폰을 아래로 살짝 내려 주세요."
            }

            // 크기 검사: 림이 너무 작으면 멀리 있는 것, 너무 크면 가까운 것
            sizePassed = widthRange.contains(rim.widthFraction)
            if sizePassed {
                sizeHint = ""
            } else if rim.widthFraction < widthRange.lowerBound {
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
