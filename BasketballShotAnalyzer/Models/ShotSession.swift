import Foundation

/// 슛 1개의 기록
struct ShotRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let time: Date
    let measuredAngle: Double
    let targetAngle: Double
    let difference: Double
    let feedback: String      // "perfect" / "flat" / "steep"
    let confidence: Double

    var feedbackTitle: String {
        switch feedback {
        case "perfect": "안정적"
        case "flat": "낮음"
        case "steep": "높음"
        default: "-"
        }
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

    /// 목표각 ±2° 안에 들어온 비율 (0~1)
    var perfectRate: Double {
        guard !shots.isEmpty else { return 0 }
        return Double(shots.filter { $0.feedback == "perfect" }.count) / Double(shots.count)
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

    /// 엑셀에서 열 수 있는 CSV 글자 만들기
    static func csv(for session: ShotSession) -> String {
        var lines = ["번호,시각,측정 입사각,목표 입사각,차이,판정"]
        let formatter = ISO8601DateFormatter()
        for (index, shot) in session.shots.enumerated() {
            lines.append([
                "\(index + 1)",
                formatter.string(from: shot.time),
                String(format: "%.1f", shot.measuredAngle),
                String(format: "%.1f", shot.targetAngle),
                String(format: "%.1f", shot.difference),
                shot.feedbackTitle
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
