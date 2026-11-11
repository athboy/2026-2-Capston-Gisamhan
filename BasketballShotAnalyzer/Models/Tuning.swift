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
    static var backboardHeight: CGFloat { CGFloat(value("backboardHeight")) }
    static var scaleTolerance: CGFloat { CGFloat(value("scaleTolerance")) }
    static var rollSign: Double { value("rollFlip") >= 0.5 ? -1 : 1 }
}
