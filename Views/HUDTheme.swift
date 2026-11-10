import SwiftUI

// MARK: - 색과 글씨 (여기 숫자만 바꾸면 앱 전체 분위기가 바뀌어요)

enum HUD {
    static let background = Color(red: 0.13, green: 0.13, blue: 0.14)   // 진한 회색 (Nike)
    static let orange = Color(red: 0.93, green: 0.31, blue: 0.15)       // 주황 (Nike)
    static let gold = Color(red: 0.72, green: 0.62, blue: 0.38)         // 금색 (Nike)
    static let cyan = Color(red: 0.27, green: 0.95, blue: 0.95)         // 청록 네온 (HUD)
    static let dim = Color.white.opacity(0.55)                          // 흐린 글씨

    /// 폭이 좁은 굵은 글씨 (Nike 리포트 느낌)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight).width(.condensed)
    }
}

// MARK: - 모서리 괄호 ⌜ ⌝ ⌞ ⌟

struct CornerBrackets: Shape {
    var length: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = length
        // 왼쪽 위
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        // 오른쪽 위
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        // 오른쪽 아래
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        // 왼쪽 아래
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}

// MARK: - 가로선 / 점선

struct HLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// Nike 리포트의 점선 구분선
struct DottedLine: View {
    var body: some View {
        HLine()
            .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
            .frame(height: 1)
    }
}

// MARK: - 소제목 (금색 글씨 + 흰 밑줄)

struct HUDHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(HUD.font(11, .semibold))
                .foregroundStyle(HUD.gold)
            Rectangle()
                .fill(Color.white)
                .frame(height: 1.5)
        }
    }
}

// MARK: - 라벨 박스 ("SHOT ARC" 같은 글자 상자)

struct HUDTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(HUD.font(15, .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.6))
            .overlay(Rectangle().stroke(Color.white, lineWidth: 1.5))
    }
}

// MARK: - 패널 (검은 반투명 + 얇은 테두리 + 작은 모서리 괄호)

struct HUDPanel: ViewModifier {
    var tint: Color

    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.72))
            .overlay(Rectangle().stroke(tint.opacity(0.35), lineWidth: 1))
            .overlay(CornerBrackets(length: 8).stroke(tint, lineWidth: 1.5))
    }
}

extension View {
    func hudPanel(tint: Color = HUD.cyan) -> some View {
        modifier(HUDPanel(tint: tint))
    }
}

// MARK: - 얇은 격자 (HUD 배경 느낌)

struct GridOverlay: View {
    var spacing: CGFloat = 36

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(HUD.cyan.opacity(0.10)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 링 게이지 (Nike의 동그란 그래프)

struct RingGauge: View {
    let progress: Double      // 0 ~ 1
    let label: String         // 가운데 글자
    var color: Color = HUD.orange

    var body: some View {
        ZStack {
            Circle()
                .stroke(HUD.gold.opacity(0.35), lineWidth: 7)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                .padding(11)
            Text(label)
                .font(HUD.font(15).monospacedDigit())
                .foregroundStyle(Color.white)
        }
    }
}

// MARK: - 미니맵 (왼쪽 위 작은 지도 느낌: 마지막 슛의 포물선과 림 위치)

struct ArcMapView: View {
    let path: [NormalizedPoint]
    let rim: RimCalibration?

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            ZStack {
                Color.black.opacity(0.5)

                // 격자
                Path { p in
                    for i in 1..<6 {
                        let x = w * CGFloat(i) / 6
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                    }
                    for i in 1..<4 {
                        let y = h * CGFloat(i) / 4
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(HUD.cyan.opacity(0.18), lineWidth: 0.5)

                // 마지막 슛의 포물선
                Path { p in
                    for (i, pt) in path.enumerated() {
                        let point = CGPoint(x: w * pt.x, y: h * (1 - pt.y))
                        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                .stroke(Color.white, lineWidth: 1.5)

                // 림 위치
                if let rim {
                    Circle()
                        .fill(HUD.cyan)
                        .frame(width: 7, height: 7)
                        .position(x: w * rim.center.x, y: h * (1 - rim.center.y))
                }
            }
            .overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 1))
        }
    }
}
