import CoreGraphics
import Foundation

/// 보정 순서 (지금 어느 단계인지)
enum CalibrationStep: Equatable, Sendable {
    case off              // 보정 중 아님
    case rim              // ① 림 지정
    case backboardTop     // ② 백보드 위쪽 끝 탭
    case backboardBottom  // ③ 백보드 아래쪽 끝 탭
    case review           // ④ 확인하고 고정
}

/// 백보드 기준점 2개 (측면에서 보면 얇은 막대라서 위/아래 끝만 사용)
struct BackboardReference: Equatable, Sendable {
    var top: NormalizedPoint
    var bottom: NormalizedPoint
}

/// 보정 결과 = "화면 → 실제 미터" 눈금자 + 폰 기울기 정보
struct CameraCalibration: Equatable, Sendable {

    // MARK: - 기준값 (코트에 맞게 여기 숫자를 바꾸세요)

    /// 백보드 실제 높이 (m). 국제 규격 1.05
    static let backboardHeightMeters: CGFloat = 1.05
    /// 카메라 프레임의 세로/가로 비율 (1080x1920 세로 영상)
    static let frameRatio: CGFloat = 1920.0 / 1080.0
    /// 림 눈금자와 백보드 눈금자가 이 비율 이내로 맞아야 통과 (0.15 = 15%)
    static let scaleTolerance: CGFloat = 0.15
    /// 백보드 위/아래 점 사이의 최소 거리 (화면 세로 비율)
    static let minBackboardHeightFraction: CGFloat = 0.03
    /// 롤 보정 방향. 코트에서 확인했을 때 반대로 보정되면 -1 로 바꾸세요.
    static let rollSign: Double = 1

    // MARK: - 저장되는 값

    let rim: RimCalibration
    let backboard: BackboardReference
    /// 보정을 고정한 순간의 폰 좌우 기울기 (도)
    let rollDegrees: Double
    /// 보정을 고정한 순간의 폰 위아래 기울기 (도)
    let pitchDegrees: Double
    let heightToWidthRatio: CGFloat

    // MARK: - 눈금자 계산

    private var pitchCos: CGFloat {
        CGFloat(max(cos(pitchDegrees * Double.pi / 180), 0.5))
    }

    /// 림으로 구한 눈금자: (화면 가로폭 단위) / 미터
    var scaleFromRim: CGFloat {
        rim.widthFraction / RimCalibration.regulationDiameterMeters
    }

    /// 백보드로 구한 눈금자: (화면 가로폭 단위) / 미터
    var scaleFromBackboard: CGFloat {
        let heightInWidthUnits = abs(backboard.top.y - backboard.bottom.y) * heightToWidthRatio
        return heightInWidthUnits / pitchCos / Self.backboardHeightMeters
    }

    /// 1이면 두 눈금자가 똑같다는 뜻
    var scaleAgreement: CGFloat {
        let bb = scaleFromBackboard
        return bb > 0 ? scaleFromRim / bb : 0
    }

    /// 두 눈금자의 평균 (더 믿을 만한 눈금자)
    var scale: CGFloat { (scaleFromRim + scaleFromBackboard) / 2 }

    /// 평균 눈금자를 반영해 다시 만든 림 (ShotPhysics가 그대로 쓸 수 있어요)
    var calibratedRim: RimCalibration {
        RimCalibration(
            center: rim.center,
            widthFraction: scale * RimCalibration.regulationDiameterMeters
        )
    }

    /// 위아래 기울기(피치)로 줄어든 세로 길이를 되돌린 비율
    var effectiveHeightToWidthRatio: CGFloat { heightToWidthRatio / pitchCos }

    // MARK: - 입사각 (롤/피치 보정 포함)

    /// 포물선 y = a·x² + b·x + c 의 x 지점에서의 보정된 입사각 (도)
    func entryAngle(a: CGFloat, b: CGFloat, atX x: CGFloat) -> Double? {
        let slope = Double(2 * a * x + b)
        let ratio = Double(heightToWidthRatio)

        // 1) 화면에서 보이는 선의 각도
        var angle = atan(ratio * slope)

        // 2) 폰이 기운 만큼 되돌리기 (롤)
        angle -= rollDegrees * Self.rollSign * Double.pi / 180

        // 3) 각도를 -90° ~ 90° 안으로 정리
        while angle > Double.pi / 2 { angle -= Double.pi }
        while angle <= -Double.pi / 2 { angle += Double.pi }

        // 4) 피치로 줄어든 세로 길이 되돌리기
        let vx = cos(angle)
        let vy = sin(angle) / Double(pitchCos)
        let degrees = atan2(abs(vy), abs(vx)) * 180 / Double.pi
        return degrees.isFinite ? degrees : nil
    }

    // MARK: - 만들기

    static func make(
        rim: RimCalibration,
        backboard: BackboardReference,
        pitch: Double,
        roll: Double
    ) -> CameraCalibration? {
        guard abs(backboard.top.y - backboard.bottom.y) >= minBackboardHeightFraction else { return nil }
        return CameraCalibration(
            rim: rim,
            backboard: backboard,
            rollDegrees: roll,
            pitchDegrees: pitch,
            heightToWidthRatio: frameRatio
        )
    }

    // MARK: - 적정성 검사 (5가지)

    static func evaluate(
        rim: RimCalibration?,
        backboard: BackboardReference?,
        pitch: Double,
        roll: Double
    ) -> [GuideCheck] {
        var backboardPassed = false
        var backboardHint = "백보드의 위쪽 끝과 아래쪽 끝을 탭해 주세요."
        var agreePassed = false
        var agreeHint = "림과 백보드를 모두 지정하면 확인해요."
        var heightPassed = false
        var heightHint = "림과 백보드를 모두 지정하면 확인해요."

        if let backboard {
            let h = abs(backboard.top.y - backboard.bottom.y)
            backboardPassed = h >= minBackboardHeightFraction
            backboardHint = backboardPassed ? "" : "백보드 위·아래 점이 너무 가까워요. 다시 탭해 주세요."

            if backboardPassed, let rim,
               let cal = make(rim: rim, backboard: backboard, pitch: pitch, roll: roll) {
                // 림 눈금자와 백보드 눈금자가 서로 맞는지
                let ratio = cal.scaleAgreement
                agreePassed = abs(ratio - 1) <= scaleTolerance
                if agreePassed {
                    agreeHint = ""
                } else if ratio > 1 {
                    agreeHint = "림이 백보드에 비해 너무 커 보여요. 림 폭을 줄이거나 백보드 점을 다시 찍어 주세요."
                } else {
                    agreeHint = "림이 백보드에 비해 너무 작아 보여요. 림 폭을 키우거나 백보드 점을 다시 찍어 주세요."
                }

                // 림은 백보드의 아래쪽 끝보다 위, 위쪽 끝보다 아래에 있어야 해요
                heightPassed = rim.center.y <= backboard.top.y
                    && rim.center.y >= backboard.bottom.y - 0.02
                heightHint = heightPassed ? "" : "림이 백보드 높이 범위 밖이에요. 림이나 백보드 점을 다시 찍어 주세요."
            }
        }

        let tiltPassed = abs(roll) <= ShootingGuide.maxRoll && ShootingGuide.pitchRange.contains(pitch)
        var tiltHint = ""
        if !tiltPassed {
            if abs(roll) > ShootingGuide.maxRoll {
                tiltHint = "폰이 옆으로 기울었어요. 수평선이 초록색이 되게 맞춰 주세요."
            } else if pitch > ShootingGuide.pitchRange.upperBound {
                tiltHint = "폰이 너무 위를 보고 있어요. 윗부분을 조금 내려 주세요."
            } else {
                tiltHint = "폰이 너무 아래를 보고 있어요. 윗부분을 조금 들어 주세요."
            }
        }

        return [
            GuideCheck(id: "cal-rim", title: "림 기준점", passed: rim != nil,
                       hint: "림 중심을 탭하고 림 폭을 맞춰 주세요."),
            GuideCheck(id: "cal-bb", title: "백보드 기준점", passed: backboardPassed, hint: backboardHint),
            GuideCheck(id: "cal-agree", title: "림·백보드 크기 일치", passed: agreePassed, hint: agreeHint),
            GuideCheck(id: "cal-height", title: "림이 백보드 높이 안", passed: heightPassed, hint: heightHint),
            GuideCheck(id: "cal-tilt", title: "카메라 기울기", passed: tiltPassed, hint: tiltHint)
        ]
    }
}
