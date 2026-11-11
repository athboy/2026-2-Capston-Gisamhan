import Foundation
import SwiftUI

/// ⭐ 추가: 목표 입사각 (45° ±2°)
enum ShotTarget {
    static let angle = 45.0
    static let tolerance = 2.0
}

/// ⭐ 추가: 점 색 (파랑 = 골, 빨강 = 노골)
enum ShotColor {
    static let made = Color(red: 0.25, green: 0.55, blue: 1.0)
    static let miss = Color(red: 0.95, green: 0.25, blue: 0.22)
    static let unknown = Color.gray

    /// 판정이 없는 옛 기록(nil)은 회색으로 보여요
    static func color(for result: Bool?) -> Color {
        switch result {
        case .some(true): return made
        case .some(false): return miss
        case .none: return unknown
        }
    }
}

/// 슛 1개의 기록
struct ShotRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let time: Date
    let measuredAngle: Double
    let targetAngle: Double
    let difference: Double
    let feedback: String      // 예전 호환용 (지금은 각도로 다시 계산해요)
    let confidence: Double
    /// ⭐ 추가: 골 여부 (옛 기록은 nil)
    var made: Bool? = nil

    /// ⭐ 45° 기준으로 다시 계산 (옛 기록도 45° 기준으로 보여요)
    var diffFromTarget: Double { measuredAngle - ShotTarget.angle }
    var isPerfect: Bool { abs(diffFromTarget) <= ShotTarget.tolerance }

    var feedbackTitle: String {
        if isPerfect { "안정적" } else if diffFromTarget < 0 { "낮음" } else { "높음" }
    }
}

/// 한 번 촬영한 기록 묶음
struct ShotSession: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date
    var calibrated: Bool
    var landscape: Bool
    var shots: [ShotRecord]

    var averageAngle: Double? {
        guard !shots.isEmpty else { return nil }
        return shots.map(\.measuredAngle).reduce(0, +) / Double(shots.count)
    }

    /// 편차 (작을수록 일관된 슛)
    var spread: Double? {
        guard shots.count >= 2, let mean = averageAngle else { return nil }
        let variance = shots.map { pow($0.measuredAngle - mean, 2) }.reduce(0, +) / Double(shots.count)
        return variance.squareRoot()
    }

    /// 목표 45° ±2° 안에 들어온 비율 (0~1)
    var perfectRate: Double {
        guard !shots.isEmpty else { return 0 }
        return Double(shots.filter(\.isPerfect).count) / Double(shots.count)
    }

    // ⭐ 추가: 골 관련
    var hasMadeData: Bool { shots.contains { $0.made != nil } }
    var madeCount: Int { shots.filter { $0.made == true }.count }
    var madeRate: Double {
        guard !shots.isEmpty else { return 0 }
        return Double(madeCount) / Double(shots.count)
    }
}

/// 파일로 저장하고 불러오기
enum SessionStore {
    private static var fileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sessions.json")
    }

    static func load() -> [ShotSession] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sessions = (try? decoder.decode([ShotSession].self, from: data)) ?? []
        return sessions.sorted { $0.startedAt > $1.startedAt }   // 최신이 위로
    }

    private static func write(_ sessions: [ShotSession]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 같은 id가 있으면 덮어쓰고, 없으면 새로 추가
    static func save(_ session: ShotSession) {
        var all = load()
        if let index = all.firstIndex(where: { $0.id == session.id }) {
            all[index] = session
        } else {
            all.append(session)
        }
        write(all)
    }

    static func delete(ids: [UUID]) {
        write(load().filter { !ids.contains($0.id) })
    }

    /// 엑셀에서 열 수 있는 CSV 글자 만들기 (⭐ 골 여부 칸 추가)
    static func csv(for session: ShotSession) -> String {
        var lines = ["번호,시각,측정 입사각,목표 입사각,차이,판정,골 여부"]
        let formatter = ISO8601DateFormatter()
        for (index, shot) in session.shots.enumerated() {
            let goal: String
            switch shot.made {
            case .some(true): goal = "골"
            case .some(false): goal = "노골"
            case .none: goal = "-"
            }
            lines.append([
                "\(index + 1)",
                formatter.string(from: shot.time),
                String(format: "%.1f", shot.measuredAngle),
                String(format: "%.1f", ShotTarget.angle),
                String(format: "%.1f", shot.diffFromTarget),
                shot.feedbackTitle,
                goal
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
