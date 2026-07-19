//
//  FastSegmentsDTO.swift
//  RunningLog
//
//  Wire format for the `fast_segments` block of the `trends-timeline`
//  response, decoded into the view models in FastSegmentModels.swift. Same
//  snake_case → camelCase DTO pattern as KeySessionDTO in TrendsService.
//
//  The payload is produced by `trends-timeline/fastSegments.ts` from the tested
//  `_shared/fast-segment-trends.ts`; system tokens already match `KeyZone`
//  (mile|3k|5k|10k|hmp|mp — LT folds into HMP at the surface).
//

import Foundation

/// Decoded, view-ready fast-segment data (per-system trends + sessions).
struct FastSegmentsData {
    let systems: [FastSystemTrend]
    let sessions: [FastSession]
    static let empty = FastSegmentsData(systems: [], sessions: [])
    var isEmpty: Bool { systems.isEmpty && sessions.isEmpty }
}

extension VolumeStatus {
    init(token: String?) {
        switch token {
        case "below": self = .below
        case "above": self = .above
        default: self = .inRange
        }
    }
}

/// Root of the `fast_segments` object.
struct FastSegmentsDTO: Decodable {
    let systems: [SystemTrendDTO]
    let sessions: [SessionDTO]

    func toData() -> FastSegmentsData {
        FastSegmentsData(
            systems: systems.compactMap { $0.toModel() },
            sessions: sessions.compactMap { $0.toModel() }
        )
    }

    // MARK: per-system trend

    struct SystemTrendDTO: Decodable {
        let system: String
        let points: [PointDTO]

        func toModel() -> FastSystemTrend? {
            guard let sys = FastSystem(rawValue: system) else { return nil }
            return FastSystemTrend(system: sys, points: points.map { $0.toModel() })
        }
    }

    struct PointDTO: Decodable {
        let sessionId: String
        let dateLabel: String
        let sessionName: String?
        let reps: Int
        let workMiles: Double
        let totalMiles: Double?
        let avgPaceSec: Int
        let neutralPaceSec: Int?
        let conditionsPaceSec: Int?
        let avgHr: Int?
        let volumeStatus: String

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case dateLabel = "date_label"
            case sessionName = "session_name"
            case reps
            case workMiles = "work_miles"
            case totalMiles = "total_miles"
            case avgPaceSec = "avg_pace_sec"
            case neutralPaceSec = "neutral_pace_sec"
            case conditionsPaceSec = "conditions_pace_sec"
            case avgHr = "avg_hr"
            case volumeStatus = "volume_status"
        }

        func toModel() -> FastSystemTrendPoint {
            FastSystemTrendPoint(
                id: sessionId, dateLabel: dateLabel, sessionName: sessionName, reps: reps,
                workMiles: workMiles, totalMiles: totalMiles,
                avgPaceSec: avgPaceSec, neutralPaceSec: neutralPaceSec,
                conditionsPaceSec: conditionsPaceSec, avgHr: avgHr,
                status: VolumeStatus(token: volumeStatus)
            )
        }
    }

    // MARK: session

    struct SessionDTO: Decodable {
        let id: String
        let date: String
        let dateLabel: String
        let name: String?
        let totalMiles: Double?
        let repCount: Int
        let fastMiles: Double
        let avgPaceSec: Int
        let neutralPaceSec: Int?
        let conditionsPaceSec: Int?
        let avgGradePct: Double?
        let avgHr: Int?
        let densityPct: Int
        let avgRestSec: Int
        let metersPerBeat: Double?
        let feelsF: Int?
        let bySystem: [VolumeDTO]

        enum CodingKeys: String, CodingKey {
            case id, date, name
            case totalMiles = "total_miles"
            case dateLabel = "date_label"
            case repCount = "rep_count"
            case fastMiles = "fast_miles"
            case avgPaceSec = "avg_pace_sec"
            case neutralPaceSec = "neutral_pace_sec"
            case conditionsPaceSec = "conditions_pace_sec"
            case avgGradePct = "avg_grade_pct"
            case avgHr = "avg_hr"
            case densityPct = "density_pct"
            case avgRestSec = "avg_rest_sec"
            case metersPerBeat = "meters_per_beat"
            case feelsF = "feels_f"
            case bySystem = "by_system"
        }

        func toModel() -> FastSession {
            FastSession(
                id: id, date: date, dateLabel: dateLabel, name: name ?? "",
                repCount: repCount, fastMiles: fastMiles, avgPaceSec: avgPaceSec,
                neutralPaceSec: neutralPaceSec, avgHr: avgHr, densityPct: densityPct,
                avgRestSec: avgRestSec, metersPerBeat: metersPerBeat, feelsF: feelsF,
                bySystem: bySystem.compactMap { $0.toModel() },
                conditionsPaceSec: conditionsPaceSec, avgGradePct: avgGradePct,
                totalMiles: totalMiles
            )
        }
    }

    struct VolumeDTO: Decodable {
        let system: String
        let reps: Int
        let workMiles: Double
        let avgPaceSec: Int
        let neutralPaceSec: Int?
        let conditionsPaceSec: Int?
        let avgHr: Int?

        enum CodingKeys: String, CodingKey {
            case system, reps
            case workMiles = "work_miles"
            case avgPaceSec = "avg_pace_sec"
            case neutralPaceSec = "neutral_pace_sec"
            case conditionsPaceSec = "conditions_pace_sec"
            case avgHr = "avg_hr"
        }

        func toModel() -> FastSystemVolume? {
            guard let sys = FastSystem(rawValue: system) else { return nil }
            return FastSystemVolume(
                system: sys, reps: reps, workMiles: workMiles, avgPaceSec: avgPaceSec,
                neutralPaceSec: neutralPaceSec, avgHr: avgHr, conditionsPaceSec: conditionsPaceSec
            )
        }
    }
}
