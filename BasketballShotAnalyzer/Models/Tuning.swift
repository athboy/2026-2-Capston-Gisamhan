import Foundation
import CoreGraphics

/// 코트에서 앱 안에서 바로 바꿀 수 있는 기준 숫자들
enum Tuning {
    enum Kind: Sendable { case slider, toggle }

    struct Item: Identifiable, Sendable {
        let id: String
        let title: String
        let detail: String
        let range: ClosedRange<Double>
        let step: Double
        let defaultValue: Double
        let kind: Kind
        let unit: String
    }

    static let items: [Item] = [
        Item(id: "ballConfidence", title: "공 확신도",
             detail: "높이면 엄격해져요(안 던졌는데 선이 뜰 때). 낮추면 민감해져요(진짜 슛이 안 잡힐 때).",
             range: 0.5...0.95, step: 0.05, defaultValue: 0.8, kind: .slider, unit: ""),
        Item(id: "ballMinSpan", title: "공 최소 이동 거리",
             detail: "제자리에서 흔들리는 것을 무시하는 기준이에요. 높이면 더 많이 움직여야 공으로 인정해요.",
             range: 0.04...0.25, step: 0.01, defaultValue: 0.10, kind: .slider, unit: ""),
        Item(id: "ballFitError", title: "포물선 허용 오차",
             detail: "점들이 포물선에서 벗어나도 되는 정도예요. 낮추면 엄격, 높이면 관대해요.",
             range: 0.005...0.05, step: 0.005, defaultValue: 0.02, kind: .slider, unit: ""),

        // ⭐ 추가: 슛 개수를 정확하게 세기 위한 기준 3개
        Item(id: "shotCooldown", title: "슛 사이 대기 시간",
             detail: "슛 하나가 기록된 뒤 이 시간 동안은 새 슛을 세지 않아요. 던진 수보다 많이 기록되면 늘리고, 연달아 던진 슛을 놓치면 줄이세요.",
             range: 2...10, step: 0.5, defaultValue: 5.0, kind: .slider, unit: "초"),
        Item(id: "shotMinStart", title: "슛 최소 출발 거리",
             detail: "림에서 화면 가로의 이만큼 이상 떨어진 곳에서 시작한 공만 슛으로 세요. 림 근처에서 튕기는 공을 거르는 기준이에요. 높이면 더 멀리서 던진 공만 인정해요.",
             range: 0.05...0.40, step: 0.01, defaultValue: 0.15, kind: .slider, unit: ""),
        Item(id: "makeRange", title: "골 판정 범위",
             detail: "공이 림 높이를 지날 때 림 중심에서 림 반지름의 이 배수 안이면 골로 봐요. 노골인데 골로 나오면 낮추고, 골인데 노골로 나오면 높이세요.",
             range: 0.4...1.5, step: 0.05, defaultValue: 0.8, kind: .slider, unit: "배"),

        Item(id: "backboardHeight", title: "백보드 실제 높이",
             detail: "코트 백보드를 줄자로 재서 맞춰 주세요. 국제 규격은 1.05m예요.",
             range: 0.8...1.3, step: 0.01, defaultValue: 1.05, kind: .slider, unit: "m"),
        Item(id: "scaleTolerance", title: "림·백보드 크기 일치 허용치",
             detail: "림과 백보드를 정확히 찍었는데도 ❌가 자주 뜨면 높여 보세요.",
             range: 0.05...0.40, step: 0.05, defaultValue: 0.15, kind: .slider, unit: ""),
        Item(id: "rollFlip", title: "롤 보정 방향 뒤집기",
             detail: "폰을 일부러 기울여 찍었을 때 평균 각도 차이가 더 벌어지면 켜 주세요.",
             range: 0...1, step: 1, defaultValue: 0, kind: .toggle, unit: "")
    ]

    private static func key(_ id: String) -> String { "tune." + id }

    static func value(_ id: String) -> Double {
        if let saved = UserDefaults.standard.object(forKey: key(id)) as? Double { return saved }
        return items.first { $0.id == id }?.defaultValue ?? 0
    }

    static func set(_ value: Double, for id: String) {
        UserDefaults.standard.set(value, forKey: key(id))
    }

    static func reset() {
        for item in items { UserDefaults.standard.removeObject(forKey: key(item.id)) }
    }

    // 다른 파일에서 쓰기 편하게 이름을 붙여 둔 값들
    static var ballConfidence: Float { Float(value("ballConfidence")) }
    static var ballMinSpan: CGFloat { CGFloat(value("ballMinSpan")) }
    static var ballFitError: CGFloat { CGFloat(value("ballFitError")) }
    static var shotCooldown: Double { value("shotCooldown") }             // ⭐
    static var shotMinStart: CGFloat { CGFloat(value("shotMinStart")) }   // ⭐
    static var makeRange: CGFloat { CGFloat(value("makeRange")) }         // ⭐
    static var backboardHeight: CGFloat { CGFloat(value("backboardHeight")) }
    static var scaleTolerance: CGFloat { CGFloat(value("scaleTolerance")) }
    static var rollSign: Double { value("rollFlip") >= 0.5 ? -1 : 1 }
}
