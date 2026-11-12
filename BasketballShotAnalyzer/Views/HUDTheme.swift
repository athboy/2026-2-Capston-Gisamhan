import SwiftUI

// MARK: - 색과 글씨 (Nike Run Club 다크 테마)

enum HUD {
    static let background = Color(red: 0.06, green: 0.06, blue: 0.07)   // 딥 매트 블랙
    static let orange = Color(red: 1.00, green: 0.33, blue: 0.12)       // 나이키 크림슨 오렌지
    static let gold = Color(red: 0.90, green: 0.96, blue: 0.24)         // 나이키 볼트(네온 옐로우)
    static let cyan = Color(red: 0.20, green: 0.90, blue: 0.95)         // 스포츠 시안
    static let dim = Color.white.opacity(0.60)                          // 보조 텍스트

    /// 스포티한 응축 폰트
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .default).width(.condensed)
    }
}

// MARK: - 뷰파인더 모서리 가이드

struct CornerBrackets: Shape {
    var length: CGFloat = 20

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

// MARK: - 구분선

struct HLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

struct DottedLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
    }
}

// MARK: - 섹션 헤더

struct HUDHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(HUD.gold)
                .frame(width: 3, height: 12)
            Text(title)
                .font(HUD.font(12, .heavy))
                .tracking(0.8)
                .foregroundStyle(HUD.gold)
        }
    }
}

// MARK: - 캡슐형 라벨 태그 ("SHOT ARC" 등)

struct HUDTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(HUD.font(13, .bold))
            .tracking(0.5)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - 모던 스포츠 카드 패널

struct HUDPanel: ViewModifier {
    var tint: Color

    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.45), lineWidth: 1)
            )
    }
}

extension View {
    func hudPanel(tint: Color = HUD.cyan) -> some View {
        modifier(HUDPanel(tint: tint))
    }
}

// MARK: - 은은한 배경 그리드 (시야 방해 최소화)

struct GridOverlay: View {
    var spacing: CGFloat = 48

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
            context.stroke(path, with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 원형 링 게이지

struct RingGauge: View {
    let progress: Double
    let label: String
    var color: Color = HUD.orange

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(HUD.font(14, .heavy).monospacedDigit())
                .foregroundStyle(Color.white)
        }
    }
}

// MARK: - 궤적 미니맵

struct ArcMapView: View {
    let path: [NormalizedPoint]
    let rim: RimCalibration?

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            ZStack {
                Color.white.opacity(0.06)

                Path { p in
                    for (i, pt) in path.enumerated() {
                        let point = CGPoint(x: w * pt.x, y: h * (1 - pt.y))
                        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                .stroke(HUD.gold, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let rim {
                    Circle()
                        .fill(HUD.cyan)
                        .frame(width: 7, height: 7)
                        .position(x: w * rim.center.x, y: h * (1 - rim.center.y))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }
}
